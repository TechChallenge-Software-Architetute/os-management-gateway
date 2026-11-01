# The auth Lambdas are addressed by deterministic name, NOT by reading the
# os-management-lambda Terraform state.
#
# This used to be a `data "terraform_remote_state" "lambda"`, which made the
# gateway deploy fail until os-management-lambda had run and written its state —
# the one real cross-repo deploy dependency in the org. The pipeline even had a
# step that exited 1 when that state file was missing.
#
# Both values the gateway needs are fully derivable:
#
#   function name -> <name_prefix>-<issuer|authorizer>-<environment>
#                    (exactly how os-management-lambda names them)
#   invoke ARN    -> the fixed API Gateway integration URI format
#
# So the gateway now plans and applies in any order. If the function does not
# exist yet, API Gateway returns a 5xx on that route at runtime until it does;
# the deploy itself no longer blocks. Explicit overrides are available for the
# case where the functions are named differently.

data "aws_caller_identity" "current" {}

locals {
  issuer_function_name_derived     = "${var.lambda_name_prefix}-issuer-${var.environment}"
  authorizer_function_name_derived = "${var.lambda_name_prefix}-authorizer-${var.environment}"

  issuer_function_name = var.issuer_function_name != "" ? var.issuer_function_name : local.issuer_function_name_derived
  authorizer_function_name = (var.authorizer_function_name != ""
    ? var.authorizer_function_name
  : local.authorizer_function_name_derived)

  # Same string aws_lambda_function.invoke_arn produces.
  issuer_invoke_arn = (var.issuer_invoke_arn != ""
    ? var.issuer_invoke_arn
  : local.derived_issuer_invoke_arn)

  authorizer_invoke_arn = (var.authorizer_invoke_arn != ""
    ? var.authorizer_invoke_arn
  : local.derived_authorizer_invoke_arn)

  lambda_arn_prefix = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function"
  invoke_uri_prefix = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions"

  derived_issuer_invoke_arn     = "${local.invoke_uri_prefix}/${local.lambda_arn_prefix}:${local.issuer_function_name}/invocations"
  derived_authorizer_invoke_arn = "${local.invoke_uri_prefix}/${local.lambda_arn_prefix}:${local.authorizer_function_name}/invocations"
}
