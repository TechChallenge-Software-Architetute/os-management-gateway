terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Configured by CI via -backend-config; `terraform init -backend=false` works for validation.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge({
      Project   = "os-management"
      Component = "api-gateway"
      ManagedBy = "Terraform"
    }, var.tags)
  }
}

resource "aws_api_gateway_rest_api" "os_management" {
  name        = var.api_name
  description = "Public entry point for the OS Management platform (auth + protected proxy)."

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# =============================================================================
# Public route: POST /auth -> auth issuer Lambda (no authorization)
# =============================================================================

resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id
  parent_id   = aws_api_gateway_rest_api.os_management.root_resource_id
  path_part   = "auth"
}

resource "aws_api_gateway_method" "auth_post" {
  rest_api_id   = aws_api_gateway_rest_api.os_management.id
  resource_id   = aws_api_gateway_resource.auth.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "auth_post" {
  rest_api_id             = aws_api_gateway_rest_api.os_management.id
  resource_id             = aws_api_gateway_resource.auth.id
  http_method             = aws_api_gateway_method.auth_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.issuer_invoke_arn
}

resource "aws_lambda_permission" "apigw_invoke_issuer" {
  statement_id  = "AllowAPIGatewayInvokeIssuer"
  action        = "lambda:InvokeFunction"
  function_name = local.issuer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.os_management.execution_arn}/*/POST/auth"
}

# =============================================================================
# TOKEN authorizer (validates the JWT on protected routes)
# =============================================================================

resource "aws_api_gateway_authorizer" "jwt" {
  name                             = "${var.api_name}-jwt-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.os_management.id
  type                             = "TOKEN"
  identity_source                  = "method.request.header.Authorization"
  authorizer_uri                   = local.authorizer_invoke_arn
  authorizer_result_ttl_in_seconds = 300
}

resource "aws_lambda_permission" "apigw_invoke_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = local.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.os_management.execution_arn}/authorizers/${aws_api_gateway_authorizer.jwt.id}"
}

# =============================================================================
# Protected routes: ANY /{proxy+} -> backend, guarded by the authorizer
# =============================================================================

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id
  parent_id   = aws_api_gateway_rest_api.os_management.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.os_management.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# HTTP_PROXY keeps the original method, body, query string, and greedy path.
resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.os_management.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "${trimsuffix(var.origin_url, "/")}/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

# =============================================================================
# Deployment + stage
# =============================================================================

resource "aws_api_gateway_deployment" "os_management" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.auth.id,
      aws_api_gateway_method.auth_post.id,
      aws_api_gateway_integration.auth_post.id,
      aws_api_gateway_authorizer.jwt.id,
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy.id,
      aws_api_gateway_integration.proxy.uri,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "os_management" {
  rest_api_id   = aws_api_gateway_rest_api.os_management.id
  deployment_id = aws_api_gateway_deployment.os_management.id
  stage_name    = var.environment

  tags = {
    Name = "${var.api_name}-${var.environment}"
  }
}
