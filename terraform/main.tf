terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.81, < 7.0"
    }
  }

  # For real use, store state remotely with encryption and locking, for example:
  # backend "s3" {
  #   bucket       = "my-tfstate-bucket"
  #   key          = "secure-pipeline-demo/terraform.tfstate"
  #   region       = "eu-central-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "secure-pipeline-demo"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# --------------------------------------------------------------------------- ECR

resource "aws_ecr_repository" "app" {
  name                 = var.image_name
  image_tag_mutability = "IMMUTABLE" # a tag can never be silently repointed at different content

  image_scanning_configuration {
    scan_on_push = true # second opinion on top of the pipeline scan
  }

  encryption_configuration {
    encryption_type = "KMS" # AWS-managed KMS key for ECR
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 30 most recent images (and their signatures)"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

# --------------------------------------------------------------------------- GitHub OIDC

# An AWS account can hold only one provider per issuer URL. Set create_oidc_provider = false
# if token.actions.githubusercontent.com is already registered in this account.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only workflows running in the "production" environment of this exact repository can
    # assume the role. Pull requests, forks and other branches or repositories cannot.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:production"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "${var.image_name}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level permissions
  }

  statement {
    sid = "EcrPushPullThisRepoOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  dynamic "statement" {
    for_each = var.create_app_runner ? [1] : []
    content {
      sid       = "DeployThisServiceOnly"
      actions   = ["apprunner:DescribeService", "apprunner:UpdateService"]
      resources = [aws_apprunner_service.app[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.create_app_runner ? [1] : []
    content {
      sid       = "PassEcrAccessRoleToAppRunnerOnly"
      actions   = ["iam:PassRole"]
      resources = [aws_iam_role.apprunner_access[0].arn]

      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["build.apprunner.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
