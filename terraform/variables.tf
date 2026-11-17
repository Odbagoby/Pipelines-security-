variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the form owner/name with no wildcards."
  }
}

variable "image_name" {
  description = "ECR repository name. Must match IMAGE_NAME in the workflow."
  type        = string
  default     = "secure-notes-api"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set to false if the account already has one."
  type        = bool
  default     = true
}

variable "create_app_runner" {
  description = "Create the App Runner service. Enable after the first image has been pushed."
  type        = bool
  default     = false
}

variable "initial_image_tag" {
  description = "Image tag (commit SHA) App Runner starts from. Required when create_app_runner is true."
  type        = string
  default     = ""
}

variable "api_key_ssm_parameter_name" {
  description = "Name of an existing SSM SecureString parameter that holds the API key."
  type        = string
  default     = "/secure-notes-api/api-key"
}
