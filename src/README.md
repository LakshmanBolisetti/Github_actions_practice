# How to Configure GitHub Actions OIDC with AWS and Amazon EKS

> A practical guide to configuring GitHub Actions OpenID Connect (OIDC) with AWS IAM, validating the connection with the AWS CLI, and allowing a workflow to deploy to Amazon EKS.
>
> **Sources:**
> * [DevOpsCube – How to Configure GitHub Actions OIDC with AWS (Easy Tutorial)](https://devopscube.com/github-actions-oidc-aws/) | **Authors:** Nitheesh Poojary and Bibin Wilson | **Published:** May 15, 2025 | **Reading time shown on source page:** 9 minutes
> * **DevOps Shack — DevSecOps Deep Dive Series:** *GitHub OIDC-Based Secure Deployment Architecture for Amazon EKS* (`@devopsshack` | 2026)
> * **DevOps Shack:** *GitHub OIDC — The Bootstrap Problem Explained* (`@devopsshack` | `devopsshack.com` | Aditya Jaiswal)

**No long-lived secrets. No kubeconfig stored in GitHub. Short-lived OIDC tokens only.**

A complete, beginner-friendly reference: what every resource is, why it exists, and how every piece connects to the next. This README preserves the technical topics, sequence, examples, and original diagrams/screenshots from the referenced materials.

## Overview

GitHub Actions workflows need an identity that AWS can authenticate before they can call AWS services. OIDC allows a workflow to obtain temporary AWS credentials without keeping long-lived AWS access keys in GitHub repository or organization secrets.

This guide covers:

* Why OIDC is preferable to long-lived AWS access keys for CI/CD.
* How GitHub's OIDC provider and AWS IAM work together.
* How to configure an IAM OIDC identity provider and an assumable IAM role (both via the AWS Management Console UI and via the AWS CLI).
* How to test the connection with AWS CLI.
* How to configure EKS access and deploy workloads to Amazon EKS.

## Sample AWS Deployment Workflow

The example architecture uses GitHub Actions to authenticate to AWS, push container images to Amazon ECR, and deploy an application to Amazon EKS.



The diagram is an architectural example. The hands-on validation in this README first uses EC2 listing, then proceeds to EKS deployment.

## AWS Authentication Methods for GitHub Actions

A workflow must authenticate to AWS before it can access services such as EC2, ECR, or EKS. The common approaches are described below.

### 1. Access keys and secret keys

A traditional workflow can use an IAM user's access key and secret key:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v1
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-west-2
```

This method stores long-lived credentials in GitHub Secrets. If those credentials are exposed, an attacker may be able to use them until they are revoked or otherwise invalidated. For that reason, long-lived credentials are not the preferred method for CI/CD authentication.

### 2. IAM roles for self-hosted runners

A self-hosted GitHub Actions runner hosted on AWS can use an IAM role attached to its underlying AWS compute resource (for example, through an instance profile).

Important distinction:

* This approach applies to self-hosted runners running in an AWS environment.
* It does not provide the same instance-role mechanism to GitHub-hosted public runners.

IAM roles provide temporary security credentials rather than requiring the workflow to store a permanent access key. Those credentials have a limited lifetime and stop being accepted after expiration.

### 3. OpenID Connect (a more secure approach)

With OIDC, a GitHub Actions workflow requests an OIDC token from GitHub and presents it to AWS. AWS validates the token and, if the configured trust conditions match, issues temporary credentials for the IAM role.

Key points:

* AWS access keys do not need to be stored as long-lived GitHub Secrets.
* Temporary credentials are issued when the workflow needs them.
* The credentials expire.
* OIDC can be used with GitHub-hosted and self-hosted runners.

OIDC adds an identity layer to OAuth 2.0. OAuth 2.0 is primarily an authorization framework, while OIDC provides authentication and identity information.

Useful references: [OpenID](https://openid.net/) and [OAuth 2.0](https://oauth.net/2/).

The remaining sections focus on GitHub Actions OIDC with AWS.

## Chapter 1: The Big Picture — Why Do Any of This?

Before writing a single AWS CLI command, let's understand the problem we are solving. This context is what makes every subsequent step feel logical rather than arbitrary.

### 1.1 The Old Way — Static Secrets (and Why It Hurts)

In the traditional CI/CD setup, deploying to Kubernetes from GitHub Actions looks like this:

* You generate a long-lived kubeconfig file or a Kubernetes ServiceAccount token.
* You base64-encode it and paste it into GitHub Secrets as `KUBE_CONFIG_B64` or `K8S_TOKEN`.
* Every pipeline run decodes and uses this token to talk to your cluster.

This works — but it carries serious risks:

| Risk | What actually goes wrong |
| :--- | :--- |
| **Token never expires** | If a static token leaks (e.g. in logs, a public fork, a compromised laptop), it keeps working forever — until someone manually rotates it. |
| **Broad permissions** | Kubernetes ServiceAccount tokens are often cluster-admin or have wide namespace access, so a leak = full cluster compromise. |
| **No audit trail** | AWS/EKS cannot tell you which pipeline run used a token. It just sees an anonymous bearer token. |
| **Secret sprawl** | As team grows, `KUBE_CONFIG_B64`, `K8S_TOKEN`, `K8S_CA_CERT` all sit in GitHub Secrets. Managing rotation is painful. |

### 1.2 The New Way — OIDC Federation (Short-lived, Scoped, Auditable)

OIDC (OpenID Connect) is a standard identity protocol. GitHub has become an OIDC identity provider, meaning it can issue cryptographically-signed certificates that prove: 'This API call is coming from workflow run #1234, in repo `jaiswaladi246/3-Tier-NodeJS-End-To-End-Project`, on the `main` branch.'

AWS can verify that certificate independently — no username, no password, no static token involved. The certificate (called a JWT) expires in about 5 minutes. Here is why that is better:

* A leaked token is useless after 5 minutes.
* The IAM role trust policy can be scoped to only one specific repo and branch. A fork cannot assume the same role.
* CloudTrail shows which IAM role was assumed, when, and which job triggered it — full audit trail.
* No credentials are stored in GitHub Secrets. You only store the IAM role ARN (a public identifier, not a secret).

> **The one-line summary:**
> GitHub proves its identity cryptographically. AWS verifies the proof and issues 15-minute temporary AWS credentials. Those credentials generate a short-lived kubeconfig. `kubectl` uses that kubeconfig to deploy. Nothing sensitive is stored anywhere.

### 1.3 How All the Pieces Connect — The Full Chain

Read this chain before diving into any individual step. Every subsequent chapter is one link in this chain:

1. GitHub Actions workflow runs and requests an OIDC token from GitHub.
2. GitHub issues a signed JWT proving the workflow's identity (repo, branch, ref).
3. The `aws-actions/configure-aws-credentials` action sends that JWT to AWS STS.
4. AWS STS looks up the registered GitHub OIDC provider and verifies the JWT signature.
5. AWS STS checks the IAM role's trust policy: does this token's audience and subject match the allowed values?
6. If yes, STS issues temporary AWS credentials (access key + secret + session token, valid 15 min).
7. The `aws eks update-kubeconfig` command uses those credentials to call `eks:DescribeCluster` and build a kubeconfig.
8. `kubectl` uses the kubeconfig's exec plugin to get an EKS token, which is verified against the EKS access entry.
9. The access entry maps the IAM role to the `AmazonEKSEditPolicy` — scoped only to namespace `project`.
10. `kubectl apply` deploys the workloads. Job ends, credentials expire, nothing persists.

## GitHub OIDC — The Bootstrap Problem Explained

**Why kubeconfig, SA tokens & short-lived tokens all fail**
**The Bootstrap Problem — and why OIDC is the only real solution**

### What is kubeconfig?

A **kubeconfig file** is simply a file that allows you to connect to a Kubernetes cluster.

When you run a command like:

```bash
kubectl get pods
```

`kubectl` doesn't know anything by default. It needs:

* which cluster to connect to
* who you are
* how to authenticate

All of that information comes from the **kubeconfig file**.

So in simple terms:
**kubeconfig is your access file to Kubernetes.**

### How is kubeconfig created?

Most of the time, you don't create it manually.

It gets generated automatically when you connect to a cluster.

For example, in your case with AWS EKS:

```bash
aws eks update-kubeconfig --name my-cluster
```

When you run this:

* AWS gives your cluster endpoint
* sets up authentication using IAM
* stores everything in your kubeconfig file

After this, your system is ready to run `kubectl` commands.

### What does kubeconfig contain?

The file mainly has three things.

First, it has **cluster details** — basically where your Kubernetes cluster is running, including the API server endpoint.

Second, it has **user credentials** — this defines who you are and how you authenticate (like IAM role, token, or certificates).

Third, it has something called a **context** — which is just a mapping of:
cluster + user + namespace.

This tells Kubernetes:
"Use this user to talk to this cluster in this namespace."

### What can you do with kubeconfig?

Once you have a valid kubeconfig file, you can fully interact with the cluster.

You can:

* deploy applications
* create services
* scale workloads
* delete resources

For example:

```bash
kubectl apply -f deployment.yaml
```

This will deploy your app to the cluster using the access defined in kubeconfig.

So yes — **kubeconfig gives you full access to the cluster.**

### Important note (real-world)

Even though kubeconfig can be used to access the cluster and perform deployments, **sharing it directly is not a good practice.**

If someone gets your kubeconfig file, they can control your cluster depending on the permissions.

In production setups, instead of sharing kubeconfig:

* we use IAM roles
* OIDC (like in your GitHub Actions)
* short-lived credentials

### The One Question That Explains Everything

Every authentication method for GitHub Actions → EKS comes down to one question:

> **The Bootstrap Question**
> How does GitHub Actions prove to AWS / Kubernetes that it is allowed to deploy?
>
> * **Scenario 1 (kubeconfig):** Store a credential → use it directly
> * **Scenario 2 (SA long token):** Store a credential → use it directly
> * **Scenario 3 (SA short token):** Store AWS keys → use them to generate a short K8s token
> * **GitHub OIDC:** Prove identity cryptographically → no stored credential needed
>
> The first three all answer: 'trust me, I have the password'.
> OIDC answers: 'verify my identity from a trusted source'.

### Scenario 1: kubeconfig Secret

**Export `~/.kube/config` → base64 encode → store as `KUBE_CONFIG_B64` in GitHub**

#### How It Works

You export your local kubeconfig — which contains either your personal AWS credentials embedded, or a long-lived Kubernetes token. You base64 encode it and store it as a GitHub Secret. The pipeline decodes it at runtime.

```bash
# Export and encode
cat ~/.kube/config | base64 -w 0
# Store as KUBE_CONFIG_B64 in GitHub Secrets

# In the pipeline
echo "$KUBE_CONFIG_B64" | base64 -d > ~/.kube/config
kubectl apply -f k8s/ -n project
```

#### What Goes Wrong

| Problem | Detail |
| :--- | :--- |
| **Token never expires** | Whatever is inside the kubeconfig — admin cert or SA token — is permanent |
| **Base64 is not encryption** | Anyone who can read GitHub Secrets decodes it instantly. It is plain text. |
| **Scope is often too wide** | Teams export admin kubeconfig to avoid RBAC debugging — full cluster access |
| **No branch restriction** | Any branch, any workflow in the repo can use `KUBE_CONFIG_B64` |
| **Zero AWS audit trail** | `kubectl` calls go directly to K8s API — CloudTrail has no record |
| **Personal credential** | Dev leaves team → their kubeconfig is still in production GitHub Secret |

> **Leak Scenario**
> `KUBE_CONFIG_B64` leaks → attacker decodes base64 → gets full `kubectl` access → permanent.
> Remediation: find a new kubeconfig, re-encode, update secret. Meanwhile cluster is compromised.

### Scenario 2: ServiceAccount Long-Lived Token

**Create a dedicated SA → extract its JWT token → store as `K8S_SA_TOKEN`**

#### How It Works

Instead of exporting your personal kubeconfig, you create a Kubernetes ServiceAccount specifically for GitHub Actions, bind it to a Role (or ClusterRole), extract its token, and store that token in GitHub Secrets. This feels more controlled — same underlying problem.

```bash
# Create SA and bind role
kubectl create serviceaccount github-deploy -n project
kubectl create rolebinding github-deploy-rb \
  --clusterrole=edit --serviceaccount=project:github-deploy -n project

# Extract token (Kubernetes < 1.24 auto-creates a secret)
SECRET=$(kubectl get sa github-deploy -n project -o jsonpath='{.secrets[0].name}')
TOKEN=$(kubectl get secret $SECRET -n project -o jsonpath='{.data.token}' | base64 -d)
SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')

# Store TOKEN, SERVER, CA_CERT as GitHub Secrets

# In the pipeline
kubectl config set-credentials github-deploy --token=$K8S_SA_TOKEN
kubectl config set-cluster my-cluster --server=$K8S_SERVER
kubectl apply -f k8s/ -n project
```

#### Is This Better Than Scenario 1?

Slightly. The scope is smaller (dedicated SA, not admin). But the mechanism is identical — you still stored a permanent credential in GitHub Secrets.

| Problem | Detail |
| :--- | :--- |
| **Token is still permanent** | Kubernetes SA tokens (pre-1.24) have no TTL. They work forever. |
| **Still stored in GitHub** | `K8S_SA_TOKEN` is a permanent K8s credential sitting in GitHub Secrets |
| **Scope creep happens** | Teams start with 'edit'. Debugging breaks → add cluster-admin. Never revert. |
| **Still no AWS trail** | SA token calls go to K8s API server. AWS CloudTrail sees nothing. |
| **Still no branch restrict** | `K8S_SA_TOKEN` available to every branch and workflow |
| **Remediation breaks CI/CD** | Token leaked → delete SA to revoke → pipeline immediately stops working |

> **Scenario 1 vs Scenario 2 — Are They Really Different?**
> Not fundamentally. Both store a long-lived Kubernetes credential in GitHub Secrets.
> Scenario 1 = admin/personal kubeconfig → wider blast radius
> Scenario 2 = dedicated SA token → smaller blast radius
>
> Same mechanism. Same root problem. Different privilege scope.
> The real problem — a permanent stored credential — is identical in both.

### Scenario 3: ServiceAccount Short-Lived Token (TokenRequest API)

**Generate a 1hr K8s token at runtime — but you still need AWS keys to bootstrap**

#### How It Works

Kubernetes 1.20+ introduced the TokenRequest API. Instead of storing a permanent SA token, you generate a time-limited token (1hr) at the start of each pipeline run using `'kubectl create token'`. The K8s token itself is short-lived. This sounds like the solution — until you ask the bootstrap question.

#### The Bootstrap Problem

To call `'kubectl create token'` from GitHub Actions, you first need to authenticate to EKS. You cannot call `kubectl` against EKS without a valid kubeconfig. To get that kubeconfig, you must run:

```bash
aws eks update-kubeconfig --name my-cluster --region ap-south-1
```

And to run that AWS CLI command, you need AWS credentials. Which means you need to store:

> **What You Must Store in GitHub Secrets for Scenario 3**
> `AWS_ACCESS_KEY_ID` ← long-lived AWS credential
> `AWS_SECRET_ACCESS_KEY` ← long-lived AWS credential
>
> These are permanent. They never expire unless you manually rotate them.
> You solved the Kubernetes token expiry problem.
> You replaced it with a permanent AWS credential problem.

The full pipeline flow for Scenario 3:

```bash
# Step 1: Authenticate to AWS using stored long-lived keys
aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY

# Step 2: Build kubeconfig using AWS creds
aws eks update-kubeconfig --name my-cluster --region ap-south-1

# Step 3: Generate short-lived K8s token (1hr)
TOKEN=$(kubectl create token github-deploy \
  --namespace project --duration=3600s)

# Step 4: Rebuild kubeconfig with the short-lived token
kubectl config set-credentials github-deploy --token=$TOKEN

# Step 5: Deploy
kubectl apply -f k8s/ -n project
```

You went through 5 steps and you still have `AWS_ACCESS_KEY_ID` in GitHub Secrets. The K8s token is short-lived — the bootstrap credential is not.

#### What Scenario 3 Gets Right

* The Kubernetes token expires in 1hr — if intercepted, limited window
* No permanent SA token stored in GitHub Secrets
* Slightly better audit than Scenarios 1 & 2 (AWS CloudTrail sees the `update-kubeconfig` call)

#### What Scenario 3 Still Gets Wrong

| Remaining Problem | Why It Matters |
| :--- | :--- |
| **AWS keys stored permanently** | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` in GitHub — these never expire |
| **Worse blast radius than Scenarios 1&2** | AWS keys can access your ENTIRE AWS account — not just EKS |
| **Still no branch restriction** | Any branch can use the AWS keys to bootstrap and generate a token |
| **Key rotation breaks pipelines** | Rotate AWS keys → pipelines break → update 2 secrets under pressure |
| **Extra complexity, same risk** | 5 steps instead of 1, but the stored credential problem is unchanged |

> **The Bootstrap Problem — Visualised**
> * Scenario 1: GitHub → `[KUBE_CONFIG_B64]` → `kubectl` → EKS
> * Scenario 2: GitHub → `[K8S_SA_TOKEN]` → `kubectl` → EKS
> * Scenario 3: GitHub → `[AWS_ACCESS_KEY + SECRET_KEY]` → `aws eks update-kubeconfig` → `kubectl create token (1hr)` → `kubectl` → EKS
>
> All three have a `[ ]` — something permanent stored in GitHub.
> You cannot escape the bootstrap problem without OIDC.

### GitHub OIDC — How It Breaks the Bootstrap Problem

OIDC removes the `[ ]` entirely. GitHub proves its identity to AWS using a cryptographically signed JWT that it generates per run. There is nothing to store. Nothing to rotate. Nothing to leak.

```text
GitHub Actions starts
  │
  │  GitHub generates a signed JWT (per run):
  │    iss: token.actions.githubusercontent.com
  │    sub: repo:jaiswaladi246/3-Tier-NodeJS:ref:refs/heads/main
  │    aud: sts.amazonaws.com
  │    exp: now + 5 min  ← one-time use
  │
  ▼ sent to AWS STS
IAM Trust Policy validates:
  ✓ JWT signature matches GitHub public key
  ✓ sub = repo:jaiswaladi246/3-Tier-NodeJS:ref:refs/heads/main
  ✓ aud = sts.amazonaws.com
  │
  ▼ issues temporary STS credentials [TTL: 15 min]
aws eks update-kubeconfig --name my-cluster --region ap-south-1
  │
  ▼ EKS Access Entry → AmazonEKSEditPolicy → namespace: project
kubectl apply -f k8s/  →  deployment succeeds
  │
  └── Credentials expire. Nothing to clean up.
```
