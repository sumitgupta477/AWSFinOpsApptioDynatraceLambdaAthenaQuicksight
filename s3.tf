# ------------------------
# Bucket for Cost and Usage Reports (CUR) and Athena query results
# ------------------------
resource "aws_s3_bucket" "cur_bucket" {
  bucket = var.bucket_name

  tags = {
    Name = "FinOpsCURBucket"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.cur_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "cur_bucket" {
  bucket                  = aws_s3_bucket.cur_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3: CUR delivery supports it without extra KMS key-policy setup.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.cur_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.cur_bucket.id

  # Older reports move to Infrequent Access. They stay queryable by Athena
  # (unlike Glacier, which Athena cannot read).
  rule {
    id     = "cur-to-infrequent-access"
    status = "Enabled"
    filter {
      prefix = "cur/"
    }
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # Athena result files are disposable.
  rule {
    id     = "expire-athena-results"
    status = "Enabled"
    filter {
      prefix = "athena-results/"
    }
    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.versioning]
}

# ------------------------
# Bucket policy allowing AWS billing to deliver CUR files
# ------------------------
data "aws_iam_policy_document" "cur_policy" {
  statement {
    sid    = "AllowCURBucketAccessGetAclAndPolicy"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl", "s3:GetBucketPolicy"]
    resources = [aws_s3_bucket.cur_bucket.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowCURBucketAccessPutObject"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cur_bucket.arn}/cur/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "cur_policy" {
  bucket = aws_s3_bucket.cur_bucket.id
  policy = data.aws_iam_policy_document.cur_policy.json

  depends_on = [aws_s3_bucket_public_access_block.cur_bucket]
}
