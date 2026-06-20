variable "aws_region" {
  description = "AWS Region for the verification environment."
  type        = string
}

variable "project_name" {
  description = "Prefix used for verification resources."
  type        = string
  default     = "dac-practice"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deployment role."
  type        = string
  default     = "mshi-04/DacPractice"
}

variable "vpc_cidr" {
  description = "CIDR block dedicated to the verification environment."
  type        = string
  default     = "10.40.0.0/16"
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL-compatible engine version."
  type        = string
  default     = "16.6"
}

variable "aurora_min_capacity" {
  description = "Minimum Aurora Serverless v2 ACUs."
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Maximum Aurora Serverless v2 ACUs."
  type        = number
  default     = 2
}

variable "aurora_log_retention_in_days" {
  description = "Retention period for exported Aurora PostgreSQL logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.aurora_log_retention_in_days)
    error_message = "aurora_log_retention_in_days must be a supported CloudWatch Logs retention value."
  }
}

variable "deletion_protection" {
  description = "Protect the verification cluster from accidental deletion."
  type        = bool
  default     = true
}

variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB tables."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = var.dynamodb_billing_mode == "PAY_PER_REQUEST"
    error_message = "This configuration supports PAY_PER_REQUEST only; provisioned capacity requires an explicit capacity design."
  }
}

variable "dynamodb_deletion_protection_enabled" {
  description = "Protect DynamoDB tables from accidental deletion."
  type        = bool
  default     = true
}

variable "dynamodb_table_class" {
  description = "Table class for DynamoDB tables."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.dynamodb_table_class)
    error_message = "dynamodb_table_class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

variable "dynamodb_ttl_attribute_name" {
  description = "Unix epoch TTL attribute used by expiring DynamoDB tables."
  type        = string
  default     = "expires_at_epoch"
}

variable "atlas_registry" {
  description = "Atlas Registry migration directory name."
  type        = string
  default     = "dacpractice"
}

variable "atlas_image_reference" {
  description = "Digest-pinned Atlas container image reference used by CodeBuild."
  type        = string
  default     = "arigaio/atlas@sha256:289a0c8eb35905d5f1ff63d06c799752762cc41a83a70ec89f412d3a0fe673d9"

  validation {
    condition     = can(regex("^[^@]+@sha256:[0-9a-f]{64}$", var.atlas_image_reference))
    error_message = "atlas_image_reference must be a digest-pinned container image reference."
  }
}
