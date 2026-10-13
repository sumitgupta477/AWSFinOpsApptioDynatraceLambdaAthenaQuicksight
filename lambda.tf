# ============================================================
# Daily idle-instance cleanup (EventBridge schedule -> Lambda)
# ============================================================
data "archive_file" "idle_cleanup" {
  type        = "zip"
  source_file = "${path.module}/lambda/idle_cleanup.py"
  output_path = "${path.module}/build/idle_cleanup.zip"
}

resource "aws_lambda_function" "cleanup" {
  function_name    = "finops-idle-cleanup"
  role             = aws_iam_role.lambda_role.arn
  handler          = "idle_cleanup.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  filename         = data.archive_file.idle_cleanup.output_path
  source_code_hash = data.archive_file.idle_cleanup.output_base64sha256

  environment {
    variables = {
      CPU_THRESHOLD = tostring(var.idle_cpu_threshold)
      LOOKBACK_DAYS = tostring(var.idle_lookback_days)
      AUTO_STOP_TAG = var.auto_stop_tag_key
      DRY_RUN       = tostring(var.idle_cleanup_dry_run)
    }
  }
}

resource "aws_cloudwatch_log_group" "cleanup" {
  name              = "/aws/lambda/${aws_lambda_function.cleanup.function_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "idle-cleanup-schedule"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "cleanup" {
  rule = aws_cloudwatch_event_rule.lambda_schedule.name
  arn  = aws_lambda_function.cleanup.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule.arn
}

# ============================================================
# Alert-driven remediation webhook (API Gateway -> Lambda)
# Called by Dynatrace / Datadog alert webhooks with a shared secret header.
# ============================================================
resource "random_password" "webhook_token" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "webhook_token" {
  name_prefix = "finops-webhook-token-"
}

resource "aws_secretsmanager_secret_version" "webhook_token" {
  secret_id     = aws_secretsmanager_secret.webhook_token.id
  secret_string = random_password.webhook_token.result
}

data "archive_file" "remediation" {
  type        = "zip"
  source_file = "${path.module}/lambda/remediation_webhook.py"
  output_path = "${path.module}/build/remediation_webhook.zip"
}

resource "aws_lambda_function" "remediation" {
  function_name    = "finops-auto-remediation"
  role             = aws_iam_role.lambda_role.arn
  handler          = "remediation_webhook.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.remediation.output_path
  source_code_hash = data.archive_file.remediation.output_base64sha256

  environment {
    variables = {
      WEBHOOK_SECRET_ARN = aws_secretsmanager_secret.webhook_token.arn
      AUTO_STOP_TAG      = var.auto_stop_tag_key
      LOW_CPU_THRESHOLD  = tostring(var.idle_cpu_threshold)
      HIGH_CPU_THRESHOLD = "80"
    }
  }
}

resource "aws_cloudwatch_log_group" "remediation" {
  name              = "/aws/lambda/${aws_lambda_function.remediation.function_name}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_api" "webhook" {
  name          = "finops-webhook-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.webhook.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.remediation.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "POST /remediate"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 5
    throttling_burst_limit = 10
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhook.execution_arn}/*/*"
}
