output "aurora_endpoint" {
  value = aws_rds_cluster.verification.endpoint
}

output "database_secret_arn" {
  value     = aws_rds_cluster.verification.master_user_secret[0].secret_arn
  sensitive = true
}

output "atlas_registry_token_secret_arn" {
  value = aws_secretsmanager_secret.atlas_registry_token.arn
}

output "codebuild_project_name" {
  value = aws_codebuild_project.atlas_deploy.name
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
