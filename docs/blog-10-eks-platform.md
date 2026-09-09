# EKS, IRSA, and the Discipline of Destroying What You Build

*What a one-shot, same-day-deleted EKS cluster taught me about cloud Kubernetes, pod identity, and the cost of being sloppy with `terraform destroy`.*

---

## The Problem

Local Kubernetes (`kind`, `minikube`) teaches you pods, Deployments, Helm, even Argo CD. It does **not** teach you the things that make cloud Kubernetes actually *cloud*: a managed control plane, node groups, and IAM Roles for Service Accounts (IRSA). You can fake GitOps locally, but you cannot fake "this pod assumed an AWS role without a single static key."

So I built a real EKS cluster — Terraform from the ground up, Argo CD deploying everything, Prometheus/Grafana observing it, Kyverno guarding it — and then I destroyed it the same day.

## EKS Cost Reality

Before any code, I did the math, because EKS is the first thing in this portfolio that can quietly run up a bill.

- Control plane: **~$0.10/hour** — you pay for it whether or not a pod runs.
- Node (`t3.medium`): **~$0.04/hour**.
- Everything I deliberately skipped: **NAT gateway** (~$32/month), **ALB** (~$18/month), **RDS**, **multi-AZ**.

The trap isn't the hourly rate — it's forgetting. Leave a cluster running for a week because "I'll clean it up later," and you've spent ~$24 on nothing. The SPEC for this project is blunt about it: *destroy same day, mandatory*.

My design was shaped entirely by that constraint: **single AZ, public subnet, no NAT, no load balancer**. The node gets a public IP and egresses through an internet gateway; I reach the app, Argo CD, and Grafana with `kubectl port-forward` instead of load balancers. Everything the demo needs, nothing that lingers.

## IRSA, Actually Explained

The thing I wanted to understand, and the thing a local cluster cannot give you: **how does a pod get AWS permissions without a secret full of keys?**

The old way was an `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` pair dumped into a Secret. It worked. It was also a long-lived credential sitting in a cluster, rotatable only by hand, and a favorite target of every scanner and every attacker.

IRSA flips the model. It works through the EKS OIDC provider:

1. Terraform creates the cluster's **OIDC provider** in IAM — a URL (`oidc.eks.us-east-1.amazonaws.com/id/<id>`) that AWS can cryptographically trust as "this is my cluster."
2. I create an **IAM role** whose trust policy says: *only `sts:AssumeRoleWithWebIdentity`, only from that OIDC provider, and only for the subject `system:serviceaccount:irsa-demo:irsa-sa`.*
3. The pod's **ServiceAccount** gets a single annotation: the role ARN. No keys, no secrets.
4. At pod start, EKS injects a projected service-account token. The AWS SDK exchanges it for temporary credentials of that role.

The trust policy is the whole ballgame. It is scoped to **one service account, in one namespace**. Even if every other pod in the cluster wanted that role, the OIDC subject check refuses them.

Here is the proof, captured from the live cluster. A job bound to the annotated service account:

```
--- identity assumed via IRSA ---
{
    "UserId": "AROAQLVP23GNMUEYZHQ3N:botocore-session-1788918858",
    "Account": "025064823194",
    "Arn": "arn:aws:sts::025064823194:assumed-role/eks-irsa-demo/botocore-session-1788918858"
}
--- list demo bucket (least-privilege read) ---
```

The pod is `eks-irsa-demo` — the exact role, nothing else. Then the negative control. A pod with **no** annotation falls back to the *node's* IAM role through the instance metadata service — which is precisely the anti-pattern IRSA exists to kill. When it tries to read the demo bucket, the node role has no business there:

```
aws s3 ls s3://baasilmirza-eks-irsa-demo-025064823194/
An error occurred (AccessDenied) when calling the ListObjectsV2 operation:
User: arn:aws:sts::025064823194:assumed-role/portfolio-eks-node-eks-node-group-.../i-...
is not authorized to perform: s3:ListBucket on resource:
"arn:aws:s3:::baasilmirza-eks-irsa-demo-025064823194"
because no identity-based policy allows the s3:ListBucket action
```

One pod is the precise, least-privilege principal. The other inherits a shared node identity that can't even touch the bucket. No keys were created, no secrets were stored, and the whole identity is revoked the instant I delete the service account.

The role itself is least-privilege in the boring, correct way: `s3:ListBucket` + `s3:GetObject` on exactly one demo bucket. Not `s3:*`, not `*:*`.

## Local vs Cloud Kubernetes

Building this next to my earlier local-cluster projects made the difference concrete:

| Concept | Local (`kind`) | Cloud (EKS) |
|---|---|---|
| Cluster API | one `kind create cluster` | managed control plane I never patch |
| Node identity | a container on my laptop | an EC2 instance in my VPC |
| Pod → AWS | not a thing | IRSA, first-class |
| Ingress | `localhost:port` | LB/NAT/IP decisions I must make and pay for |
| Networking | loopback | VPC, subnets, route tables, IGW, security groups |

The Kubernetes *objects* are identical. The *decisions around* them are where the learning lives: What subnets? What egress path? What does a pod get to assume? Local clusters keep all of that invisible, which is exactly why one cloud cluster is worth it.

## GitOps: Git Is the Source of Truth

Nothing is installed by hand (except Argo CD itself, once). A single app-of-apps `Application` points at a directory in this repo, and Argo CD syncs four child apps from Git:

