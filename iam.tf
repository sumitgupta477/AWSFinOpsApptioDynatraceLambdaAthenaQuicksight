/*resource "aws_iam_role" "cloudability_role" {
  name = "CloudabilityRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::9235116172606:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })
}*/

resource "aws_iam_policy" "cloudability_policy" {
  name = "CloudabilityReadOnlyPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:*",
          "cur:*",
          "aws-portal:ViewBilling",
          "aws-portal:ViewUsage",
          "organizations:List*",
          "organizations:Describe*",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}

/*resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.cloudability_role.name
  policy_arn = aws_iam_policy.cloudability_policy.arn
} */

# ------------------------
# Bucket Policy for CUR
# ------------------------
data "aws_iam_policy_document" "cur_policy" {
  statement {
    sid = "AllowCURBucketAccessGetAcl"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl"
    ]

    resources = [
      aws_s3_bucket.cur_bucket.arn
    ]
  }

  statement {
    sid = "AllowCURBucketAccessPutObject"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.cur_bucket.arn}/AWSBillingReports/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "cur_policy" {
  bucket = aws_s3_bucket.cur_bucket.id
  policy = data.aws_iam_policy_document.cur_policy.json
}

resource "aws_iam_role" "datadog_role" {
  name = "DatadogAWSIntegrationRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::464622532012:root" # Datadog account
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "datadog_policy" {
  role = aws_iam_role.datadog_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:Get*",
        "cloudwatch:List*",
        "ec2:Describe*",
        "rds:Describe*",
        "s3:ListAllMyBuckets"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:DescribeInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      }
    ]
  })
}