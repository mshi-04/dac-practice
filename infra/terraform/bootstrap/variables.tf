variable "aws_region" {
  description = "AWS Region that holds the Terraform state bucket."
  type        = string
}

variable "project_name" {
  description = "Prefix used for bootstrap resources and tags."
  type        = string
  default     = "dac-practice"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for the verification Terraform state."
  type        = string
}
