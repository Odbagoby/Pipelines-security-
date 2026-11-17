# Optional runtime. Enable with create_app_runner = true AFTER the pipeline has pushed a first image,
# because App Runner needs an existing image to start from.

locals {
  # The parameter is created out of band (see README). Only its ARN is referenced here, so the
  # secret value never enters Terraform code or state.
  api_key_parameter_arn = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.api_key_ssm_parameter_name}"
}

# Role App Runner uses to pull the image from ECR.
data "aws_iam_policy_document" "apprunner_access_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_access" {
  count              = var.create_app_runner ? 1 : 0
  name               = "${var.image_name}-apprunner-access"
  assume_role_policy = data.aws_iam_policy_document.apprunner_access_trust.json
}

data "aws_iam_policy_document" "apprunner_access" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "apprunner_access" {
  count  = var.create_app_runner ? 1 : 0
  name   = "ecr-pull"
  role   = aws_iam_role.apprunner_access[0].id
  policy = data.aws_iam_policy_document.apprunner_access.json
}

# Role the running container uses. Its only permission is to read its own API key.
data "aws_iam_policy_document" "apprunner_instance_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["tasks.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_instance" {
  count              = var.create_app_runner ? 1 : 0
  name               = "${var.image_name}-apprunner-instance"
  assume_role_policy = data.aws_iam_policy_document.apprunner_instance_trust.json
}

data "aws_iam_policy_document" "apprunner_instance" {
  statement {
    actions   = ["ssm:GetParameters"]
    resources = [local.api_key_parameter_arn]
  }
}

resource "aws_iam_role_policy" "apprunner_instance" {
  count  = var.create_app_runner ? 1 : 0
  name   = "read-api-key"
  role   = aws_iam_role.apprunner_instance[0].id
  policy = data.aws_iam_policy_document.apprunner_instance.json
}

resource "aws_apprunner_service" "app" {
  count        = var.create_app_runner ? 1 : 0
  service_name = var.image_name

  source_configuration {
    auto_deployments_enabled = false # deployments happen only through the gated pipeline

    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access[0].arn
    }

    image_repository {
      image_identifier      = "${aws_ecr_repository.app.repository_url}:${var.initial_image_tag}"
      image_repository_type = "ECR"

      image_configuration {
        port = "8080"
        runtime_environment_secrets = {
          API_KEY = local.api_key_parameter_arn
        }
      }
    }
  }

  instance_configuration {
    cpu               = "256"
    memory            = "512"
    instance_role_arn = aws_iam_role.apprunner_instance[0].arn
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = "/healthz"
  }

  lifecycle {
    # The pipeline moves the image tag forward on every release; Terraform should not roll it back.
    ignore_changes = [source_configuration[0].image_repository[0].image_identifier]
  }

  depends_on = [
    aws_iam_role_policy.apprunner_access,
    aws_iam_role_policy.apprunner_instance,
  ]
}
