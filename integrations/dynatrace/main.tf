# Registers this AWS account with Dynatrace using role-based authentication
# (no long-lived AWS access keys). Apply the root module first with
# enable_dynatrace = true, then run this module.

terraform {
  required_providers {
    dynatrace = {
      source  = "dynatrace-oss/dynatrace"
      version = "~> 1.0"
    }
  }
}

# Credentials come from the DYNATRACE_ENV_URL and DYNATRACE_API_TOKEN environment variables.
provider "dynatrace" {}

variable "aws_account_id" {
  description = "The AWS account to monitor"
  type        = string
}

variable "iam_role_name" {
  description = "Role created by the root module (output dynatrace_role_name)"
  type        = string
  default     = "DynatraceMonitoringRole"
}

resource "dynatrace_aws_credentials" "this" {
  label          = "aws-finops"
  partition_type = "AWS_DEFAULT"
  tagged_only    = false

  authentication_data {
    account_id = var.aws_account_id
    iam_role   = var.iam_role_name
  }
}

data "dynatrace_aws_supported_services" "supported" {}

resource "dynatrace_aws_service" "services" {
  for_each                = data.dynatrace_aws_supported_services.supported.services
  credentials_id          = dynatrace_aws_credentials.this.id
  name                    = each.key
  use_recommended_metrics = true
}
