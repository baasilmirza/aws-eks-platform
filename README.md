# Integrated AWS + Kubernetes Platform

A real end-to-end cloud platform in one coherent system: a Terraform-provisioned EKS cluster running an application deployed through Argo CD (GitOps), observed by Prometheus/Grafana, and guarded by Kyverno — all granted AWS access through IRSA. Built as a **one-shot, same-day-destroyed** proof that cloud Kubernetes is more than a local toy.

```
Terraform ──> EKS (control plane + node) ──> Argo CD ──> app + observability
                  │──> IRSA (IAM)              │
                  │──> ECR (image)             └──> Kyverno policies
```

## What this proves

1. **EKS via Terraform** — managed control plane, node groups, VPC networking. A local `kind` cluster cannot teach IAM IRSA or the managed control plane.
2. **IRSA (IAM Roles for Service Accounts)** — a pod assumes a least-privilege IAM role with *no static AWS keys*, and a control pod is *denied*.
3. **GitOps with Argo CD** — an app-of-apps pattern where Git is the single source of truth for the app, the observability stack, Kyverno, and the IRSA demo.
4. **Observability** — Prometheus scrapes the cluster and Grafana visualizes it, deployed as a Helm chart through Argo CD.
5. **Policy enforcement with Kyverno** — non-compliant pods are denied at admission time.
6. **Teardown discipline** — `terraform destroy` returns a clean state, verified by an orphan-resource check.

## Architecture

```
                        ┌────────────────────────────────────────────┐
                        │              AWS account                  │
                        │  ┌──────────────────────────────────────┐  │
                        │  │  VPC (2 public subnets / 2 AZs)      │  │
                        │  │    └─ EKS cluster (1.35)             │  │
                        │  │         ├─ OIDC provider  ──> IAM    │  │
                        │  │         │       role (IRSA)          │  │
                        │  │         └─ node group (t3.medium,    │  │
                        │  │              single AZ)              │  │
                        │  │              └─ Argo CD              │  │
                        │  │                   ├─ portfolio-app   │  │
                        │  │                   ├─ Prometheus/     │  │
                        │  │                   │  Grafana         │  │
                        │  │                   ├─ Kyverno         │  │
                        │  │                   └─ IRSA demo job   │  │
                        │  └──────────────────────────────────────┘  │
                        │  ECR (app image)   S3 (IRSA demo bucket)   │
                        └────────────────────────────────────────────┘
```

Key design choices, all cost-driven (no Free Tier here):

- **No NAT, no ALB** — two public subnets (EKS requires the control plane to span two AZs), but a **single node in one AZ**. The node gets a public IP and egresses through an internet gateway. NAT (~$32/mo) and load balancers are skipped; access to the app, Argo CD, and Grafana is via `kubectl port-forward`.
- **One `t3.medium` node** — small enough to stay cheap (~$0.04/h), large enough to host Argo CD + the app + a trimmed Prometheus/Grafana + Kyverno together. Argo CD's unused extras (dex, notifications, application-set) are scaled to zero to stay under the node's ~17-pod limit.
- **ECR for the app image** — built once, pushed to a private in-region registry, pulled by the node's IAM role. No public registry, no pull secrets.
- **IRSA over access keys** — the OIDC provider maps a Kubernetes service account to an IAM role; the trust policy is scoped to that one service account in that one namespace.
- **Access entries over `aws-auth`** — EKS 1.35 grants admin via an access entry, not the legacy ConfigMap; Terraform declares it for the operator principal.

## Repository layout

```
terraform/
├── bootstrap/            # one-time state backend: S3 bucket + DynamoDB lock
├── modules/
│   ├── vpc/              # single-AZ public VPC, IGW, route table
│   ├── eks/              # EKS cluster + t3.medium managed node group + OIDC
│   ├── ecr/              # ECR repo for the app image
│   └── irsa/             # OIDC-trust IAM role + least-privilege S3 demo bucket
├── main.tf               # wires modules
├── backend.tf            # S3 remote state
├── variables.tf / outputs.tf / versions.tf
helm/
├── portfolio-app/        # app chart (ECR image, ClusterIP svc, probes, resources)
├── observability/        # kube-prometheus-stack dependency, trimmed for one node
└── kyverno/              # kyverno dependency, admission controller only
argocd/
├── bootstrap/root-app.yaml   # app-of-apps entrypoint
├── apps/                     # child apps: portfolio-app, observability, kyverno, kyverno-policies, irsa-demo
└── irsa-demo/                # namespace + annotated SA + Job (proves IRSA)
kyverno/
└── policies/             # require-labels, require-requests-limits, disallow-privileged
scripts/
├── bootstrap.sh          # create state backend
├── deploy.sh             # terraform apply + build/push image + install Argo CD
├── verify.sh             # prove app, observability, Kyverno, IRSA
└── teardown.sh           # destroy + orphan check + state backend cleanup
docs/
├── blog-10-eks-platform.md   # the writeup
├── irsa-explained.md         # how IRSA actually works
└── teardown.md               # destroy + orphan cleanup walkthrough
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with credentials that can create EKS/EC2/VPC/IAM/S3/DynamoDB/ECR resources
- `kubectl`, `docker`, `helm`, `git`

## Quickstart

```bash
# 1. Create the state backend (S3 + DynamoDB)
./scripts/bootstrap.sh