- **portfolio-app** — the FastAPI app, packaged as a Helm chart, pulled from ECR
- **observability** — Prometheus + Grafana via `kube-prometheus-stack`
- **kyverno** — the policy engine
- **irsa-demo** — the service account + job that proves IRSA

Every change is a commit. Drift is self-healed. This is the same pattern a real team runs in production, just pointed at a cluster that costs 15 cents an hour.

## Policy Enforcement: Kyverno Says No

Kyverno sits as an admission webhook and enforces three policies. Two are scoped to the app's `portfolio` namespace — pods must carry `team` and `app.kubernetes.io/name` labels, and must set CPU/memory requests+limits. One is cluster-wide — privileged containers are forbidden.

The happy path just works: the app chart already sets its labels and resources. The interesting part is the negative test — a pod that violates the policy:

```
$ kubectl run bad-pod -n portfolio --image=nginx --restart=Never
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/portfolio/bad-pod was blocked due to the following policies

require-labels:
  require-team-and-app-labels: 'validation error: Pods in the 'portfolio' namespace
    must have 'team' and 'app.kubernetes.io/name' labels. ...'

require-requests-limits:
  require-resource-requests-and-limits: 'validation error: Pods in the 'portfolio'
    namespace must set CPU and memory requests and limits. ...'

$ kubectl run priv-pod -n portfolio --image=nginx --restart=Never --privileged
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:

disallow-privileged:
  disallow-privileged-containers: 'validation error: Privileged containers are not
    allowed. securityContext.privileged must be unset or false. ...'
```

Admission control is where "we have a policy" becomes "the cluster enforces the policy." A human forgetting a label gets a hard `denied`, not a nagging email.

## Teardown Discipline

The least glamorous skill in this project, and the one that saves real money: destroying what you built, and *proving* it's gone.

`terraform destroy` is necessary but not sufficient. EKS creates things Terraform doesn't track — load balancers from a `LoadBalancer` service, EBS volumes from a `PersistentVolume`, security groups touched by controllers. The SPEC's orphan check is a list, and I ran it:

```
EKS clusters:      (none)
ELBs:              (none)
EBS volumes:       (none)
security groups:   (none)
IAM roles:         (none)
ECR repos:         (none)
IRSA demo bucket:  NoSuchBucket
CloudWatch groups: (none)
```

54 Terraform resources destroyed, then every orphan check empty: no ELBs, no EBS volumes, no stray security groups, no IAM roles, no ECR repos, no CloudWatch log groups, no demo bucket. Then the state backend itself — S3 bucket and DynamoDB lock table — is destroyed last, so there is no state file keeping the ghost of a cluster alive.

The rule I came away with: **the cluster isn't gone until you've looked, not until Terraform says so.**

## What Broke Along the Way

This project was the most "everything broke, then I fixed it" of the portfolio so far. The honest list:

- **EKS needs two AZs, not one** — my first `terraform apply` failed with `Subnets specified must be in at least two different AZs`. The control plane spans two AZs even when the node group is single-AZ. Fix: two public subnets for the cluster, one subnet for the single node.
- **AL2 is dead on modern EKS** — `AMI Type AL2_x86_64 is only supported for kubernetes versions 1.32 or earlier`. Switched to `AL2023_x86_64_STANDARD`.
- **Access entries, not `aws-auth`** — a brand-new EKS cluster returns `401 Unauthorized` to the very IAM user who created it, because new clusters use EKS Access Entries, not the `aws-auth` ConfigMap. Fix: an `access_entries` block granting my principal `AmazonEKSClusterAdminPolicy`.
- **Private GHCR image** — the P1 app image lived in GitHub's registry as `private`. The EKS node couldn't pull it. Fix: push to a private **ECR** repository in-region; the node's IAM role pulls it with no secrets. Also matched the spec, which lists ECR as a required service.
- **CRDs too big for `kubectl apply`** — Kyverno and Prometheus ship CRDs whose schemas exceed Kubernetes' 256KB limit for the `last-applied-configuration` annotation, so Argo CD couldn't apply them at all: `metadata.annotations: Too long: may not be more than 262144 bytes`. Fix: install the CRDs with `kubectl apply --server-side`, and tell Argo CD to ignore CRD annotation/label diffs.
- **Single-node pod pressure** — a `t3.medium` caps at ~17 pods, and Argo CD + Prometheus + Grafana + Kyverno + the app want more. Fix: scale Argo CD's unused extras (dex, notifications, application-set) to zero, and trim the observability chart (alertmanager off, small limits).
- **The Prometheus operator starts blind** — it cached API discovery before the CRDs existed, so it never created the Prometheus server until a `rollout restart` made it re-discover them.

## Lessons Learned

- **Cost shapes architecture.** Single-AZ node, no NAT, no ALB isn't a compromise — it's the correct design for an ephemeral demo, and it forced me to understand egress paths.
- **IRSA is a trust-policy problem, not a secrets problem.** Get the OIDC subject condition right and the security model falls out of it. And without IRSA, pods silently inherit the node's IAM role — the exact anti-pattern the demo exposes.
- **New-cloud versions bite.** EKS 1.35 dropped AL2, switched to access entries, and ships CRDs that outgrow client-side apply. The platform moves under you; IaC pins it in place.
- **GitOps and policy make the demo self-documenting.** The repo is the system; `verify.sh` is the proof.
- **Destroy is part of the build.** The orphan check is the difference between "I think it's gone" and "it's gone."

---

*Built with Terraform, EKS, IRSA, Argo CD, Helm, Prometheus/Grafana, Kyverno, and ECR. Source on GitHub.*
