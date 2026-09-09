variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Single availability zone for the cost-controlled cluster"
  type        = string
  default     = "us-east-1a"
}

variable "environment" {
  description = "Deployment environment name (tagging + resource names)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "portfolio-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the managed node group"
  type        = string
  default     = "t3.medium"
}

variable "irsa_namespace" {
  description = "Kubernetes namespace of the IRSA-bound service account"
  type        = string
  default     = "irsa-demo"
}

variable "irsa_service_account" {
  description = "Kubernetes service account granted AWS access via IRSA"
  type        = string
  default     = "irsa-sa"
}

variable "ecr_repo_name" {
  description = "ECR repository name for the application image"
  type        = string
  default     = "portfolio-app"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "project10"
    ManagedBy   = "terraform"
  }
}
