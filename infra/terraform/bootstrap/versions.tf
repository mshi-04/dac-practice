# The bootstrap stack creates the S3 bucket that stores the main stack's remote
# state. It intentionally uses local state (no backend block) to avoid the
# chicken-and-egg problem of storing state in a bucket that does not exist yet.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = var.project_name
      Environment = "bootstrap"
    }
  }
}
