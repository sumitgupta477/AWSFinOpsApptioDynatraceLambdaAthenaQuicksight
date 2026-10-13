# ============================================================
# Lambda role for idle cleanup and alert remediation
# ============================================================
resource "aws_iam_role" "lambda_role" {
  name = "lambda-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "finops-remediation"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "cloudwatch:GetMetricStatistics", "cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        # Automation can only stop instances that have explicitly opted in via tag.
        Effect   = "Allow"
        Action   = "ec2:StopInstances"
        Resource = "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEqualsIgnoreCase = { "ec2:ResourceTag/${var.auto_stop_tag_key}" = "true" }
        }
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.webhook_token.arn
      }
    ]
  })
}

# ============================================================
# Glue crawler role (reads CUR files, updates the Glue catalog)
# ============================================================
resource "aws_iam_role" "glue_role" {
  name = "finops-glue-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  name = "read-cur"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.cur_bucket.arn}/cur/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.cur_bucket.arn
      }
    ]
  })
}

# ============================================================
# Apptio Cloudability: read-only cross-account access (optional)
# ============================================================
resource "aws_iam_role" "cloudability_role" {
  count = var.enable_cloudability ? 1 : 0
  name  = "CloudabilityRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.cloudability_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = var.cloudability_external_id } }
    }]
  })
}

resource "aws_iam_role_policy" "cloudability_policy" {
  count = var.enable_cloudability ? 1 : 0
  name  = "CloudabilityReadOnlyPolicy"
  role  = aws_iam_role.cloudability_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:Get*",
          "ce:Describe*",
          "ce:List*",
          "cur:DescribeReportDefinitions",
          "organizations:List*",
          "organizations:Describe*",
          "ec2:Describe*",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.cur_bucket.arn, "${aws_s3_bucket.cur_bucket.arn}/cur/*"]
      }
    ]
  })
}

# ============================================================
# Datadog AWS integration role (optional)
# ============================================================
resource "aws_iam_role" "datadog_role" {
  count = var.enable_datadog ? 1 : 0
  name  = "DatadogAWSIntegrationRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::464622532012:root" } # Datadog's AWS account
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = var.datadog_external_id } }
    }]
  })
}

resource "aws_iam_role_policy" "datadog_policy" {
  count = var.enable_datadog ? 1 : 0
  name  = "DatadogReadOnly"
  role  = aws_iam_role.datadog_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:Get*",
        "cloudwatch:List*",
        "ec2:Describe*",
        "rds:Describe*",
        "s3:ListAllMyBuckets",
        "tag:GetResources"
      ]
      Resource = "*"
    }]
  })
}

# ============================================================
# Dynatrace role-based AWS monitoring (optional; no access keys needed)
# ============================================================
resource "aws_iam_role" "dynatrace_role" {
  count = var.enable_dynatrace ? 1 : 0
  name  = "DynatraceMonitoringRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.dynatrace_aws_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = var.dynatrace_external_id } }
    }]
  })
}

resource "aws_iam_role_policy" "dynatrace_policy" {
  count = var.enable_dynatrace ? 1 : 0
  name  = "DynatraceReadOnly"
  role  = aws_iam_role.dynatrace_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "ec2:DescribeInstances",
        "ec2:DescribeAvailabilityZones",
        "tag:GetResources",
        "sts:GetCallerIdentity"
      ]
      Resource = "*"
    }]
  })
}
