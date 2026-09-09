#!/usr/bin/env bash
# Provision EKS + IRSA + ECR via Terraform, build & push the app image, install Argo CD.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-portfolio-eks}"
APP_IMAGE_TAG="${APP_IMAGE_TAG:-0.1.0}"
APP_SOURCE="${APP_SOURCE:-https://github.com/baasilmirza/containerized-app-cicd.git}"

cd "$REPO_ROOT/terraform"

echo "==> terraform apply"
terraform init
terraform apply -auto-approve

ECR_URL="$(terraform output -raw ecr_repo_url)"
echo "==> ECR repository: $ECR_URL"

echo "==> build & push app image to ECR"
TMP_APP="$(mktemp -d)"
git clone --depth 1 "$APP_SOURCE" "$TMP_APP/app"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_URL"
docker build -t "$ECR_URL:$APP_IMAGE_TAG" "$TMP_APP/app"
docker push "$ECR_URL:$APP_IMAGE_TAG"
rm -rf "$TMP_APP"

echo "==> update kubeconfig"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "==> install CRDs via server-side apply (large schemas exceed kubectl's 256KB annotation limit)"
CRD_TMP="$(mktemp -d)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm repo update >/dev/null
helm pull kyverno/kyverno --version 3.9.0 --untar --untardir "$CRD_TMP" >/dev/null
helm pull prometheus-community/kube-prometheus-stack --version 90.0.0 --untar --untardir "$CRD_TMP" >/dev/null
kubectl apply --server-side --force-conflicts -f "$CRD_TMP/kube-prometheus-stack/charts/crds/crds/"
helm template kyverno "$CRD_TMP/kyverno" -n kyverno > "$CRD_TMP/kyverno-rendered.yaml"
awk 'BEGIN{RS="---\n"} /kind: CustomResourceDefinition/' "$CRD_TMP/kyverno-rendered.yaml" \
  | kubectl apply --server-side --force-conflicts -f -
rm -rf "$CRD_TMP"

echo "==> install Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

echo "==> apply app-of-apps root"
kubectl apply -f "$REPO_ROOT/argocd/bootstrap/root-app.yaml"

echo "Deploy complete. Run: scripts/verify.sh"
