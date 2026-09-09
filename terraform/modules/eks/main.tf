module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  enable_irsa = true

  access_entries = {
    cluster_admin = {
      principal_arn = var.cluster_admin_principal_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  eks_managed_node_group_defaults = {
    instance_types = [var.instance_type]
    ami_type       = "AL2023_x86_64_STANDARD"
  }

  eks_managed_node_groups = {
    main = {
      name         = "${var.cluster_name}-node"
      min_size     = 1
      max_size     = 1
      desired_size = 1
      subnet_ids   = var.node_subnet_ids
    }
  }

  tags = var.tags
}
