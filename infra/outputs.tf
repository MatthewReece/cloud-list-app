output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.shopping_list.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.shopping_list.arn
}

output "aws_region" {
  description = "AWS region used for deployment"
  value       = var.aws_region
}

output "cloudfront_url" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "api_gateway_base_url" {
  description = "The base URL for invoking the shopping list API (excluding stage and resource path)"
  # Constructed using the REST API ID and the region from variables.tf
  value = "https://${aws_api_gateway_rest_api.shopping_api.id}.execute-api.${var.aws_region}.amazonaws.com"
}

output "api_gateway_invoke_url" {
  description = "The complete URL for the /items resource, ready for frontend use."
  # Combines the base URL, stage name, and resource path
  value = "https://${aws_api_gateway_rest_api.shopping_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.dev_stage.stage_name}/items"
}
