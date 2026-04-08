resource "aws_athena_workgroup" "this" {
  name = "cloudability-workgroup"

  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${var.bucket_name}/athena-results/"
    }
  }
}

resource "aws_glue_crawler" "cur_crawler" {
  name = "cur-crawler"

  role = aws_iam_role.glue_role.arn

  database_name = "finops_db"

  s3_target {
    path = "s3://${var.bucket_name}/cur/"
  }
}

resource "aws_athena_database" "cur_db" {
  name   = "cloudability_cur_db"
  bucket = aws_s3_bucket.cur_bucket.bucket
}

resource "aws_athena_named_query" "cur_table" {
  name      = "create_cur_table"
  database  = aws_athena_database.cur_db.name
  query     = <<SQL
CREATE EXTERNAL TABLE IF NOT EXISTS cloudability_cur (
  invoice_id string,
  billing_period_start_date string,
  billing_period_end_date string,
  linked_account_id string,
  service string,
  usage_type string,
  usage_amount double,
  cost double
)
PARTITIONED BY (year string, month string, day string)
STORED AS PARQUET
LOCATION 's3://${aws_s3_bucket.cur_bucket.bucket}/AWSBillingReports/'
SQL
}

resource "aws_budgets_budget" "monthly_budget" {
  name              = "monthly-cost-budget"
  budget_type       = "COST"
  limit_amount      = "5000"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator = "GREATER_THAN"
    threshold           = 80

    subscriber_email_addresses = ["finops@company.com"]
  }
}

resource "aws_ce_anomaly_monitor" "this" {
  name              = "finops-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_lambda_function" "cleanup" {
  function_name = "finops-idle-cleanup"
  handler       = "index.handler"
  runtime       = "python3.10"
}

resource "aws_athena_named_query" "qs_total_cost_by_service" {
  name     = "total_cost_by_service"
  database = aws_athena_database.cur_db.name
  query    = <<SQL
SELECT service,
       SUM(cost) AS total_cost
FROM cloudability_cur
WHERE year = '2026' AND month = '04'
GROUP BY service
ORDER BY total_cost DESC;
SQL
}

resource "aws_athena_named_query" "qs_cost_by_account" {
  name     = "cost_by_account"
  database = aws_athena_database.cur_db.name
  query    = <<SQL
SELECT linked_account_id,
       SUM(cost) AS total_cost
FROM cloudability_cur
WHERE year = '2026' AND month = '04'
GROUP BY linked_account_id
ORDER BY total_cost DESC;
SQL
}

resource "aws_athena_named_query" "qs_daily_cost_trend" {
  name     = "daily_cost_trend"
  database = aws_athena_database.cur_db.name
  query    = <<SQL
SELECT year, month, day,
       SUM(cost) AS total_cost
FROM cloudability_cur
GROUP BY year, month, day
ORDER BY year, month, day;
SQL
}

resource "aws_quicksight_data_source" "athena_source" {
  data_source_id = "cloudability-athena"
  name           = "Cloudability Athena"
  aws_account_id = var.aws_account_id
  type           = "ATHENA"

  athena_parameters {
    work_group = "primary"
  }

  permissions {
    principal = "arn:aws:quicksight:${var.region}:${var.aws_account_id}:user/default/${var.quicksight_user}"
    actions   = [
      "quicksight:DescribeDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource"
    ]
  }
}

resource "aws_quicksight_data_set" "cur_dataset" {
  data_set_id   = "cloudability-cur-dataset"
  name          = "Cloudability CUR Dataset"
  aws_account_id = var.aws_account_id
  import_mode   = "DIRECT_QUERY"

  physical_table {
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena_source.arn
      catalog         = aws_athena_database.cur_db.name
      schema          = aws_athena_database.cur_db.name
      name            = "cloudability_cur"
    }
  }

  permissions {
    principal = "arn:aws:quicksight:${var.region}:${var.aws_account_id}:user/default/${var.quicksight_user}"
    actions   = [
      "quicksight:DescribeDataSet",
      "quicksight:UpdateDataSet",
      "quicksight:DeleteDataSet"
    ]
  }
}

resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "idle-cleanup-schedule"
  schedule_expression = "rate(1 day)"
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
}

resource "aws_lambda_function" "remediation" {
  function_name = "finops-auto-remediation"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.10"

  filename = "lambda.zip"
}

resource "dynatrace_aws_credentials" "this" {
  label = "aws-finops"

  authentication_data {
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
  }
}

resource "dynatrace_aws_service" "ec2" {
  name = "EC2 Monitoring"
}

resource "aws_apigatewayv2_api" "webhook" {
  name          = "finops-webhook-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.webhook.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.remediation.invoke_arn
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "POST /remediate"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation.function_name
  principal     = "apigateway.amazonaws.com"
}