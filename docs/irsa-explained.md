# IRSA Explained

How a pod gets AWS permissions without a single static key.

## The old way (and why it's bad)

Put `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in a Kubernetes Secret, mount it as env vars. Problems:

- Long-lived credential sitting in a cluster, readable by anyone with RBAC to that Secret.
- Manual rotation.
- A favorite target of secret scanners and attackers.
- One key shared across every pod that needs AWS — no per-workload scoping.

## The IRSA way

Identity, not keys. A pod proves *who it is* (via its service account) and AWS grants it a role accordingly.

### The moving parts

1. **EKS OIDC provider** — the cluster exposes an OIDC endpoint (`oidc.eks.<region>.amazonaws.com/id/<id>`). Terraform registers it in IAM so AWS can verify tokens issued by *this* cluster.
2. **IAM role + trust policy** — an `AssumeRoleWithWebIdentity` trust, limited to that OIDC provider **and** to a specific `sub` (subject):
   ```
   system:serviceaccount:<namespace>:<service-account>
   ```
3. **ServiceAccount annotation** — the pod's SA carries `eks.amazonaws.com/role-arn`.
4. **Projected token** — EKS injects a signed JWT into the pod; the AWS SDK exchanges it for temporary role credentials.

### The trust policy is the whole ballgame

```json
{
  "Effect": "Allow",
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Principal": { "Federated": "arn:aws:iam::<acct>:oidc-provider/oidc.eks...id/<id>" },
  "Condition": {
    "StringEquals": {
      "<issuer>:aud": "sts.amazonaws.com",
      "<issuer>:sub": "system:serviceaccount:irsa-demo:irsa-sa"
    }
  }
}
```

Two conditions matter:

- `:aud` — the token must be intended for `sts.amazonaws.com` (prevents a token minted for another service being replayed).
- `:sub` — the token's subject must be exactly that service account. One namespace, one SA. Every other pod in the cluster is refused, even though they share the same OIDC provider.

### Terraform (this repo)

`terraform/modules/irsa/main.tf` builds the trust policy from the EKS module's `oidc_provider_arn` by stripping the `arn:aws:iam::<acct>:oidc-provider/` prefix to recover the issuer, then scoping to `var.namespace` / `var.service_account`.

### The demo, end to end

1. `terraform apply` creates the OIDC provider + the `eks-irsa-demo` role + a demo S3 bucket.
2. `argocd/irsa-demo/service-account.yaml` annotates `irsa-sa` with the role ARN.
3. `argocd/irsa-demo/job.yaml` runs `aws sts get-caller-identity` and `aws s3 ls s3://<bucket>/` using *only* the projected token.
4. `scripts/verify.sh` runs the same `aws sts get-caller-identity` with the default SA (no annotation) → `AccessDenied`.

### Why this matters

- **No secrets in the cluster.**
- **Per-workload, least-privilege IAM** — a pod gets exactly the role its service account maps to.
- **Revocation is deletion** — delete the SA (or the role) and the identity is gone.

## Limits / notes

- Only works on EKS (or clusters that replicate the OIDC→IAM web-identity flow).
- The role name + account id are baked into the manifest here for determinism; in a real pipeline they'd come from Terraform output into a templated value.
