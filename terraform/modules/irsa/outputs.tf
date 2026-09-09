output "role_arn" {
  description = "IAM role ARN assumed by the service account via IRSA"
  value       = aws_iam_role.this.arn
}

output "bucket_name" {
  description = "S3 bucket the role can read"
  value       = aws_s3_bucket.demo.id
}
