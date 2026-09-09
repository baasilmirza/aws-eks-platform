output "repo_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.this.repository_url
}

output "repo_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.this.arn
}
