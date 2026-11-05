variable "aws_region" {
  description = "AWS region where the API Gateway is created."
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "Expected AWS account ID. Guards the provider against deploying to the wrong account. Empty = no restriction (local validation)."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Deployment environment (develop, main). Drives the stage name and state keys."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.environment))
    error_message = "environment may contain only letters, numbers, underscores, and hyphens."
  }
}

variable "api_name" {
  description = "Name of the API Gateway REST API."
  type        = string
  default     = "os-management-gateway"
}

variable "origin_url" {
  description = "Base URL of the OS Management backend (the app on Kubernetes), e.g. https://app.example.com."
  type        = string

  validation {
    condition     = can(regex("^https?://[^/]+(:[0-9]+)?(/.*)?$", var.origin_url))
    error_message = "origin_url must be an absolute HTTP or HTTPS URL."
  }
}

variable "lambda_name_prefix" {
  description = <<-EOT
    Prefix os-management-lambda uses for its function names (its own `name_prefix`
    variable). The gateway derives `<prefix>-issuer-<env>` and
    `<prefix>-authorizer-<env>` from it instead of reading that repo's Terraform
    state, which is what lets the two deploy in any order.
  EOT
  type        = string
  default     = "os-auth"
}

variable "issuer_function_name" {
  description = "Overrides the derived issuer function name. Empty = derive it."
  type        = string
  default     = ""
}

variable "authorizer_function_name" {
  description = "Overrides the derived authorizer function name. Empty = derive it."
  type        = string
  default     = ""
}

variable "issuer_invoke_arn" {
  description = "Overrides the derived issuer invoke ARN. Empty = derive it."
  type        = string
  default     = ""
}

variable "authorizer_invoke_arn" {
  description = "Overrides the derived authorizer invoke ARN. Empty = derive it."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional AWS tags."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Retention for the API Gateway access-log group."
  type        = number
  default     = 14
}

variable "manage_apigw_account" {
  description = <<-EOT
    Manage the account-level API Gateway CloudWatch Logs role (required for access logs).
    This is a singleton per region/account — set to false if another stack already owns it.
  EOT
  type        = bool
  default     = true
}

variable "throttle_rate_limit" {
  description = "Steady-state requests/second applied to every route."
  type        = number
  default     = 50
}

variable "throttle_burst_limit" {
  description = "Burst capacity applied to every route."
  type        = number
  default     = 100
}

variable "auth_throttle_rate_limit" {
  description = "Tighter steady-state requests/second for the unauthenticated POST /auth route."
  type        = number
  default     = 5
}

variable "auth_throttle_burst_limit" {
  description = "Tighter burst capacity for the unauthenticated POST /auth route."
  type        = number
  default     = 10
}
