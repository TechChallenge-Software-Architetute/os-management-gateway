terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
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

# The REST API type supports the greedy proxy resource needed to forward any
# HTTP verb and any path below the API Gateway invoke URL.
resource "aws_api_gateway_rest_api" "os_management" {
  name        = var.api_name
  description = "Public proxy for the OS Management API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Produces the API Gateway route: ANY /{proxy+}.
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id
  parent_id   = aws_api_gateway_rest_api.os_management.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.os_management.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"

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

resource "aws_api_gateway_deployment" "os_management" {
  rest_api_id = aws_api_gateway_rest_api.os_management.id

  triggers = {
    redeployment = sha1(jsonencode([
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
  stage_name    = var.stage_name

  tags = {
    Name = "${var.api_name}-${var.stage_name}"
  }
}
