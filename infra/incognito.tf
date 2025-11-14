# -------------------------
# AWS Cognito User Pool
# -------------------------
resource "aws_cognito_user_pool" "shopping_list_pool" {
  name = "ShoppingListUserPool"

  # Require users to verify email during sign-up
  auto_verified_attributes = ["email"]

  # Define password strength requirements (e.g., minimum 8 characters)
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  # Configuration for sending verification emails
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Allow users to sign in using their email address as the username
  username_attributes = ["email"]

  tags = {
    Project = "cloud-shopping-list"
  }
}

# -------------------------
# AWS Cognito User Pool Domain (Required for Google/Federated Logins)
# Note: The domain prefix must be globally unique
# -------------------------
resource "aws_cognito_user_pool_domain" "shopping_list_domain" {
  domain       = "cloud-shopping-list-app-9233" # CHANGE THIS TO A UNIQUE PREFIX
  user_pool_id = aws_cognito_user_pool.shopping_list_pool.id
}


# -------------------------
# AWS Cognito User Pool Client
# -------------------------
resource "aws_cognito_user_pool_client" "shopping_list_client" {
  name         = "shopping-list-app-client"
  user_pool_id = aws_cognito_user_pool.shopping_list_pool.id

  # Allow the client to create and update users without a secret
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  # Prevent a secret from being required, typical for web/mobile apps
  generate_secret = false

  # Configure token expiration for short-lived access
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  access_token_validity  = 60 # 60 minutes
  id_token_validity      = 60 # 60 minutes
  refresh_token_validity = 30 # 30 days
}

# -------------------------
# Output Variables (Needed by API Gateway and Frontend)
# -------------------------
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.shopping_list_pool.id
}

output "cognito_app_client_id" {
  description = "The ID of the Cognito User Pool App Client."
  value       = aws_cognito_user_pool_client.shopping_list_client.id
}
