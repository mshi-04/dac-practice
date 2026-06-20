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

variable "deletion_protection" {
  description = "Protect the verification cluster from accidental deletion."
  type        = bool
  default     = true
}

variable "atlas_registry" {
  description = "Atlas Registry migration directory name."
  type        = string
  default     = "dacpractice"
}

variable "atlas_image_tag" {
  description = "Immutable Atlas container image tag used by CodeBuild."
  type        = string
  default     = "v1.2.3"
}
