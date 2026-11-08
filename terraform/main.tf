data "aws_caller_identity" "me" {}

# 1. Zip the Python file (Terraform does it; no manual zip)
data "archive_file" "code" {
  type        = "zip"
  source_file = "${path.module}/../watchdog.py"
  output_path = "${path.module}/build/watchdog.zip"
}

# 2. Log group for the function (7 days, then auto-delete)
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/site-watchdog"
  retention_in_days = 7
}

# 3. IAM role: the identity the function runs as
resource "aws_iam_role" "lambda" {
  name = "site-watchdog-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# 4. Permissions: ONLY write its own logs + read ONE parameter (least privilege)
resource "aws_iam_role_policy" "lambda" {
  name = "site-watchdog-permissions"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Sid      = "ReadBotToken"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.me.account_id}:parameter${var.token_param_name}"
      }
    ]
  })
}

# 5. The Lambda function
resource "aws_lambda_function" "watchdog" {
  function_name    = "site-watchdog"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "watchdog.lambda_handler"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      SITES                = join(",", var.sites)
      TELEGRAM_CHAT_ID     = var.telegram_chat_id
      TELEGRAM_TOKEN_PARAM = var.token_param_name
      SLOW_MS              = "3000"
      CERT_WARN_DAYS       = "14"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]
}

# 6. Schedule: an alarm clock that fires every 15 minutes
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "site-watchdog-schedule"
  schedule_expression = var.schedule
}

# 7. Connect the alarm clock to the function
resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = aws_lambda_function.watchdog.arn
}

# 8. Allow EventBridge (only this rule) to call the function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.watchdog.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
