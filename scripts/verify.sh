#!/usr/bin/env bash
# Verify the full stack: app, Argo CD, observability, Kyverno, IRSA.
set -euo pipefail

echo "==> Argo CD apps (should all be Healthy/Synced)"
kubectl get applications -n argocd

echo "==> app pods"
kubectl get pods -n portfolio

echo "==> IRSA demo job log (identity + S3 access via pod IAM)"
kubectl wait --for=condition=complete --timeout=120s job/irsa-demo -n irsa-demo
kubectl logs -n irsa-demo job/irsa-demo

echo "==> IRSA negative control (no service account -> AccessDenied)"
kubectl run irsa-deny \
  -n irsa-demo \
  --image=public.ecr.aws/aws-cli/aws-cli:latest \
  --restart=Never \
  --command -- /bin/sh -c "aws sts get-caller-identity" || true
sleep 10
kubectl logs -n irsa-demo irsa-deny || true
kubectl delete pod irsa-deny -n irsa-demo --ignore-not-found

echo "==> Kyverno policy enforcement"
echo "--- compliant app pod is running:"
kubectl get pods -n portfolio
echo "--- denied pod (no labels) -> expect 'denied by require-labels':"
kubectl run bad-pod -n portfolio --image=nginx --restart=Never 2>&1 || true
echo "--- denied pod (privileged) -> expect 'denied by disallow-privileged':"
kubectl run priv-pod -n portfolio --image=nginx --restart=Never --privileged 2>&1 || true

echo "==> ports to try (run in separate terminals)"
echo "    kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "    kubectl -n portfolio port-forward svc/portfolio-app 8000:80"
echo "    kubectl -n monitoring port-forward svc/observability-grafana 3000:80"
