output "s3_bucket" {
  value = aws_s3_bucket.cur_bucket.bucket
}

output "glue_database" {
  value = aws_glue_catalog_database.cur_db.name
}

output "cur_table" {
  description = "Athena table created by the Glue crawler after the first CUR delivery"
  value       = local.cur_table
}

output "athena_workgroup" {
  value = aws_athena_workgroup.this.name
}

output "remediation_webhook_url" {
  value = "${aws_apigatewayv2_api.webhook.api_endpoint}/remediate"
}

output "webhook_token_secret_arn" {
  description = "Secrets Manager secret holding the x-webhook-token value for alert webhooks"
  value       = aws_secretsmanager_secret.webhook_token.arn
}

output "cloudability_role_arn" {
  value = var.enable_cloudability ? aws_iam_role.cloudability_role[0].arn : null
}

output "datadog_role_arn" {
  value = var.enable_datadog ? aws_iam_role.datadog_role[0].arn : null
}

output "dynatrace_role_name" {
  value = var.enable_dynatrace ? aws_iam_role.dynatrace_role[0].name : null
}
