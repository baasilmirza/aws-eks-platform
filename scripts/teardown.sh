#!/usr/bin/env bash
# Destroy the cluster and verify no orphan resources remain.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

cd "$REPO_ROOT/terraform"

echo "==> terraform destroy"
terraform destroy -auto-approve

echo "==> orphan check"
echo "--- EKS clusters"
aws eks list-clusters --region "$REGION" --query "clusters[?contains(@,'portfolio-eks')]" --output text
echo "--- ELBs"
aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[].LoadBalancerName" --output text
echo "--- EBS volumes"
aws ec2 describe-volumes --region "$REGION" \
  --query "Volumes[?State!='available'].VolumeId" --output text
echo "--- security groups (should be none named *portfolio-eks*)"
aws ec2 describe-security-groups --region "$REGION" \
  --query "SecurityGroups[?contains(GroupName,'portfolio-eks')].GroupId" --output text
echo "--- IAM roles (should be empty)"
aws iam list-roles --query "Roles[?contains(RoleName,'eks-irsa-demo')].RoleName" --output text
echo "--- ECR repos (should be empty)"
aws ecr describe-repositories --region "$REGION" \
  --query "repositories[?repositoryName=='portfolio-app'].repositoryName" --output text
echo "--- IRSA demo bucket (should be empty)"
aws s3 ls "s3://baasilmirza-eks-irsa-demo-$ACCOUNT_ID" 2>&1 || echo "(gone)"
echo "--- CloudWatch log groups (should be empty)"
aws logs describe-log-groups --region "$REGION" \
  --query "logGroups[?contains(logGroupName,'portfolio-eks')].logGroupName" --output text

echo "==> destroy state backend (S3 bucket + DynamoDB lock)"
cd "$REPO_ROOT/terraform/bootstrap"
terraform destroy -auto-approve

echo "Teardown complete. Check AWS billing console tomorrow to confirm."
