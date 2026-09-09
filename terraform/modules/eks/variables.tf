variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "vpc_id" {
  description = "VPC id to deploy the cluster into"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet ids for the cluster control plane"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnet ids for the node group (single AZ)"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for managed node group"
  type        = string
}

variable "cluster_admin_principal_arn" {
  description = "IAM principal ARN granted cluster admin access via an EKS access entry"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
