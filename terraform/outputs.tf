output "api_id" {
  description = "ID of the OS Management REST API."
  value       = aws_api_gateway_rest_api.os_management.id
}

output "proxy_route" {
  description = "Catch-all API Gateway route."
  value       = "ANY /{proxy+}"
}

output "invoke_url" {
  description = "Base URL for the deployed API Gateway stage. Append an OS Management path, such as /clients."
  value       = "https://${aws_api_gateway_rest_api.os_management.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.os_management.stage_name}"
}
