variable "aws_region" {
  default = "us-east-1"
}

variable "cloudability_account_id" {
  description = "Cloudability AWS Account ID"
  type        = string
}

variable "external_id" {
  description = "External ID from Cloudability"
  type        = string
}

variable "bucket_name" {
  default = "cloudability-cur-bucket"
} 
