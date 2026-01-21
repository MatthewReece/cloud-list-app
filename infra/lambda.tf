resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-v2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
      Effect    = "Allow"
    }]
  })

  tags = {
    Project = "cloud-shopping-list"
    Env     = "dev"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo_access" {
  role = aws_iam_role.lambda_exec_role.name
  # NOTE: AmazonDynamoDBFullAccess is fine for development, but consider
  # scoping this down to specific table permissions for production.
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_function" "shopping_api" {
  function_name    = "shopping-list-api-v2"
  role             = aws_iam_role.lambda_exec_role.arn
  runtime          = "nodejs22.x"
  handler          = "handler.handler"
  filename         = "${path.module}/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")

  # Assumes aws_dynamodb_table.shopping_list is defined elsewhere
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.shopping_list.name
    }
  }

  tags = {
    Project = "cloud-shopping-list"
    Env     = "dev"
  }
}

# ----------------------------------------------------
# PERMISSIONS FIX APPLIED HERE
# ----------------------------------------------------
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shopping_api.function_name
  principal     = "apigateway.amazonaws.com"

  # This line links the API Gateway (shopping_api) execution ARN to the Lambda.
  source_arn = "${aws_api_gateway_rest_api.shopping_api.execution_arn}/*/*"
}
