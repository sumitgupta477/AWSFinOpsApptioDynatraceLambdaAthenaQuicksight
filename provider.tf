terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # For team use, store state remotely, for example:
  # backend "s3" {
  #   bucket = "my-terraform-state"
  #   key    = "finops/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Cost and Usage Report definitions can only be managed in us-east-1.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "finops"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
