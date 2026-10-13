# ------------------------
# Cost and Usage Report (hourly, Parquet, Athena-ready)
# ------------------------
resource "aws_cur_report_definition" "cloudability_cur" {
  report_name                = var.cur_report_name
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.cur_bucket.bucket
  s3_prefix                  = "cur"
  s3_region                  = var.aws_region
  additional_artifacts       = ["ATHENA"]
  report_versioning          = "OVERWRITE_REPORT"
  refresh_closed_reports     = true

  depends_on = [aws_s3_bucket_policy.cur_policy]
}

locals {
  # CUR delivers Parquet files to <prefix>/<report>/<report>/year=YYYY/month=M/
  cur_data_path = "s3://${aws_s3_bucket.cur_bucket.bucket}/cur/${var.cur_report_name}/${var.cur_report_name}/"
  # The Glue crawler names the table after the last folder of the path.
  cur_table = replace(var.cur_report_name, "-", "_")
}

# ------------------------
# Glue catalog + crawler: keeps the CUR table and its partitions up to date
# ------------------------
resource "aws_glue_catalog_database" "cur_db" {
  name = "finops_cur_db"
}

resource "aws_glue_crawler" "cur_crawler" {
  name          = "finops-cur-crawler"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.cur_db.name
  schedule      = "cron(0 6 * * ? *)" # daily, after CUR's overnight refresh

  s3_target {
    path = local.cur_data_path
    exclusions = [
      "**.json", "**.yml", "**.sql", "**.csv", "**.gz", "**.zip",
      "**/cost_and_usage_data_status/*",
    ]
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }
}

# ------------------------
# Athena workgroup and saved queries (also used by QuickSight)
# ------------------------
resource "aws_athena_workgroup" "this" {
  name          = "finops-workgroup"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 10737418240 # 10 GB guardrail on query cost

    result_configuration {
      output_location = "s3://${aws_s3_bucket.cur_bucket.bucket}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

resource "aws_athena_named_query" "qs_total_cost_by_service" {
  name      = "total_cost_by_service_this_month"
  workgroup = aws_athena_workgroup.this.name
  database  = aws_glue_catalog_database.cur_db.name
  query     = <<SQL
SELECT line_item_product_code AS service,
       ROUND(SUM(line_item_unblended_cost), 2) AS total_cost
FROM ${local.cur_table}
WHERE year = CAST(year(current_date) AS varchar)
  AND month = CAST(month(current_date) AS varchar)
GROUP BY line_item_product_code
ORDER BY total_cost DESC;
SQL
}

resource "aws_athena_named_query" "qs_cost_by_account" {
  name      = "cost_by_account_this_month"
  workgroup = aws_athena_workgroup.this.name
  database  = aws_glue_catalog_database.cur_db.name
  query     = <<SQL
SELECT line_item_usage_account_id AS account_id,
       ROUND(SUM(line_item_unblended_cost), 2) AS total_cost
FROM ${local.cur_table}
WHERE year = CAST(year(current_date) AS varchar)
  AND month = CAST(month(current_date) AS varchar)
GROUP BY line_item_usage_account_id
ORDER BY total_cost DESC;
SQL
}

resource "aws_athena_named_query" "qs_daily_cost_trend" {
  name      = "daily_cost_trend_last_90_days"
  workgroup = aws_athena_workgroup.this.name
  database  = aws_glue_catalog_database.cur_db.name
  query     = <<SQL
SELECT date_trunc('day', line_item_usage_start_date) AS usage_day,
       ROUND(SUM(line_item_unblended_cost), 2) AS total_cost
FROM ${local.cur_table}
WHERE line_item_usage_start_date >= current_date - INTERVAL '90' DAY
GROUP BY 1
ORDER BY 1;
SQL
}

resource "aws_athena_named_query" "qs_top_resources" {
  name      = "top_20_resources_this_month"
  workgroup = aws_athena_workgroup.this.name
  database  = aws_glue_catalog_database.cur_db.name
  query     = <<SQL
SELECT line_item_resource_id,
       line_item_product_code AS service,
       ROUND(SUM(line_item_unblended_cost), 2) AS total_cost
FROM ${local.cur_table}
WHERE year = CAST(year(current_date) AS varchar)
  AND month = CAST(month(current_date) AS varchar)
  AND line_item_resource_id <> ''
GROUP BY 1, 2
ORDER BY total_cost DESC
LIMIT 20;
SQL
}
