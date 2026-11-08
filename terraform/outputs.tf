output "function_name" {
  value = aws_lambda_function.watchdog.function_name
}

output "log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}
