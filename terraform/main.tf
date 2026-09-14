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

  # Guardrail: fail fast if the active credentials point at an unexpected account.
  # Empty (local validation) = no restriction; CI sets TF_VAR_aws_account_id.
  allowed_account_ids = var.aws_account_id != "" ? [var.aws_account_id] : []

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
# Public route: POST /auth/login -> backend app (staff login, no authorization)
# =============================================================================
# Staff authenticate tokenless (email/senha), so this route must bypass the JWT
# authorizer just like POST /auth does. Being a specific resource, it takes
# precedence over the greedy ANY /{proxy+}. It proxies straight to the backend
# (HTTP_PROXY), which mints the staff JWT. Once staff hold a token, every other
# route reaches the backend through /{proxy+} (the authorizer accepts any token
# signed with the shared JWT_SECRET; the backend enforces roles).

resource "aws_api_gateway_resource" "auth_login" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id
  parent_id   = aws_api_gateway_resource.auth.id
  path_part   = "login"
}

resource "aws_api_gateway_method" "auth_login_post" {
  rest_api_id   = aws_api_gateway_rest_api.os_management.id
  resource_id   = aws_api_gateway_resource.auth_login.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "auth_login_post" {
  rest_api_id             = aws_api_gateway_rest_api.os_management.id
  resource_id             = aws_api_gateway_resource.auth_login.id
  http_method             = aws_api_gateway_method.auth_login_post.http_method
  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  uri                     = "${trimsuffix(var.origin_url, "/")}/auth/login"
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
# Observability — structured (JSON) access logs + X-Ray
# =============================================================================
# REST API access/execution logs require an account-level CloudWatch Logs role.
# That setting is a singleton per region/account: set manage_apigw_account = false
# if another stack already owns it.

resource "aws_iam_role" "apigw_cloudwatch" {
  count = var.manage_apigw_account ? 1 : 0
  name  = "${var.api_name}-${var.environment}-apigw-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  count      = var.manage_apigw_account ? 1 : 0
  role       = aws_iam_role.apigw_cloudwatch[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  count               = var.manage_apigw_account ? 1 : 0
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch[0].arn

  depends_on = [aws_iam_role_policy_attachment.apigw_cloudwatch]
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.api_name}-${var.environment}/access"
  retention_in_days = var.log_retention_days
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
      aws_api_gateway_resource.auth_login.id,
      aws_api_gateway_method.auth_login_post.id,
      aws_api_gateway_integration.auth_login_post.id,
      aws_api_gateway_integration.auth_login_post.uri,
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
  rest_api_id          = aws_api_gateway_rest_api.os_management.id
  deployment_id        = aws_api_gateway_deployment.os_management.id
  stage_name           = var.environment
  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      resourcePath       = "$context.resourcePath"
      path               = "$context.path"
      status             = "$context.status"
      protocol           = "$context.protocol"
      responseLatency    = "$context.responseLatency"
      integrationLatency = "$context.integrationLatency"
      integrationStatus  = "$context.integrationStatus"
      principalId        = "$context.authorizer.principalId"
      clientId           = "$context.authorizer.clientId"
      authorizerError    = "$context.authorizer.error"
      sourceIp           = "$context.identity.sourceIp"
      userAgent          = "$context.identity.userAgent"
      errorMessage       = "$context.error.message"
    })
  }

  tags = {
    Name = "${var.api_name}-${var.environment}"
  }

  depends_on = [aws_api_gateway_account.this]
}

# Default throttling for every route + a tighter cap on the unauthenticated /auth route
# (CPF enumeration guard).
resource "aws_api_gateway_method_settings" "default" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id
  stage_name  = aws_api_gateway_stage.os_management.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.throttle_rate_limit
    throttling_burst_limit = var.throttle_burst_limit
    metrics_enabled        = true
  }
}

resource "aws_api_gateway_method_settings" "auth" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id
  stage_name  = aws_api_gateway_stage.os_management.stage_name
  method_path = "${aws_api_gateway_resource.auth.path_part}/${aws_api_gateway_method.auth_post.http_method}"

  settings {
    throttling_rate_limit  = var.auth_throttle_rate_limit
    throttling_burst_limit = var.auth_throttle_burst_limit
    metrics_enabled        = true
  }
}

# Same tighter cap on the public staff login route (brute-force guard).
resource "aws_api_gateway_method_settings" "auth_login" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id
  stage_name  = aws_api_gateway_stage.os_management.stage_name
  method_path = "${aws_api_gateway_resource.auth.path_part}/${aws_api_gateway_resource.auth_login.path_part}/${aws_api_gateway_method.auth_login_post.http_method}"

  settings {
    throttling_rate_limit  = var.auth_throttle_rate_limit
    throttling_burst_limit = var.auth_throttle_burst_limit
    metrics_enabled        = true
  }
}
