output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS control plane API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN used by IRSA"
  value       = module.eks.oidc_provider_arn
}

output "irsa_role_arn" {
  description = "IAM role ARN assumed by the IRSA demo service account"
  value       = module.irsa.role_arn
}

output "irsa_bucket_name" {
  description = "S3 bucket the IRSA role can read (least-privilege demo)"
  value       = module.irsa.bucket_name
}

output "ecr_repo_url" {
  description = "ECR repository URL for the application image"
  value       = module.ecr.repo_url
}

output "vpc_id" {
  description = "VPC id"
  value       = module.vpc.vpc_id
}

output "configure_kubectl" {
  description = "Command to update kubeconfig for the cluster"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${module.eks.cluster_name}"
}
