data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "vpc" {
  source = "./modules/vpc"

  name               = var.cluster_name
  cidr               = var.vpc_cidr
  availability_zone  = var.availability_zone
  public_subnet_cidr = var.public_subnet_cidr
  tags               = var.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids
  instance_type   = var.instance_type
  tags            = var.tags
}

module "ecr" {
  source = "./modules/ecr"

  repo_name = var.ecr_repo_name
  tags      = var.tags
}

module "irsa" {
  source = "./modules/irsa"

  account_id        = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = var.irsa_namespace
  service_account   = var.irsa_service_account
  tags              = var.tags
}
