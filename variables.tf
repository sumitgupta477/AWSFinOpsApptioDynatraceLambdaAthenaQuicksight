variable "aws_region" {
  description = "Region for all resources. CUR report definitions require us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket for Cost and Usage Reports and Athena results"
  type        = string
}

variable "cur_report_name" {
  type    = string
  default = "cloudability-report"
}

variable "alert_email" {
  description = "Email address for budget and cost-anomaly alerts"
  type        = string
}

variable "monthly_budget_usd" {
  type    = number
  default = 5000
}

variable "anomaly_threshold_usd" {
  description = "Alert when a cost anomaly's total impact is at least this many dollars"
  type        = number
  default     = 100
}

# ---------------- Idle-instance automation ----------------
variable "idle_cpu_threshold" {
  description = "Average CPU % below which an opted-in instance counts as idle"
  type        = number
  default     = 5
}

variable "idle_lookback_days" {
  type    = number
  default = 7
}

variable "auto_stop_tag_key" {
  description = "Only instances tagged <key>=true are ever stopped by automation"
  type        = string
  default     = "AutoStop"
}

variable "idle_cleanup_dry_run" {
  description = "When true, the daily job only reports idle instances instead of stopping them"
  type        = bool
  default     = true
}

# ---------------- Third-party integrations (all optional) ----------------
variable "enable_cloudability" {
  description = "Create the cross-account IAM role Apptio Cloudability uses to read billing data"
  type        = bool
  default     = false
}

variable "cloudability_account_id" {
  description = "AWS account ID provided by Cloudability"
  type        = string
  default     = ""
}

variable "cloudability_external_id" {
  description = "External ID provided by Cloudability"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_datadog" {
  type    = bool
  default = false
}

variable "datadog_external_id" {
  description = "External ID from the Datadog AWS integration tile"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_dynatrace" {
  description = "Create the IAM role Dynatrace assumes for role-based AWS monitoring (see integrations/dynatrace)"
  type        = bool
  default     = false
}

variable "dynatrace_aws_account_id" {
  description = "Dynatrace's AWS account ID, shown in the Dynatrace AWS connection settings"
  type        = string
  default     = ""
}

variable "dynatrace_external_id" {
  description = "External ID shown in the Dynatrace AWS connection settings"
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------- QuickSight ----------------
variable "enable_quicksight" {
  description = "Create the QuickSight data source and dataset. Enable after the Glue crawler has created the CUR table."
  type        = bool
  default     = false
}

variable "quicksight_user" {
  description = "QuickSight user name (in the default namespace) who owns the data source and dataset"
  type        = string
  default     = ""
}
