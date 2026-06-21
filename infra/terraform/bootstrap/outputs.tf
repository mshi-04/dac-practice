output "state_bucket_name" {
  description = "Name of the S3 bucket that stores the main stack's remote state."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket."
  value       = aws_s3_bucket.terraform_state.arn
}

output "state_lock_table_name" {
  description = "Name of the DynamoDB table that locks the main stack's remote state."
  value       = aws_dynamodb_table.terraform_state_lock.name
}
