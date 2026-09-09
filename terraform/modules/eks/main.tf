module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  enable_irsa = true

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  eks_managed_node_group_defaults = {
    instance_types = [var.instance_type]
    ami_type       = "AL2_x86_64"
  }

  eks_managed_node_groups = {
    main = {
      name         = "${var.cluster_name}-node"
      min_size     = 1
      max_size     = 1
      desired_size = 1
      subnet_ids   = var.subnet_ids
    }
  }

  tags = var.tags
}
