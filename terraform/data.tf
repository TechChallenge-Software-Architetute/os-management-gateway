# Reads the auth Lambda functions (issuer + authorizer) from the os-management-lambda
# Terraform state, so their invoke ARNs don't have to be passed in manually.
data "terraform_remote_state" "lambda" {
  backend = "s3"
  config = {
    bucket = var.lambda_state_bucket
    key    = "lambda/${var.environment}/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  issuer_invoke_arn        = data.terraform_remote_state.lambda.outputs.issuer_invoke_arn
  issuer_function_name     = data.terraform_remote_state.lambda.outputs.issuer_function_name
  authorizer_invoke_arn    = data.terraform_remote_state.lambda.outputs.authorizer_invoke_arn
  authorizer_function_name = data.terraform_remote_state.lambda.outputs.authorizer_function_name
}
