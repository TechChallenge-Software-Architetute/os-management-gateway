variable "aws_region" {
  description = "AWS region where the API Gateway is created."
  type        = string
  sensitive   = true
}

variable "origin_url" {
  description = "Base URL of the OS Management service, for example http://203.0.113.10:8080."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^https?://[^/]+(:[0-9]+)?(/.*)?$", var.origin_url))
    error_message = "origin_url must be an absolute HTTP or HTTPS URL."
  }
}

variable "api_name" {
  description = "Name of the API Gateway REST API."
  type        = string
  default     = "os-management-gateway"
}

variable "stage_name" {
  description = "API Gateway stage name."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.stage_name))
    error_message = "stage_name may contain only letters, numbers, underscores, and hyphens."
  }
}

variable "tags" {
  description = "Additional AWS tags."
  type        = map(string)
  default     = {}
}
