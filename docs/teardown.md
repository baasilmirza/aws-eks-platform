# Teardown & Orphan Check

`terraform destroy` is necessary but **not sufficient** for an EKS cluster. Controllers create resources Terraform doesn't track. This is the full teardown procedure.

## Why an orphan check

- A `LoadBalancer` Service creates an **ELB/NLB** outside the Terraform graph.
- A `PersistentVolumeClaim` creates an **EBS volume**.
- Controllers can create **security groups** and **IAM roles**.
- Left alone, these bill you indefinitely.

## Procedure

```bash
./scripts/teardown.sh
```

The script does, in order:

1. `terraform destroy` — tears down EKS, VPC, IRSA role, ECR repo, demo bucket.
2. **Orphan check** — queries AWS for anything that should be gone:

| Resource | Check |
|---|---|
| EKS clusters | `aws eks list-clusters` filtered by name |
| ELBs | `aws elbv2 describe-load-balancers` |
| EBS volumes | `aws ec2 describe-volumes` (non-`available`) |
| Security groups | filtered by `portfolio-eks` name |
| IAM roles | `eks-irsa-demo` |
| ECR repos | `portfolio-app` |
| IRSA demo bucket | `aws s3 ls s3://baasilmirza-eks-irsa-demo-<acct>` |
| CloudWatch log groups | filtered by `portfolio-eks` |

3. **Destroy the state backend** last — the S3 bucket + DynamoDB lock table are intentionally outside the main config (same pattern as a production control plane), so `terraform destroy` can't delete the state it is reading. Removing them last means no state file keeps a cluster's ghost alive.

## Ordering matters

EKS cluster creation is slow (~10–15 min); destruction is too. Because the node group, OIDC provider, and VPC all depend on the cluster, `terraform destroy` resolves that graph for you — but it's normal for it to take several minutes and for the first destroy to fail if resources are still in use; re-run it.

## Cost safety checklist

- [ ] Single AZ, no NAT, no ALB
- [ ] One `t3.medium` node
- [ ] `terraform destroy` immediately after demo
- [ ] Orphan check clean
- [ ] State backend destroyed
- [ ] **Billing console checked next day**
