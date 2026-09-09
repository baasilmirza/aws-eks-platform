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
<IRSA_JOB_OUTPUT>
```

And a control pod — same `aws sts get-caller-identity`, but the *default* service account, no annotation:

```
<IRSA_DENY_OUTPUT>
```

One pod is a first-class AWS principal. The other is nobody. No keys were created, no secrets were stored, and the whole identity is revoked the instant I delete the service account.

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
<KYVERNO_DENY_OUTPUT>
```

Admission control is where "we have a policy" becomes "the cluster enforces the policy." A human forgetting a label gets a hard `denied`, not a nagging email.

## Teardown Discipline

The least glamorous skill in this project, and the one that saves real money: destroying what you built, and *proving* it's gone.

`terraform destroy` is necessary but not sufficient. EKS creates things Terraform doesn't track — load balancers from a `LoadBalancer` service, EBS volumes from a `PersistentVolume`, security groups touched by controllers. The SPEC's orphan check is a list, and I ran it:

```
<ORPHAN_CHECK_OUTPUT>
```

Empty everywhere: no ELBs, no EBS volumes, no stray security groups, no IAM roles, no ECR repos, no CloudWatch log groups, no demo bucket. Then the state backend itself — S3 bucket and DynamoDB lock table — is destroyed last, so there is no state file keeping the ghost of a cluster alive.

The rule I came away with: **the cluster isn't gone until you've looked, not until Terraform says so.**

## What Broke Along the Way

- **Private GHCR image** — the P1 app image lived in GitHub's registry as `private`. The EKS node couldn't pull it. Fix: push to a private **ECR** repository in-region instead; the node's IAM role pulls it with no secrets. It also matched the project spec, which lists ECR as a required service.
- **Single-node memory pressure** — Argo CD + Prometheus + Grafana + Kyverno on one `t3.medium` means you think about resource requests for real. The observability chart is trimmed (alertmanager off, small limits) and Kyverno runs admission-only, not its background/report controllers.
- **Subnet public-IP gotcha** — a node in a public subnet still needs `map_public_ip_on_launch = true` or it can't reach the internet to pull images. Easy to miss, instantly obvious when the node won't join.

## Lessons Learned

- **Cost shapes architecture.** Single-AZ, no NAT, no ALB isn't a compromise — it's the correct design for an ephemeral demo, and it forced me to understand egress paths.
- **IRSA is a trust-policy problem, not a secrets problem.** Get the OIDC subject condition right and the security model falls out of it.
- **GitOps and policy make the demo self-documenting.** The repo is the system; `verify.sh` is the proof.
- **Destroy is part of the build.** The orphan check is the difference between "I think it's gone" and "it's gone."

---

*Built with Terraform, EKS, IRSA, Argo CD, Helm, Prometheus/Grafana, Kyverno, and ECR. Source on GitHub.*