# 2. Provision EKS, build & push the app image, install Argo CD, apply the app-of-apps root
./scripts/deploy.sh

# 3. Prove it works
./scripts/verify.sh
```

`deploy.sh` does the heavy lifting:

1. `terraform apply` — VPC, EKS cluster + node group, OIDC provider, ECR repo, IRSA role + demo bucket.
2. Builds the FastAPI app (from the P1 repo) and pushes it to ECR.
3. `aws eks update-kubeconfig`.
4. Installs Argo CD via the upstream `stable` manifest.
5. Applies the app-of-apps root — Argo CD then syncs the app, observability, Kyverno, and the IRSA demo from Git.

## Verifying each acceptance criterion

| Criterion | How to verify |
|---|---|
| EKS provisioned via Terraform | `terraform output cluster_endpoint`; `kubectl get nodes` shows one `Ready` node |
| IRSA grants least-privilege access | `scripts/verify.sh` shows the job assuming `eks-irsa-demo` and listing the bucket; the control pod is denied |
| Argo CD deploys app + observability | `kubectl get applications -n argocd` — all `Synced`/`Healthy` |
| Kyverno policies enforced | `kubectl run bad-pod ...` and `--privileged` are both denied |
| `terraform destroy` clean | `scripts/teardown.sh` orphan check prints empty everywhere |
| Orphan check done | ELBs, EBS volumes, security groups, IAM roles, ECR images, log groups, demo bucket |

## Security posture

- **IRSA trust is scoped** to `system:serviceaccount:irsa-demo:irsa-sa` — no other pod in the cluster can assume the role.
- **The IRSA role is least-privilege** — `s3:ListBucket` + `s3:GetObject` on exactly one demo bucket, nothing else.
- **Kyverno `Enforce`** — pods in `portfolio` must carry labels and set CPU/memory requests+limits; privileged containers are denied cluster-wide.
- **App runs as non-root** (`runAsNonRoot: true`, uid 1000) — inherited from the P1 image, enforced by the chart.
- **ECR scans on push** and expires old images after 3.

## Known quirks

- **CRDs need server-side apply** — Kyverno and Prometheus ship CRDs whose schemas exceed Kubernetes' 256KB `last-applied-configuration` limit, so client-side `kubectl apply` (Argo CD's default) fails with `metadata.annotations: Too long`. `deploy.sh` installs them with `kubectl apply --server-side`, and the Argo CD apps carry `ignoreDifferences` on CRD annotations/labels so drift detection doesn't fight the out-of-band install.
- **Prometheus operator restarts blind** — the operator caches API discovery at startup; if it starts before its CRDs exist, it needs a `rollout restart` to re-discover them.
- **EKS access is via Access Entries** — EKS 1.35 uses access entries, not the `aws-auth` ConfigMap. Terraform declares the operator principal's access entry in `modules/eks`.

## Destroy

```bash
./scripts/teardown.sh
```

This runs `terraform destroy`, then an orphan check across ELBs, EBS volumes, security groups, IAM roles, ECR repositories, the IRSA demo bucket, and CloudWatch log groups, and finally destroys the state backend. **Destroy the same day** — the cluster costs ~$0.15/h (control plane ~$0.10/h + node ~$0.04/h).

## Cost

- EKS control plane ~ $0.10/h
- `t3.medium` node ~ $0.04/h
- No NAT, no ALB, no RDS. State bucket + DynamoDB + ECR: pennies.
- A full 6-hour session ≈ **$0.85**; 24 h ≈ **$3.40**. Destroy right after the demo → well under $1.

## Blog post

See [`docs/blog-10-eks-platform.md`](docs/blog-10-eks-platform.md) — EKS cost reality → IRSA explained → local vs cloud k8s → teardown discipline.
