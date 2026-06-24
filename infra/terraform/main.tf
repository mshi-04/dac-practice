data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "postgres_kms" {
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

data "aws_iam_policy_document" "dynamodb_kms" {
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
    sid    = "AllowDynamoDBUse"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dynamodb.amazonaws.com"]
    }

    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${var.aws_region}.amazonaws.com"]
    }

  }

  statement {
    sid    = "AllowDynamoDBCreateGrant"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dynamodb.amazonaws.com"]
    }

    actions   = ["kms:CreateGrant"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
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

resource "aws_security_group" "postgres" {
  name        = "${local.name_prefix}-postgres"
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

resource "aws_vpc_security_group_egress_rule" "codebuild_to_postgres" {
  description                  = "PostgreSQL to verification RDS"
  security_group_id            = aws_security_group.codebuild.id
  referenced_security_group_id = aws_security_group.postgres.id
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

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.name_prefix}-postgres"
  subnet_ids = values(aws_subnet.private)[*].id
}

resource "aws_db_parameter_group" "postgres" {
  name        = "${local.name_prefix}-postgres16"
  family      = "postgres16"
  description = "Parameter group for the verification RDS PostgreSQL instance."
}

resource "aws_kms_key" "postgres" {
  description             = "Encryption key for verification RDS PostgreSQL storage."
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.postgres_kms.json
}

resource "aws_kms_alias" "postgres" {
  name          = "alias/${local.name_prefix}-postgres"
  target_key_id = aws_kms_key.postgres.key_id
}

resource "aws_kms_key" "dynamodb" {
  description             = "Encryption key for verification DynamoDB tables."
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.dynamodb_kms.json
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${local.name_prefix}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/aws/rds/instance/${local.name_prefix}-postgres/postgresql"
  retention_in_days = var.postgres_log_retention_in_days
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name_prefix}-atlas-deploy"
  retention_in_days = var.codebuild_log_retention_in_days
}

resource "aws_db_instance" "postgres" {
  identifier                      = "${local.name_prefix}-postgres"
  engine                          = "postgres"
  engine_version                  = var.postgres_engine_version
  instance_class                  = var.db_instance_class
  allocated_storage               = var.db_allocated_storage
  storage_type                    = var.db_storage_type
  multi_az                        = var.db_multi_az
  db_name                         = "dacpractice"
  username                        = "atlas_admin"
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.postgres.name
  parameter_group_name            = aws_db_parameter_group.postgres.name
  vpc_security_group_ids          = [aws_security_group.postgres.id]
  publicly_accessible             = false
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.postgres.arn
  backup_retention_period         = 7
  backup_window                   = "18:00-18:30"
  maintenance_window              = "sun:19:00-sun:19:30"
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${local.name_prefix}-final"
  enabled_cloudwatch_logs_exports = ["postgresql"]

  depends_on = [aws_cloudwatch_log_group.postgres]
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
        Sid      = "WriteBuildLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.codebuild.arn}:*"
      },
      {
        Sid      = "CreateBuildNetworkInterface"
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Vpc"           = aws_vpc.verification.arn
            "ec2:Subnet"        = values(aws_subnet.private)[*].arn
            "ec2:SecurityGroup" = aws_security_group.codebuild.arn
          }
        }
      },
      {
        Sid      = "DeleteBuildNetworkInterface"
        Effect   = "Allow"
        Action   = ["ec2:DeleteNetworkInterface"]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
        Condition = {
          StringEquals = {
            "ec2:Vpc" = aws_vpc.verification.arn
          }
        }
      },
      {
        Sid      = "DescribeBuildNetwork"
        Effect   = "Allow"
        Action   = ["ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.atlas_registry_token.arn, aws_db_instance.postgres.master_user_secret[0].secret_arn]
      }
    ]
  })
}

resource "aws_codebuild_project" "atlas_deploy" {
  name          = "${local.name_prefix}-atlas-deploy"
  description   = "Applies an immutable Atlas Registry migration tag to verification RDS PostgreSQL."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
    # Docker is required to run the digest-pinned Atlas image in this build.
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
      value = aws_db_instance.postgres.master_user_secret[0].secret_arn
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/buildspec.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "atlas-deploy"
      status      = "ENABLED"
    }
  }

  vpc_config {
    vpc_id             = aws_vpc.verification.id
    subnets            = values(aws_subnet.private)[*].id
    security_group_ids = [aws_security_group.codebuild.id]
  }
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_deploy" {
  name = "${local.name_prefix}-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:rds-verification"
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
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
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
        Sid    = "ReadPostgresEncryptionKey"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
        ]
        Resource = aws_kms_key.postgres.arn
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
