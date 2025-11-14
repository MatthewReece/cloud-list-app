# -------------------------
# Cognito Authorizer
# -------------------------
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "CognitoAuthorizer"
  rest_api_id     = aws_api_gateway_rest_api.shopping_api.id
  type            = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization" # Looks for JWT in Authorization header
  provider_arns   = [aws_cognito_user_pool.shopping_list_pool.arn]

  # CRITICAL: Ensures the Authorizer is deployed after the User Pool is created
  depends_on = [
    aws_cognito_user_pool.shopping_list_pool
  ]
}

# -------------------------
# IAM Role for API Gateway CloudWatch Logs
# -------------------------
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "apigateway.amazonaws.com" }
      Effect    = "Allow"
    }]
  })
  tags = {
    Project = "cloud-shopping-list"
  }
}

# -------------------------
# Policy Attachment for Logging Role
# -------------------------
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# -------------------------
# Global API Gateway Account Settings (Links Role to Account)
# -------------------------
resource "aws_api_gateway_account" "api_account_settings" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.api_gateway_cloudwatch_attachment
  ]
}

# -------------------------
# API Gateway REST API Definition
# -------------------------
resource "aws_api_gateway_rest_api" "shopping_api" {
  name        = "shopping-list-api"
  description = "API Gateway for Cloud Shopping List Lambda"
  tags = {
    Project = "cloud-shopping-list"
    Env     = "dev"
  }
}

# -------------------------
# Resource: /items
# -------------------------
resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.shopping_api.id
  parent_id   = aws_api_gateway_rest_api.shopping_api.root_resource_id
  path_part   = "items"
}

# -------------------------
# Method: ANY HTTP on /items
# -------------------------
resource "aws_api_gateway_method" "items_method" {
  rest_api_id   = aws_api_gateway_rest_api.shopping_api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "ANY"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

# -------------------------
# Integration: Lambda (AWS_PROXY)
# -------------------------
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.shopping_api.id
  resource_id             = aws_api_gateway_resource.items.id
  http_method             = aws_api_gateway_method.items_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"

  # Assumes aws_lambda_function.shopping_api is defined in lambda.tf
  uri = aws_lambda_function.shopping_api.invoke_arn
}

# Lambda Permission for API Gateway (Ensures API Gateway can invoke the Lambda)
# -------------------------
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shopping_api.function_name
  principal     = "apigateway.amazonaws.com"

  # Restrict access to only the deployed API execution ARN
  # This makes the permission specific to your API.
  source_arn = "${aws_api_gateway_rest_api.shopping_api.execution_arn}/*/*"
}


# --- Deployment & Stage Management  ---

# -------------------------
# Deployment 
# -------------------------
resource "aws_api_gateway_deployment" "shopping_api_deploy" {
  rest_api_id = aws_api_gateway_rest_api.shopping_api.id

  # Forces a new deployment whenever API configuration changes.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.items.id,
      aws_api_gateway_method.items_method.id,
      aws_api_gateway_method.options_method.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_authorizer.cognito_authorizer.id,
      aws_api_gateway_integration_response.options_integration_response.id,
      # CRITICAL ADDITION: Your new 4XX CORS fix resource
      aws_api_gateway_gateway_response.cors_4xx_response.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -------------------------
# Stage: dev
# -------------------------
resource "aws_api_gateway_stage" "dev_stage" {
  deployment_id = aws_api_gateway_deployment.shopping_api_deploy.id
  rest_api_id   = aws_api_gateway_rest_api.shopping_api.id
  stage_name    = "dev"
  description   = "Development Stage"

  tags = {
    Project = "cloud-shopping-list"
    Env     = "dev"
  }
}

# --- CloudWatch Logging Configuration (Stage Specific) ---

# -------------------------
# CloudWatch Log Group for API Gateway Execution
# -------------------------
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.shopping_api.id}"
  retention_in_days = 7

  tags = {
    Project = "cloud-shopping-list"
    Env     = "dev"
  }
}

# -------------------------
# Stage Settings to Enable Logging (DEPENDS_ON UPDATED)
# -------------------------
resource "aws_api_gateway_method_settings" "dev_stage_settings" {
  rest_api_id = aws_api_gateway_rest_api.shopping_api.id
  stage_name  = aws_api_gateway_stage.dev_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "ERROR"
    data_trace_enabled = true
  }

  # Ensure the global account settings are applied first.
  depends_on = [
    aws_api_gateway_stage.dev_stage,
    aws_cloudwatch_log_group.api_gateway_log_group,
    aws_api_gateway_account.api_account_settings
  ]
}

# =========================================================================
#  CORS CONFIGURATION FOR /items RESOURCE 
# Required for React/S3 frontend to communicate with API Gateway
# =========================================================================

# -------------------------
# Method: OPTIONS HTTP on /items (Preflight Check)
# -------------------------
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.shopping_api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# -------------------------
# Integration: MOCK for OPTIONS (Handles CORS Headers)
# -------------------------
resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.shopping_api.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

# -------------------------
# Method Response: 200 OK for OPTIONS
# -------------------------
resource "aws_api_gateway_method_response" "options_200_method_response" {
  rest_api_id = aws_api_gateway_rest_api.shopping_api.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# -------------------------
# Integration Response: Set CORS Headers
# -------------------------
resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.shopping_api.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_200_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'" # ✅ ADDED PUT AND DELETE
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [aws_api_gateway_method_response.options_200_method_response]
}

# =========================================================================
#  CORS FIX FOR ERROR RESPONSES (4XX)
# This resource forces API Gateway to include CORS headers on error responses (like 401).
# =========================================================================
resource "aws_api_gateway_gateway_response" "cors_4xx_response" {
  # Referencing your main API resource
  rest_api_id   = aws_api_gateway_rest_api.shopping_api.id
  response_type = "DEFAULT_4XX"

  # Map the CORS headers to the 4XX response
  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'*,GET,POST,PUT,DELETE,OPTIONS'"
  }
}
