output "aws_role_arn" {
  description = "Set as the GitHub repository variable AWS_ROLE_ARN."
  value       = aws_iam_role.github_deploy.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "apprunner_service_arn" {
  description = "Set as the GitHub repository variable APPRUNNER_SERVICE_ARN."
  value       = var.create_app_runner ? aws_apprunner_service.app[0].arn : null
}

output "apprunner_access_role_arn" {
  description = "Set as the GitHub repository variable APPRUNNER_ACCESS_ROLE_ARN."
  value       = var.create_app_runner ? aws_iam_role.apprunner_access[0].arn : null
}

output "service_url" {
  value = var.create_app_runner ? "https://${aws_apprunner_service.app[0].service_url}" : null
}
