# 9. HTTP API: gives the Lambda a public HTTPS address
resource "aws_apigatewayv2_api" "dashboard" {
  name          = "site-watchdog-api"
  protocol_type = "HTTP"

  # CORS: only the dashboard's website may call this API from a browser
  cors_configuration {
    allow_origins = [var.dashboard_origin]
    allow_methods = ["GET"]
    allow_headers = ["authorization"]
    max_age       = 300
  }
}

# 10. JWT authorizer: the security guard. Checks every token BEFORE the Lambda runs
resource "aws_apigatewayv2_authorizer" "auth0" {
  api_id           = aws_apigatewayv2_api.dashboard.id
  name             = "auth0-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://${var.auth0_domain}/" # trailing slash: Auth0 tokens have it
    audience = [var.auth0_audience]
  }
}

# 11. Integration: "send requests to this Lambda"
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.dashboard.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.watchdog.invoke_arn
  payload_format_version = "2.0"
}

# 12. Route: GET /status, protected by the JWT authorizer
resource "aws_apigatewayv2_route" "status" {
  api_id             = aws_apigatewayv2_api.dashboard.id
  route_key          = "GET /status"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.auth0.id
}

# 13. Stage: makes the API live; throttling limits abuse (and cost)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.dashboard.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 5
    throttling_rate_limit  = 2
  }
}

# 14. Allow API Gateway (only this API) to call the Lambda
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.watchdog.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dashboard.execution_arn}/*/*"
}
