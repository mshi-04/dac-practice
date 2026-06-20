data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "aurora_kms" {
  statement {
    sid    = "EnableAccountAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRdsUse"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["rds.${var.aws_region}.amazonaws.com"]
    }
  }
}

locals {
  name_prefix = "${var.project_name}-verification"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "verification" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "verification" {
  vpc_id = aws_vpc.verification.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = toset(local.azs)

  vpc_id                  = aws_vpc.verification.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, index(local.azs, each.value))
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${each.value}"
  }
}

resource "aws_subnet" "private" {
  for_each = toset(local.azs)

  vpc_id            = aws_vpc.verification.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10 + index(local.azs, each.value))

  tags = {
    Name = "${local.name_prefix}-private-${each.value}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.verification.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.verification.id
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "verification" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id

  depends_on = [aws_internet_gateway.verification]

  tags = {
    Name = "${local.name_prefix}-nat"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.verification.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.verification.id
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "codebuild" {
  name        = "${local.name_prefix}-codebuild"
  description = "Outbound access for the Atlas deployment build."
  vpc_id      = aws_vpc.verification.id
}

resource "aws_security_group" "aurora" {
  name        = "${local.name_prefix}-aurora"
  description = "Accept PostgreSQL only from the deployment build."
  vpc_id      = aws_vpc.verification.id

  ingress {
    description     = "PostgreSQL from CodeBuild"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.codebuild.id]
  }
}

resource "aws_vpc_security_group_egress_rule" "codebuild_to_aurora" {
  description                  = "PostgreSQL to verification Aurora"
  security_group_id            = aws_security_group.codebuild.id
  referenced_security_group_id = aws_security_group.aurora.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "codebuild_https" {
  description       = "HTTPS to Atlas Registry, container registries, and AWS APIs"
  security_group_id = aws_security_group.codebuild.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "codebuild_dns_udp" {
  description       = "DNS over UDP"
  security_group_id = aws_security_group.codebuild.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "codebuild_dns_tcp" {
  description       = "DNS over TCP"
  security_group_id = aws_security_group.codebuild.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name_prefix}-aurora"
  subnet_ids = values(aws_subnet.private)[*].id
}

resource "aws_kms_key" "aurora" {
  description             = "Encryption key for verification Aurora storage."
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.aurora_kms.json
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${local.name_prefix}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

resource "aws_cloudwatch_log_group" "aurora_postgresql" {
  name              = "/aws/rds/cluster/${local.name_prefix}-aurora/postgresql"
  retention_in_days = var.aurora_log_retention_in_days
}

resource "aws_rds_cluster" "verification" {
  cluster_identifier              = "${local.name_prefix}-aurora"
  engine                          = "aurora-postgresql"
  engine_version                  = var.aurora_engine_version
  database_name                   = "dacpractice"
  master_username                 = "atlas_admin"
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.aurora.arn
  backup_retention_period         = 7
  preferred_backup_window         = "18:00-18:30"
  preferred_maintenance_window    = "sun:19:00-sun:19:30"
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${local.name_prefix}-final"
  enabled_cloudwatch_logs_exports = ["postgresql"]

  depends_on = [aws_cloudwatch_log_group.aurora_postgresql]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }
}

resource "aws_rds_cluster_instance" "verification" {
  identifier          = "${local.name_prefix}-instance-1"
  cluster_identifier  = aws_rds_cluster.verification.id
  engine              = aws_rds_cluster.verification.engine
  engine_version      = aws_rds_cluster.verification.engine_version
  instance_class      = "db.serverless"
  publicly_accessible = false
}

resource "aws_secretsmanager_secret" "atlas_registry_token" {
  name                    = "${local.name_prefix}/atlas-registry-read-token"
  recovery_window_in_days = 7
}

resource "aws_iam_role" "codebuild" {
  name = "${local.name_prefix}-codebuild"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${local.name_prefix}-codebuild"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.atlas_registry_token.arn, aws_rds_cluster.verification.master_user_secret[0].secret_arn]
      }
    ]
  })
}

resource "aws_codebuild_project" "atlas_deploy" {
  name          = "${local.name_prefix}-atlas-deploy"
  description   = "Applies an immutable Atlas Registry migration tag to verification Aurora."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ATLAS_REGISTRY"
      value = var.atlas_registry
    }

    environment_variable {
      name  = "ATLAS_IMAGE_REFERENCE"
      value = var.atlas_image_reference
    }

    environment_variable {
      name  = "ATLAS_TOKEN_SECRET_ID"
      value = aws_secretsmanager_secret.atlas_registry_token.arn
    }

    environment_variable {
      name  = "DATABASE_SECRET_ID"
      value = aws_rds_cluster.verification.master_user_secret[0].secret_arn
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/buildspec.yml")
  }

  vpc_config {
    vpc_id             = aws_vpc.verification.id
    subnets            = values(aws_subnet.private)[*].id
    security_group_ids = [aws_security_group.codebuild.id]
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_deploy" {
  name = "${local.name_prefix}-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:aurora-verification"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_deploy" {
  name = "${local.name_prefix}-github-deploy"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
      Resource = aws_codebuild_project.atlas_deploy.arn
    }]
  })
}

resource "aws_iam_role" "github_terraform_plan" {
  name = "${local.name_prefix}-github-terraform-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:terraform-plan"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_terraform_plan" {
  name = "${local.name_prefix}-github-terraform-plan"
  role = aws_iam_role.github_terraform_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAccountMetadata"
        Effect = "Allow"
        Action = [
          "dynamodb:ListTables",
          "ec2:Describe*",
          "iam:Get*",
          "iam:List*",
          "kms:List*",
          "rds:Describe*",
          "rds:ListTagsForResource",
          "secretsmanager:ListSecrets",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadDynamoDBTables"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:ListTagsOfResource",
        ]
        Resource = [
          aws_dynamodb_table.shopping_cart.arn,
          aws_dynamodb_table.customer_activity.arn,
          aws_dynamodb_table.order_lookup.arn,
        ]
      },
      {
        Sid    = "ReadCodeBuildProject"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetProjects",
          "codebuild:ListTagsForResource",
        ]
        Resource = aws_codebuild_project.atlas_deploy.arn
      },
      {
        Sid    = "ReadAuroraEncryptionKey"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
        ]
        Resource = aws_kms_key.aurora.arn
      },
      {
        Sid    = "ReadRegistryTokenSecretMetadata"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListTagsForResource",
        ]
        Resource = aws_secretsmanager_secret.atlas_registry_token.arn
      },
    ]
  })
}
