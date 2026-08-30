output "api_id" {
  description = "ID of the OS Management REST API."
  value       = aws_api_gateway_rest_api.os_management.id
}

output "invoke_url" {
  description = "Base URL for the deployed API Gateway stage."
  value       = aws_api_gateway_stage.os_management.invoke_url
}

output "auth_endpoint" {
  description = "Full URL of the CPF authentication endpoint."
  value       = "${aws_api_gateway_stage.os_management.invoke_url}/auth"
}
