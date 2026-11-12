# 🔐 How to Configure GitHub Actions OIDC with AWS and Amazon EKS ☸️

> 📖 **A practical guide to configuring GitHub Actions OpenID Connect (OIDC) with AWS IAM, validating the connection with the AWS CLI, and allowing a workflow to deploy to Amazon EKS.**
>
> 📌 **Sources:**
> * 🌐 [DevOpsCube – How to Configure GitHub Actions OIDC with AWS (Easy Tutorial)](https://devopscube.com/github-actions-oidc-aws/) | **Authors:** Nitheesh Poojary and Bibin Wilson | **Published:** May 15, 2025 | **Reading time shown on source page:** 9 minutes
> * 📘 **DevOps Shack — DevSecOps Deep Dive Series:** *GitHub OIDC-Based Secure Deployment Architecture for Amazon EKS* (`@devopsshack` | 2026)
> * 📙 **DevOps Shack:** *GitHub OIDC — The Bootstrap Problem Explained* (`@devopsshack` | `devopsshack.com` | Aditya Jaiswal)

&lt;span style=&quot;color: #ea580c;&quot;&gt;&lt;strong&gt;🔥 DEVSECOPS DEEP DIVE&lt;/strong&gt;&lt;/span&gt;

🛡️ **&lt;span style=&quot;color: #16a34a;&quot;&gt;No long-lived secrets.&lt;/span&gt; &lt;span style=&quot;color: #2563eb;&quot;&gt;No kubeconfig stored in GitHub.&lt;/span&gt; &lt;span style=&quot;color: #7c3aed;&quot;&gt;Short-lived OIDC tokens only.&lt;/span&gt;**

A complete, beginner-friendly reference: what every resource is, why it exists, and how every piece connects to the next. This README preserves the technical topics, sequence, examples, and original diagrams/screenshots from the referenced materials.

## 🧭 Overview

GitHub Actions workflows need an identity that AWS can authenticate before they can call AWS services. **&lt;span style=&quot;color: #2563eb;&quot;&gt;OIDC&lt;/span&gt;** allows a workflow to obtain **&lt;span style=&quot;color: #16a34a;&quot;&gt;temporary AWS credentials&lt;/span&gt;** without keeping **&lt;span style=&quot;color: #dc2626;&quot;&gt;long-lived AWS access keys&lt;/span&gt;** in GitHub repository or organization secrets.

This guide covers:

* ✅ Why OIDC is preferable to long-lived AWS access keys for CI/CD.
* 🔗 How GitHub's OIDC provider and AWS IAM work together.
* ⚙️ How to configure an IAM OIDC identity provider and an assumable IAM role (**&lt;span style=&quot;color: #2563eb;&quot;&gt;both via the AWS Management Console UI&lt;/span&gt;** and **&lt;span style=&quot;color: #16a34a;&quot;&gt;via the AWS CLI&lt;/span&gt;**).
* 🧪 How to test the connection with AWS CLI.
* ☸️ How to configure EKS access and deploy workloads to Amazon EKS.

## 🏗️ Sample AWS Deployment Workflow

The example architecture uses GitHub Actions to authenticate to AWS, push container images to Amazon ECR, and deploy an application to Amazon EKS.



The diagram is an architectural example. The hands-on validation in this README first uses EC2 listing, then proceeds to EKS deployment.

## 🔑 AWS Authentication Methods for GitHub Actions

A workflow must authenticate to AWS before it can access services such as EC2, ECR, or EKS. The common approaches are described below.

### ❌ 1. &lt;span style=&quot;color: #dc2626;&quot;&gt;Access keys and secret keys&lt;/span&gt;

A traditional workflow can use an IAM user's access key and secret key:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v1
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-west-2
```

⚠️ This method stores **&lt;span style=&quot;color: #dc2626;&quot;&gt;long-lived credentials&lt;/span&gt;** in GitHub Secrets. If those credentials are exposed, an attacker may be able to use them until they are revoked or otherwise invalidated. For that reason, long-lived credentials are **&lt;span style=&quot;color: #dc2626;&quot;&gt;not the preferred method&lt;/span&gt;** for CI/CD authentication.

### 🖥️ 2. &lt;span style=&quot;color: #d97706;&quot;&gt;IAM roles for self-hosted runners&lt;/span&gt;

A self-hosted GitHub Actions runner hosted on AWS can use an IAM role attached to its underlying AWS compute resource (for example, through an instance profile).

📌 **Important distinction:**

* ✔️ This approach applies to self-hosted runners running in an AWS environment.
* ❌ It does not provide the same instance-role mechanism to GitHub-hosted public runners.

IAM roles provide temporary security credentials rather than requiring the workflow to store a permanent access key. Those credentials have a limited lifetime and stop being accepted after expiration.

### ✅ 3. &lt;span style=&quot;color: #16a34a;&quot;&gt;OpenID Connect (a more secure approach)&lt;/span&gt;

With OIDC, a GitHub Actions workflow requests an OIDC token from GitHub and presents it to AWS. AWS validates the token and, if the configured trust conditions match, issues temporary credentials for the IAM role.

🎯 **Key points:**

* 🔒 AWS access keys do not need to be stored as long-lived GitHub Secrets.
* ⏱️ Temporary credentials are issued when the workflow needs them.
* ⌛ The credentials expire.
* 🌐 OIDC can be used with GitHub-hosted and self-hosted runners.

OIDC adds an identity layer to OAuth 2.0. OAuth 2.0 is primarily an authorization framework, while OIDC provides authentication and identity information.

📚 **Useful references:** [OpenID](https://openid.net/) and [OAuth 2.0](https://oauth.net/2/).

The remaining sections focus on GitHub Actions OIDC with AWS.

## 🌍 Chapter 1: The Big Picture — Why Do Any of This?

Before writing a single AWS CLI command, let's understand the problem we are solving. This context is what makes every subsequent step feel logical rather than arbitrary.

### ⚠️ 1.1 &lt;span style=&quot;color: #dc2626;&quot;&gt;The Old Way — Static Secrets (and Why It Hurts)&lt;/span&gt;

In the traditional CI/CD setup, deploying to Kubernetes from GitHub Actions looks like this:

* 🔑 You generate a long-lived kubeconfig file or a Kubernetes ServiceAccount token.
* 📦 You base64-encode it and paste it into GitHub Secrets as `KUBE_CONFIG_B64` or `K8S_TOKEN`.
* 🔄 Every pipeline run decodes and uses this token to talk to your cluster.

This works — but it carries **&lt;span style=&quot;color: #dc2626;&quot;&gt;serious risks&lt;/span&gt;**:

| 🚨 Risk | 💥 What actually goes wrong |
| :--- | :--- |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Token never expires&lt;/span&gt;** | If a static token leaks (e.g. in logs, a public fork, a compromised laptop), it keeps working forever — until someone manually rotates it. |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Broad permissions&lt;/span&gt;** | Kubernetes ServiceAccount tokens are often `cluster-admin` or have wide namespace access, so a leak = full cluster compromise. |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;No audit trail&lt;/span&gt;** | AWS/EKS cannot tell you which pipeline run used a token. It just sees an anonymous bearer token. |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Secret sprawl&lt;/span&gt;** | As team grows, `KUBE_CONFIG_B64`, `K8S_TOKEN`, `K8S_CA_CERT` all sit in GitHub Secrets. Managing rotation is painful. |

### 🛡️ 1.2 &lt;span style=&quot;color: #16a34a;&quot;&gt;The New Way — OIDC Federation (Short-lived, Scoped, Auditable)&lt;/span&gt;

OIDC (OpenID Connect) is a standard identity protocol. GitHub has become an OIDC identity provider, meaning it can issue cryptographically-signed certificates that prove: *'This API call is coming from workflow run #1234, in repo `jaiswaladi246/3-Tier-NodeJS-End-To-End-Project`, on the `main` branch.'*

AWS can verify that certificate independently — no username, no password, no static token involved. The certificate (called a JWT) expires in about **&lt;span style=&quot;color: #16a34a;&quot;&gt;5 minutes&lt;/span&gt;**. Here is why that is better:

* ⏱️ **&lt;span style=&quot;color: #16a34a;&quot;&gt;A leaked token is useless after 5 minutes.&lt;/span&gt;**
* 🔒 **&lt;span style=&quot;color: #16a34a;&quot;&gt;The IAM role trust policy can be scoped to only one specific repo and branch.&lt;/span&gt;** A fork cannot assume the same role.
* 📋 **&lt;span style=&quot;color: #16a34a;&quot;&gt;CloudTrail shows which IAM role was assumed, when, and which job triggered it&lt;/span&gt;** — full audit trail.
* 🚫 **&lt;span style=&quot;color: #16a34a;&quot;&gt;No credentials are stored in GitHub Secrets.&lt;/span&gt;** You only store the IAM role ARN (a public identifier, not a secret).

> 💡 **&lt;span style=&quot;color: #1d4ed8;&quot;&gt;The one-line summary:&lt;/span&gt;**
> GitHub proves its identity cryptographically. AWS verifies the proof and issues 15-minute temporary AWS credentials. Those credentials generate a short-lived kubeconfig. `kubectl` uses that kubeconfig to deploy. **&lt;span style=&quot;color: #16a34a;&quot;&gt;Nothing sensitive is stored anywhere.&lt;/span&gt;**

### 🔗 1.3 How All the Pieces Connect — The Full Chain

Read this chain before diving into any individual step. Every subsequent chapter is one link in this chain:

1. ▶️ GitHub Actions workflow runs and requests an OIDC token from GitHub.
2. 🪪 GitHub issues a signed JWT proving the workflow's identity (repo, branch, ref).
3. 📤 The `aws-actions/configure-aws-credentials` action sends that JWT to AWS STS.
4. 🔍 AWS STS looks up the registered GitHub OIDC provider and verifies the JWT signature.
5. 🛡️ AWS STS checks the IAM role's trust policy: does this token's audience and subject match the allowed values?
6. 🎫 If yes, STS issues temporary AWS credentials (access key + secret + session token, valid 15 min).
7. ⚙️ The `aws eks update-kubeconfig` command uses those credentials to call `eks:DescribeCluster` and build a kubeconfig.
8. 🔑 `kubectl` uses the kubeconfig's exec plugin to get an EKS token, which is verified against the EKS access entry.
9. 🎯 The access entry maps the IAM role to the `AmazonEKSEditPolicy` — scoped only to namespace `project`.
10. 🚀 `kubectl apply` deploys the workloads. Job ends, credentials expire, nothing persists.

## 🧩 &lt;span style=&quot;color: #ea580c;&quot;&gt;GitHub OIDC — The Bootstrap Problem Explained&lt;/span&gt;

**&lt;span style=&quot;color: #dc2626;&quot;&gt;Why kubeconfig, SA tokens & short-lived tokens all fail&lt;/span&gt;**
**&lt;span style=&quot;color: #16a34a;&quot;&gt;The Bootstrap Problem — and why OIDC is the only real solution&lt;/span&gt;**

### 📄 What is kubeconfig?

A **&lt;span style=&quot;color: #2563eb;&quot;&gt;kubeconfig file&lt;/span&gt;** is simply a file that allows you to connect to a Kubernetes cluster.

When you run a command like:

```bash
kubectl get pods
```

`kubectl` doesn't know anything by default. It needs:

* 🎯 **which cluster to connect to**
* 🪪 **who you are**
* 🔐 **how to authenticate**

All of that information comes from the **kubeconfig file**.

So in simple terms:
👉 **&lt;span style=&quot;color: #2563eb;&quot;&gt;kubeconfig is your access file to Kubernetes.&lt;/span&gt;**

### 🛠️ How is kubeconfig created?

Most of the time, you don't create it manually.

It gets generated automatically when you connect to a cluster.

For example, in your case with AWS EKS:

```bash
aws eks update-kubeconfig --name my-cluster
```

When you run this:

* 🌐 AWS gives your cluster endpoint
* 🔐 sets up authentication using IAM
* 💾 stores everything in your kubeconfig file

After this, your system is ready to run `kubectl` commands.

### 📦 What does kubeconfig contain?

The file mainly has three things.

1. 🏢 First, it has **&lt;span style=&quot;color: #2563eb;&quot;&gt;cluster details&lt;/span&gt;** — basically where your Kubernetes cluster is running, including the API server endpoint.
2. 🔑 Second, it has **&lt;span style=&quot;color: #d97706;&quot;&gt;user credentials&lt;/span&gt;** — this defines who you are and how you authenticate (like IAM role, token, or certificates).
3. 🔗 Third, it has something called a **&lt;span style=&quot;color: #7c3aed;&quot;&gt;context&lt;/span&gt;** — which is just a mapping of:
   **cluster + user + namespace**.

This tells Kubernetes:
> 💬 *"Use this user to talk to this cluster in this namespace."*

### ⚡ What can you do with kubeconfig?

Once you have a valid kubeconfig file, you can fully interact with the cluster.

You can:

* 🚀 deploy applications
* 🌐 create services
* 📈 scale workloads
* 🗑️ delete resources

For example:

```bash
kubectl apply -f deployment.yaml
```

This will deploy your app to the cluster using the access defined in kubeconfig.

So yes — **&lt;span style=&quot;color: #dc2626;&quot;&gt;kubeconfig gives you full access to the cluster.&lt;/span&gt;**

### ⚠️ Important note (real-world)

Even though kubeconfig can be used to access the cluster and perform deployments, **&lt;span style=&quot;color: #dc2626;&quot;&gt;sharing it directly is not a good practice.&lt;/span&gt;**

If someone gets your kubeconfig file, they can control your cluster depending on the permissions.

In production setups, instead of sharing kubeconfig:

* 🛡️ we use **&lt;span style=&quot;color: #16a34a;&quot;&gt;IAM roles&lt;/span&gt;**
* 🔐 **&lt;span style=&quot;color: #16a34a;&quot;&gt;OIDC&lt;/span&gt;** (like in your GitHub Actions)
* ⏱️ **&lt;span style=&quot;color: #16a34a;&quot;&gt;short-lived credentials&lt;/span&gt;**

### ❓ The One Question That Explains Everything

Every authentication method for GitHub Actions → EKS comes down to one question:

> 🧭 **&lt;span style=&quot;color: #1d4ed8;&quot;&gt;The Bootstrap Question&lt;/span&gt;**
> **How does GitHub Actions prove to AWS / Kubernetes that it is allowed to deploy?**
>
> * 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Scenario 1 (kubeconfig):&lt;/span&gt;** Store a credential → use it directly
> * 🟠 **&lt;span style=&quot;color: #d97706;&quot;&gt;Scenario 2 (SA long token):&lt;/span&gt;** Store a credential → use it directly
> * 🟡 **&lt;span style=&quot;color: #b45309;&quot;&gt;Scenario 3 (SA short token):&lt;/span&gt;** Store AWS keys → use them to generate a short K8s token
> * 🟢 **&lt;span style=&quot;color: #16a34a;&quot;&gt;GitHub OIDC:&lt;/span&gt;** Prove identity cryptographically → no stored credential needed
>
> ❌ The first three all answer: *'trust me, I have the password'*.
> ✅ OIDC answers: *'verify my identity from a trusted source'*.

### 🔴 &lt;span style=&quot;color: #dc2626;&quot;&gt;Scenario 1: kubeconfig Secret&lt;/span&gt;

**Export `~/.kube/config` → base64 encode → store as `KUBE_CONFIG_B64` in GitHub**

#### ⚙️ How It Works

You export your local kubeconfig — which contains either your personal AWS credentials embedded, or a long-lived Kubernetes token. You base64 encode it and store it as a GitHub Secret. The pipeline decodes it at runtime.

```bash
# Export and encode
cat ~/.kube/config | base64 -w 0
# Store as KUBE_CONFIG_B64 in GitHub Secrets

# In the pipeline
echo "$KUBE_CONFIG_B64" | base64 -d > ~/.kube/config
kubectl apply -f k8s/ -n project
```

#### ❌ What Goes Wrong

| 🚨 Problem | 📋 Detail |
| :--- | :--- |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Token never expires&lt;/span&gt;** | Whatever is inside the kubeconfig — admin cert or SA token — is permanent |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Base64 is not encryption&lt;/span&gt;** | Anyone who can read GitHub Secrets decodes it instantly. It is plain text. |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Scope is often too wide&lt;/span&gt;** | Teams export admin kubeconfig to avoid RBAC debugging — full cluster access |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;No branch restriction&lt;/span&gt;** | Any branch, any workflow in the repo can use `KUBE_CONFIG_B64` |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Zero AWS audit trail&lt;/span&gt;** | `kubectl` calls go directly to K8s API — CloudTrail has no record |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Personal credential&lt;/span&gt;** | Dev leaves team → their kubeconfig is still in production GitHub Secret |

> 🚨 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Leak Scenario&lt;/span&gt;**
> `KUBE_CONFIG_B64` leaks → attacker decodes base64 → gets full `kubectl` access → **&lt;span style=&quot;color: #dc2626;&quot;&gt;permanent&lt;/span&gt;**.
> Remediation: find a new kubeconfig, re-encode, update secret. Meanwhile cluster is compromised.

### 🟠 &lt;span style=&quot;color: #ea580c;&quot;&gt;Scenario 2: ServiceAccount Long-Lived Token&lt;/span&gt;

**Create a dedicated SA → extract its JWT token → store as `K8S_SA_TOKEN`**

#### ⚙️ How It Works

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

#### 🤔 Is This Better Than Scenario 1?

Slightly. The scope is smaller (dedicated SA, not admin). But the mechanism is identical — you still stored a permanent credential in GitHub Secrets.

| 🚨 Problem | 📋 Detail |
| :--- | :--- |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Token is still permanent&lt;/span&gt;** | Kubernetes SA tokens (pre-1.24) have no TTL. They work forever. |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Still stored in GitHub&lt;/span&gt;** | `K8S_SA_TOKEN` is a permanent K8s credential sitting in GitHub Secrets |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Scope creep happens&lt;/span&gt;** | Teams start with `'edit'`. Debugging breaks → add `cluster-admin`. Never revert. |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Still no AWS trail&lt;/span&gt;** | SA token calls go to K8s API server. AWS CloudTrail sees nothing. |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Still no branch restrict&lt;/span&gt;** | `K8S_SA_TOKEN` available to every branch and workflow |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Remediation breaks CI/CD&lt;/span&gt;** | Token leaked → delete SA to revoke → pipeline immediately stops working |

> ⚠️ **&lt;span style=&quot;color: #b45309;&quot;&gt;Scenario 1 vs Scenario 2 — Are They Really Different?&lt;/span&gt;**
> Not fundamentally. Both store a long-lived Kubernetes credential in GitHub Secrets.
> * **Scenario 1** = admin/personal kubeconfig → **&lt;span style=&quot;color: #dc2626;&quot;&gt;wider blast radius&lt;/span&gt;**
> * **Scenario 2** = dedicated SA token → **&lt;span style=&quot;color: #d97706;&quot;&gt;smaller blast radius&lt;/span&gt;**
>
> Same mechanism. Same root problem. Different privilege scope.
> The real problem — **&lt;span style=&quot;color: #dc2626;&quot;&gt;a permanent stored credential&lt;/span&gt;** — is identical in both.

### 🔵 &lt;span style=&quot;color: #2563eb;&quot;&gt;Scenario 3: ServiceAccount Short-Lived Token (TokenRequest API)&lt;/span&gt;

**Generate a 1hr K8s token at runtime — but you still need AWS keys to bootstrap**

#### ⚙️ How It Works

Kubernetes 1.20+ introduced the TokenRequest API. Instead of storing a permanent SA token, you generate a time-limited token (1hr) at the start of each pipeline run using `'kubectl create token'`. The K8s token itself is short-lived. This sounds like the solution — until you ask the bootstrap question.

#### 🚧 The Bootstrap Problem

To call `'kubectl create token'` from GitHub Actions, you first need to authenticate to EKS. You cannot call `kubectl` against EKS without a valid kubeconfig. To get that kubeconfig, you must run:

```bash
aws eks update-kubeconfig --name my-cluster --region ap-south-1
```

And to run that AWS CLI command, you need AWS credentials. Which means you need to store:

> 🚨 **&lt;span style=&quot;color: #dc2626;&quot;&gt;What You Must Store in GitHub Secrets for Scenario 3&lt;/span&gt;**
> * `AWS_ACCESS_KEY_ID` ← **&lt;span style=&quot;color: #dc2626;&quot;&gt;long-lived AWS credential&lt;/span&gt;**
> * `AWS_SECRET_ACCESS_KEY` ← **&lt;span style=&quot;color: #dc2626;&quot;&gt;long-lived AWS credential&lt;/span&gt;**
>
> These are permanent. They never expire unless you manually rotate them.
> You solved the Kubernetes token expiry problem.
> **&lt;span style=&quot;color: #dc2626;&quot;&gt;You replaced it with a permanent AWS credential problem.&lt;/span&gt;**

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

You went through 5 steps and you still have `AWS_ACCESS_KEY_ID` in GitHub Secrets. The K8s token is short-lived — **&lt;span style=&quot;color: #dc2626;&quot;&gt;the bootstrap credential is not.&lt;/span&gt;**

#### ✅ What Scenario 3 Gets Right

* 🟢 The Kubernetes token expires in 1hr — if intercepted, limited window
* 🟢 No permanent SA token stored in GitHub Secrets
* 🟢 Slightly better audit than Scenarios 1 & 2 (AWS CloudTrail sees the `update-kubeconfig` call)

#### ❌ What Scenario 3 Still Gets Wrong

| 🚨 Remaining Problem | 💥 Why It Matters |
| :--- | :--- |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;AWS keys stored permanently&lt;/span&gt;** | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` in GitHub — these never expire |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Worse blast radius than Scenarios 1&2&lt;/span&gt;** | AWS keys can access your ENTIRE AWS account — not just EKS |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Still no branch restriction&lt;/span&gt;** | Any branch can use the AWS keys to bootstrap and generate a token |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Key rotation breaks pipelines&lt;/span&gt;** | Rotate AWS keys → pipelines break → update 2 secrets under pressure |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Extra complexity, same risk&lt;/span&gt;** | 5 steps instead of 1, but the stored credential problem is unchanged |

> 🔍 **&lt;span style=&quot;color: #1d4ed8;&quot;&gt;The Bootstrap Problem — Visualised&lt;/span&gt;**
> * **Scenario 1:** GitHub → `<span style="color: #dc2626;">[KUBE_CONFIG_B64]</span>` → `kubectl` → EKS
> * **Scenario 2:** GitHub → `<span style="color: #dc2626;">[K8S_SA_TOKEN]</span>` → `kubectl` → EKS
> * **Scenario 3:** GitHub → `<span style="color: #dc2626;">[AWS_ACCESS_KEY + SECRET_KEY]</span>` → `aws eks update-kubeconfig` → `kubectl create token (1hr)` → `kubectl` → EKS
>
> All three have a **`[ ]`** — **&lt;span style=&quot;color: #dc2626;&quot;&gt;something permanent stored in GitHub.&lt;/span&gt;**
> **&lt;span style=&quot;color: #1d4ed8;&quot;&gt;You cannot escape the bootstrap problem without OIDC.&lt;/span&gt;**

### 🟢 &lt;span style=&quot;color: #16a34a;&quot;&gt;GitHub OIDC — How It Breaks the Bootstrap Problem&lt;/span&gt;

OIDC removes the `[ ]` entirely. GitHub proves its identity to AWS using a cryptographically signed JWT that it generates per run. **&lt;span style=&quot;color: #16a34a;&quot;&gt;There is nothing to store. Nothing to rotate. Nothing to leak.&lt;/span&gt;**

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

📄 **GitHub Actions YAML:**

```yaml
- name: Configure AWS credentials (no keys needed)
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
    aws-region: ap-south-1

- name: Update kubeconfig
  run: aws eks update-kubeconfig --name my-cluster --region ap-south-1
```

✅ `AWS_ROLE_TO_ASSUME` is a **&lt;span style=&quot;color: #16a34a;&quot;&gt;role ARN — a public identifier&lt;/span&gt;**. It cannot authenticate anything on its own. It is not a secret.

### 📊 All 3 Scenarios vs GitHub OIDC — Full Comparison

| 📋 Feature | 🔴 Scenario 1 kubeconfig | 🟠 Scenario 2 SA Long Token | 🔵 Scenario 3 SA Short Token |
| :--- | :--- | :--- | :--- |
| **Stored in GitHub?** | &lt;span style=&quot;color: #dc2626;&quot;&gt;Yes — kubeconfig&lt;/span&gt; | &lt;span style=&quot;color: #dc2626;&quot;&gt;Yes — SA token&lt;/span&gt; | &lt;span style=&quot;color: #16a34a;&quot;&gt;Yes — AWS keys&lt;/span&gt; |
| **What's stored** | &lt;span style=&quot;color: #dc2626;&quot;&gt;Admin/SA token (K8s)&lt;/span&gt; | &lt;span style=&quot;color: #dc2626;&quot;&gt;SA JWT token (K8s)&lt;/span&gt; | &lt;span style=&quot;color: #16a34a;&quot;&gt;`AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`&lt;/span&gt; |
| **Credential expires?** | &lt;span style=&quot;color: #dc2626;&quot;&gt;Never&lt;/span&gt; | &lt;span style=&quot;color: #dc2626;&quot;&gt;Never&lt;/span&gt; | &lt;span style=&quot;color: #16a34a;&quot;&gt;Never (AWS keys don't)&lt;/span&gt; |
| **K8s token expires?** | &lt;span style=&quot;color: #dc2626;&quot;&gt;Never&lt;/span&gt; | &lt;span style=&quot;color: #dc2626;&quot;&gt;Never&lt;/span&gt; | &lt;span style=&quot;color: #16a34a;&quot;&gt;Yes — 1hr&lt;/span&gt; |
| **Bootstrap problem?** | &lt;span style=&quot;color: #dc2626;&quot;&gt;No — direct&lt;/span&gt; | &lt;span style=&quot;color: #dc2626;&quot;&gt;No — direct&lt;/span&gt; | &lt;span style=&quot;color: #16a34a;&quot;&gt;Yes — needs AWS keys first&lt;/span&gt; |
| **AWS audit trail?** | &lt;span style=&quot;color: #dc2626;&quot;&gt;None&lt;/span&gt; | &lt;span style=&quot;color: #dc2626;&quot;&gt;None&lt;/span&gt; | &lt;span style=&quot;color: #16a34a;&quot;&gt;Yes — CloudTrail&lt;/span&gt; |
| **Branch restriction?** | &lt;span style=&quot;color: #dc2626;&quot;&gt;None&lt;/span&gt; | &lt;span style=&quot;color: #dc2626;&quot;&gt;None&lt;/span&gt; | &lt;span style=&quot;color: #16a34a;&quot;&gt;None&lt;/span&gt; |
| **Leak impact** | &lt;span style=&quot;color: #dc2626;&quot;&gt;Permanent cluster&lt;/span&gt; | &lt;span style=&quot;color: #dc2626;&quot;&gt;Permanent cluster&lt;/span&gt; | &lt;span style=&quot;color: #16a34a;&quot;&gt;Permanent AWS account&lt;/span&gt; |
| **Compliance** | ❌ &lt;span style=&quot;color: #dc2626;&quot;&gt;Fails&lt;/span&gt; | ❌ &lt;span style=&quot;color: #dc2626;&quot;&gt;Fails&lt;/span&gt; | ⚠️ &lt;span style=&quot;color: #16a34a;&quot;&gt;Partial&lt;/span&gt; |

> 🏆 **&lt;span style=&quot;color: #15803d;&quot;&gt;The One-Line Summary&lt;/span&gt;**
> * 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;Scenario 1&lt;/span&gt;** — You store a permanent Kubernetes credential.
> * 🟠 **&lt;span style=&quot;color: #d97706;&quot;&gt;Scenario 2&lt;/span&gt;** — You store a permanent Kubernetes credential (smaller scope).
> * 🔵 **&lt;span style=&quot;color: #2563eb;&quot;&gt;Scenario 3&lt;/span&gt;** — You solve K8s token expiry but store permanent AWS keys instead. The bootstrap problem moves. It doesn't disappear.
> * 🟢 **&lt;span style=&quot;color: #16a34a;&quot;&gt;GitHub OIDC&lt;/span&gt;** — **&lt;span style=&quot;color: #15803d;&quot;&gt;No stored credential. Identity proved at runtime. Bootstrap problem solved.&lt;/span&gt;**

## ✅ Chapter 2: Preconditions — What Must Be True Before You Start

Skipping preconditions is the number-one cause of confusing errors mid-setup. This chapter explains each check and why it matters.

### 👤 2.1 AWS CLI Authentication

Every AWS CLI command in this guide runs as whichever IAM principal is currently authenticated. If you are using the wrong account or an under-privileged role, commands will fail with cryptic `<span style="color: #dc2626;">AccessDenied</span>` errors.

```bash
# Verify who you are logged in as
aws sts get-caller-identity

# Expected output:
{
  "UserId": "AIDAXXXXXXXXXXXXXXX",
  "Account": "585593375370",
  "Arn": "arn:aws:iam::585593375370:user/your-admin-user"
}
```

> ⚠️ **&lt;span style=&quot;color: #b45309;&quot;&gt;Required permissions for this guide:&lt;/span&gt;**
> Your IAM principal must be able to: create/manage OIDC providers (`iam:CreateOpenIDConnectProvider`), create IAM roles and policies (`iam:CreateRole`, `iam:AttachRolePolicy`), and manage EKS access entries (`eks:CreateAccessEntry`, `eks:AssociateAccessPolicy`, `eks:UpdateClusterConfig`).

### 🟢 2.2 EKS Cluster Must Be ACTIVE

Access entries (the new auth system we will use) only work when the cluster is fully running. If the cluster is `<span style="color: #d97706;">CREATING</span>` or `<span style="color: #d97706;">UPDATING</span>`, commands will fail.

```bash
aws eks describe-cluster \
  --name my-cluster \
  --region ap-south-1 \
  --query "{status:cluster.status,authMode:cluster.accessConfig.authenticationMode}" \
  --output json

# Expected output:
{
  "status": "ACTIVE",
  "authMode": "API_AND_CONFIG_MAP"
}
```

### 🔐 2.3 Authentication Mode Must Support Access Entries

EKS originally used only the `aws-auth` ConfigMap to control who could access a cluster. This was error-prone — one bad YAML edit and you could lock yourself out. AWS introduced Access Entries API as a safer alternative.

The catch: access entries only work if the cluster's authentication mode is `<span style="color: #16a34a;">API</span>` or `<span style="color: #16a34a;">API_AND_CONFIG_MAP</span>`. The legacy-only `<span style="color: #dc2626;">CONFIG_MAP</span>` mode does not support access entries at all.

| 🔑 Auth Mode | ❓ Supports Access Entries? | 🛠️ What to Do |
| :--- | :--- | :--- |
| `CONFIG_MAP` | ❌ **&lt;span style=&quot;color: #dc2626;&quot;&gt;No&lt;/span&gt;** | Must upgrade — see Section 6.1 |
| `API` | ✅ **&lt;span style=&quot;color: #16a34a;&quot;&gt;Yes&lt;/span&gt;** | Ready to use as-is |
| `API_AND_CONFIG_MAP` | ✅ **&lt;span style=&quot;color: #16a34a;&quot;&gt;Yes&lt;/span&gt;** | Already done — no action needed |

## ⚙️ Configure GitHub Actions OIDC with AWS IAM

The AWS-side identity provider and role are configured once. Individual workflows then assume that role when they run.

## 🏛️ Step 1 / Chapter 3: Registering GitHub as a Trusted Identity Provider in AWS IAM

This is the foundation of the entire trust chain. Without this step, AWS has no way to verify any token GitHub sends.

### 💡 3.1 What Is an OIDC Provider (in Plain Language)?

Think of it like this: you want to let people log into your building using their company ID badge. But your security desk does not know that company. You need to go to that company's HR department, verify that their badges are legitimate, and add them to your approved-vendor list.

In our case:

* 🏢 **&lt;span style=&quot;color: #2563eb;&quot;&gt;Your AWS account&lt;/span&gt;** = the building with a security desk
* 🪪 **&lt;span style=&quot;color: #7c3aed;&quot;&gt;GitHub&lt;/span&gt;** = the company issuing ID badges (JWTs)
* ✅ **&lt;span style=&quot;color: #16a34a;&quot;&gt;Creating the OIDC provider&lt;/span&gt;** = adding GitHub to your approved-vendor list in AWS IAM

Specifically, AWS needs three pieces of information to trust GitHub tokens:

11. 🌐 **&lt;span style=&quot;color: #2563eb;&quot;&gt;The provider URL&lt;/span&gt;** — so AWS knows which endpoint to check the JWT signature against.
12. 🎯 **&lt;span style=&quot;color: #7c3aed;&quot;&gt;The audience (client ID)&lt;/span&gt;** — so AWS knows these tokens were meant for AWS STS, not some other service.
13. 🔒 **&lt;span style=&quot;color: #16a34a;&quot;&gt;The TLS thumbprint&lt;/span&gt;** — a fingerprint of GitHub's TLS certificate chain, so AWS can verify it is really talking to GitHub, not an impersonator.

### 🖥️ &lt;span style=&quot;color: #2563eb;&quot;&gt;Option A: AWS Management Console UI Procedure&lt;/span&gt;

GitHub is the OIDC identity provider in this integration. Add GitHub's provider information to AWS IAM.

1. 🌐 Open the **AWS Management Console**.
2. 🧭 Navigate to **IAM → Identity providers**.
3. ➕ Choose **Add provider**.
4. 📝 Enter the following values:

| ⚙️ Setting | 📌 Value |
| :--- | :--- |
| **Provider type** | &lt;span style=&quot;color: #2563eb;&quot;&gt;OpenID Connect&lt;/span&gt; |
| **Provider URL** | `https://token.actions.githubusercontent.com` |
| **Audience** | `sts.amazonaws.com` |





This registers GitHub's OIDC issuer with AWS and establishes the provider side of the trust relationship.

### 💻 &lt;span style=&quot;color: #16a34a;&quot;&gt;Option B: Alternative AWS CLI Procedure (3.2 Creating the OIDC Provider)&lt;/span&gt;

```bash
# Step 1: Check if the provider already exists
aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn,'token.actions.githubusercontent.com')].Arn" \
  --output text

# If it exists and you need to recreate it, delete first:
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::585593375370:oidc-provider/token.actions.githubusercontent.com

# Create the provider:
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

> 💡 **&lt;span style=&quot;color: #1d4ed8;&quot;&gt;Why sts.amazonaws.com as the client ID?&lt;/span&gt;**
> When GitHub issues the JWT, it sets an `'audience'` field in the token. The official `aws-actions/configure-aws-credentials` action always sets this to `sts.amazonaws.com`. Your OIDC provider must match this value, otherwise AWS will reject the token with an **&lt;span style=&quot;color: #dc2626;&quot;&gt;'aud claim mismatch'&lt;/span&gt;** error.

## 🛡️ Step 2 / Chapters 4 & 5: Creating the Web Identity IAM Role, Trust Policy, and Permission Policy

The IAM role is the identity that GitHub Actions will 'become' inside AWS. The trust policy on that role is the security gate that controls exactly who is allowed to become it.

### 🪪 4.1 What Is an IAM Role?

An IAM role is like a job title in an organization. The job title (role) has certain permissions attached (what can be done). Any person (or system) who qualifies can temporarily assume that job title.

Unlike an IAM user, a role has **&lt;span style=&quot;color: #16a34a;&quot;&gt;no permanent password or access key&lt;/span&gt;**. You assume a role temporarily and get **&lt;span style=&quot;color: #16a34a;&quot;&gt;short-lived credentials&lt;/span&gt;** — they automatically expire. That is exactly what we want for CI/CD.

### 📜 4.2 What Is a Trust Policy?

Every IAM role has two types of policies:

* 🔐 **&lt;span style=&quot;color: #2563eb;&quot;&gt;Trust policy&lt;/span&gt;** (who can assume this role) — this is what we are writing now.
* 🛠️ **&lt;span style=&quot;color: #7c3aed;&quot;&gt;Permission policy&lt;/span&gt;** (what the role can do once assumed) — this is what we attach in Chapter 5.

The trust policy is where the OIDC magic happens. It says: *'I will only allow `AssumeRoleWithWebIdentity` if the web identity token comes from GitHub, has the right audience, and matches the `sub` claim for our specific repo and branch.'*

### 🖥️ &lt;span style=&quot;color: #2563eb;&quot;&gt;Option A: AWS Management Console UI Procedure&lt;/span&gt;

After creating the identity provider, assign an IAM role to it.

1. 📂 Open the newly created identity provider.
2. ➕ Choose **Assign role**.
3. 🆕 Select the option to **create a new role**.
4. 🌐 Choose **Web identity** as the trusted entity type.





A web identity role allows an identity outside AWS to use an OIDC token to request role credentials.



Enter the GitHub organization information in the role setup.



⚠️ The trust configuration determines which GitHub identities are permitted to assume the role. **&lt;span style=&quot;color: #dc2626;&quot;&gt;Restrict it to the intended organization/repository/branch&lt;/span&gt;** or other supported subject conditions; do not make the role assumable by unrelated repositories.

Next, attach the IAM permissions required by the workflow.



The source walkthrough uses administrator permissions for its demonstration. For a real environment, **&lt;span style=&quot;color: #16a34a;&quot;&gt;grant only the permissions required by the workflow&lt;/span&gt;**.

Give the role a name, for example:

```text
github-actions-workflow-role
```

#### 🔍 Get the identifiers needed for the trust policy

The AWS trust policy must match GitHub's OIDC `sub` (subject) claim.

#### 🏷️ Subject Claim Formats

**1. 🔒 &lt;span style=&quot;color: #16a34a;&quot;&gt;Immutable subject (repositories created after July 15, 2026):&lt;/span&gt;**
GitHub repositories created after **July 15, 2026** use immutable subject claims by default. The new subject contains both the owner ID and repository ID:

```text
repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:ref:refs/heads/main
```

**2. 📄 &lt;span style=&quot;color: #2563eb;&quot;&gt;Traditional subject (older repositories):&lt;/span&gt;**

```text
repo:OWNER/REPOSITORY:ref:refs/heads/main
```

#### 🆔 Retrieve Owner ID and Repository ID



Modify the role by updating the repository ID and owner ID.



Review the role configuration and create it. This role defines what the GitHub Actions workflow is allowed to do in the AWS account.

### 💻 &lt;span style=&quot;color: #16a34a;&quot;&gt;Option B: Alternative AWS CLI Procedure — IAM Role and Trust Policy (Chapter 4)&lt;/span&gt;

#### 📝 4.3 Creating the Trust Policy File

On Windows PowerShell, file encoding matters. The AWS CLI will reject a UTF-16 BOM-encoded file with a confusing JSON parse error. Always write the file with **&lt;span style=&quot;color: #d97706;&quot;&gt;ASCII encoding&lt;/span&gt;**:

```powershell
# Windows PowerShell — write as ASCII to avoid BOM issues
'{ ... full JSON ... }' | Out-File -FilePath .\github-oidc-trust.json -Encoding ascii
```

```json
# The complete trust policy:
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::585593375370:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:jaiswaladi246/3-Tier-NodeJS-End-To-End-Project:ref:refs/heads/main"
      }
    }
  }]
}
```

#### 🔬 4.4 Dissecting Every Field in the Trust Policy

Every field in this JSON is there for a reason. Here is what each one does:

| 🧩 Field | 🎯 Purpose and Why It Matters |
| :--- | :--- |
| ✅ `Effect: Allow` | Grants permission. Without this, the statement would do nothing. Note: a role with NO trust policy cannot be assumed by anyone — it is locked by default. |
| 🌐 `Principal: Federated` | Identifies who is allowed to assume this role. `'Federated'` means an external identity provider (GitHub in this case). Using the OIDC provider ARN here means only GitHub-issued tokens are considered — not IAM users, not EC2 instances. |
| 🔄 `Action: AssumeRoleWithWebIdentity` | This is the specific STS action that exchanges a web identity token (JWT) for temporary AWS credentials. It is different from `AssumeRole` (used by IAM users/roles) because it is designed for external identity tokens. |
| 🎯 `Condition: aud = sts.amazonaws.com` | Verifies the token's audience field matches exactly. This prevents a JWT issued for some other AWS service or non-AWS service from being misused to assume this role. It is a double-check that the token was intended for STS. |
| 🔒 `Condition: sub = repo:...main` | **&lt;span style=&quot;color: #16a34a;&quot;&gt;This is the most important security control.&lt;/span&gt;** The `sub` (subject) claim in GitHub's JWT encodes the exact repo, ref type, and branch. Using `StringLike` with this value means only a workflow running on the `main` branch of your specific repository can assume this role. A fork, a PR branch, or any other repo is rejected. |

#### 🛠️ 4.5 Creating the IAM Role

```bash
# Create the role using the trust policy file
aws iam create-role \
  --role-name GitHubActionsEKSDeployRole \
  --assume-role-policy-document file://github-oidc-trust.json

# Verify it was created correctly
aws iam get-role --role-name GitHubActionsEKSDeployRole
```

> 💡 **&lt;span style=&quot;color: #b45309;&quot;&gt;Why is the role called GitHubActionsEKSDeployRole?&lt;/span&gt;**
> The name is descriptive by design. Anyone reading your IAM console immediately understands: this role is for GitHub Actions, and it is specifically for EKS deployments. Good naming hygiene is a security practice — it helps you audit roles and spot unexpected ones.

### 💻 &lt;span style=&quot;color: #16a34a;&quot;&gt;Option B (Continued): Alternative AWS CLI Procedure — The IAM Permission Policy (Chapter 5)&lt;/span&gt;

Having a role (identity) is not enough. You also need to define what that role is allowed to do inside AWS. That is what the permission policy controls. This is the **&lt;span style=&quot;color: #16a34a;&quot;&gt;principle of least privilege&lt;/span&gt;** in action.

#### ❓ 5.1 Why Do We Need eks:DescribeCluster?

When your GitHub Actions workflow runs this command:

```bash
aws eks update-kubeconfig --name my-cluster --region ap-south-1
```

Behind the scenes, the AWS CLI calls the EKS API's `DescribeCluster` endpoint. This returns:

* 🌐 The cluster API server endpoint (e.g. `https://ABCDEF.gr7.ap-south-1.eks.amazonaws.com`)
* 🔐 The cluster's certificate authority (CA) data
* 🏷️ The cluster name and ARN

The CLI uses this data to build the kubeconfig file. Without `eks:DescribeCluster` permission, this call is rejected and `kubectl` cannot be configured at all.

#### 🛡️ 5.2 Why Only eks:DescribeCluster — Not eks:* or AdministratorAccess?

This is least-privilege principle. The deployment role should be able to do **&lt;span style=&quot;color: #16a34a;&quot;&gt;exactly one thing&lt;/span&gt;** in the IAM/EKS control plane: read cluster metadata. It should **&lt;span style=&quot;color: #dc2626;&quot;&gt;not&lt;/span&gt;** be able to:

* ❌ Create or delete EKS clusters
* ❌ Modify EKS cluster configuration
* ❌ Create IAM users or roles
* ❌ Access S3, RDS, or any other service

The actual Kubernetes-level permissions (what `kubectl` can do) are handled separately by EKS access entries in Chapter 6, not by IAM policies. This **&lt;span style=&quot;color: #2563eb;&quot;&gt;two-layer design&lt;/span&gt;** means even if the IAM role is compromised, the damage is limited.

#### 📎 5.3 Creating and Attaching the Policy

```json
# Create the minimal policy file
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "EKSDescribeCluster",
    "Effect": "Allow",
    "Action": ["eks:DescribeCluster"],
    "Resource": "arn:aws:eks:ap-south-1:585593375370:cluster/my-cluster"
  }]
}
```

```bash
# Create the IAM policy in AWS
aws iam create-policy \
  --policy-name GitHubActionsEKSDescribeClusterPolicy \
  --policy-document file://eks-describe-cluster-policy.json

# Attach the policy to the role
aws iam attach-role-policy \
  --role-name GitHubActionsEKSDeployRole \
  --policy-arn arn:aws:iam::585593375370:policy/GitHubActionsEKSDescribeClusterPolicy

# Verify attachment
aws iam list-attached-role-policies --role-name GitHubActionsEKSDeployRole
```

> 💡 **&lt;span style=&quot;color: #1d4ed8;&quot;&gt;IAM Policy vs Trust Policy — the key distinction:&lt;/span&gt;**
> The **&lt;span style=&quot;color: #2563eb;&quot;&gt;trust policy&lt;/span&gt;** answers **WHO** can assume this role. The **&lt;span style=&quot;color: #7c3aed;&quot;&gt;permission policy&lt;/span&gt;** answers **WHAT** this role can do after being assumed. Both are required. A role with a trust policy but no permission policy can be assumed but cannot do anything useful.

## 🔑 Step 3 / Chapter 7.1: Adding the IAM Role ARN to GitHub Secrets

The workflow needs the IAM role ARN so that the credentials action can request it.

### 🖥️ &lt;span style=&quot;color: #2563eb;&quot;&gt;GitHub UI Procedure&lt;/span&gt;

The ARN can be stored as either:

* 🏢 **&lt;span style=&quot;color: #2563eb;&quot;&gt;Organization secret:&lt;/span&gt;** available to repositories permitted by the organization's secret policy.
* 📁 **&lt;span style=&quot;color: #16a34a;&quot;&gt;Repository secret:&lt;/span&gt;** available only to the selected repository.

For the example, the article uses an organization-level secret.

1. ⚙️ Open the GitHub organization or repository **Settings**.
2. 🔐 Go to **Secrets and variables → Actions**.
3. ➕ Create a secret with this name:

```text
AWS_OIDC_ROLE
```

4. 📌 Set its value to the ARN of the IAM role created in Step 2.





✅ The secret contains the **&lt;span style=&quot;color: #16a34a;&quot;&gt;role ARN&lt;/span&gt;**, not an AWS access key or secret key.

### 🧹 7.1 What Secret to Store (and What to Remove)

You only need **&lt;span style=&quot;color: #16a34a;&quot;&gt;one&lt;/span&gt;** GitHub repository secret now:

| 🟢 Secret Name | 📌 Value |
| :--- | :--- |
| ✅ **&lt;span style=&quot;color: #15803d;&quot;&gt;`AWS_ROLE_TO_ASSUME`&lt;/span&gt;** | `<span style="color: #15803d;">arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole</span>` |

These secrets can now be **&lt;span style=&quot;color: #dc2626;&quot;&gt;deleted&lt;/span&gt;** because they are no longer used:

| 🗑️ Secret to Remove | 💡 Why It Is No Longer Needed |
| :--- | :--- |
| ❌ **&lt;span style=&quot;color: #dc2626;&quot;&gt;`KUBE_CONFIG_B64`&lt;/span&gt;** | Was a static kubeconfig. Now generated fresh on every run via `aws eks update-kubeconfig`. |
| ❌ **&lt;span style=&quot;color: #dc2626;&quot;&gt;`K8S_SERVER`&lt;/span&gt;** | The cluster endpoint is now read dynamically via `eks:DescribeCluster`. |
| ❌ **&lt;span style=&quot;color: #dc2626;&quot;&gt;`K8S_CA_CERT`&lt;/span&gt;** | The cluster CA cert is read dynamically from EKS, not stored as a secret. |
| ❌ **&lt;span style=&quot;color: #dc2626;&quot;&gt;`K8S_TOKEN`&lt;/span&gt;** | Was a static ServiceAccount token. Now replaced by 15-minute OIDC-derived tokens. |

## 🧪 Step 4: Test the OIDC Connection to AWS

Before configuring EKS, validate that GitHub Actions can assume the AWS role and call an AWS API.

The credentials action is `aws-actions/configure-aws-credentials`. It uses the GitHub OIDC token and assumes the role whose ARN is stored in `AWS_OIDC_ROLE`.

The core step is:

```yaml
- name: Configure AWS credentials using OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_OIDC_ROLE }}
    aws-region: us-west-2
```

Create the workflow file `.github/workflows/ec2-list.yaml` in your repository:

```yaml
name: List EC2 Instances

on:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  list-ec2:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Configure AWS credentials using OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_OIDC_ROLE }}
          aws-region: us-west-2

      - name: List EC2 Instances
        run: |
          aws ec2 describe-instances \
            --query "Reservations[*].Instances[*].InstanceId" \
            --output table
```

Commit and push the workflow to the `main` branch to trigger it.

If the provider, role trust relationship, GitHub secret, and IAM permissions are configured correctly, the workflow should authenticate and print the EC2 instance IDs.



> 🚦 **&lt;span style=&quot;color: #b45309;&quot;&gt;Validation checkpoint:&lt;/span&gt;** Do not proceed to EKS until this workflow successfully assumes the role and runs the EC2 API command. If the AWS CLI command returns an authorization error, verify that the role has the required EC2 read permission.

## ☸️ Step 5 / Chapter 6: Enable GitHub Actions Access to Amazon EKS via OIDC (EKS Access Entries — Connecting IAM to Kubernetes RBAC)

You now have an IAM role that can be assumed by GitHub Actions and can call `eks:DescribeCluster`. But that role still cannot talk to the Kubernetes API inside the cluster. **&lt;span style=&quot;color: #2563eb;&quot;&gt;EKS access entries bridge this gap.&lt;/span&gt;**

EKS access involves **&lt;span style=&quot;color: #7c3aed;&quot;&gt;two separate authorization layers&lt;/span&gt;**:

1. ☁️ **&lt;span style=&quot;color: #2563eb;&quot;&gt;AWS IAM:&lt;/span&gt;** the GitHub workflow must assume the IAM role and have permission to interact with the EKS cluster.
2. ☸️ **&lt;span style=&quot;color: #16a34a;&quot;&gt;Kubernetes/EKS cluster access:&lt;/span&gt;** the IAM role must be granted access to Kubernetes resources through the cluster's access configuration and associated access policy.

### ❓ 6.1 What Problem Do Access Entries Solve?

Kubernetes has its own auth system (RBAC — Role-Based Access Control) that is completely separate from AWS IAM. By default, an IAM role — even with full `AdministratorAccess` — cannot `kubectl apply` to a cluster.

Historically, the bridge was a ConfigMap called `aws-auth` in the `kube-system` namespace. You had to manually add entries like:

```yaml
# Old way (aws-auth ConfigMap) — error-prone YAML editing
mapRoles: |
  - rolearn: arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole
    username: github-actions
    groups:
      - system:masters # ← dangerously broad
```

⚠️ **&lt;span style=&quot;color: #dc2626;&quot;&gt;Problems with the old way:&lt;/span&gt;**

* ❌ One YAML indentation error could corrupt the ConfigMap and lock everyone out of the cluster.
* ❌ No easy CLI — you had to `kubectl edit` or `kubectl apply` the ConfigMap manually.
* ❌ Hard to audit — who added what entry and when?
* ❌ `system:masters` gives full cluster admin — no namespace scoping.

✅ **&lt;span style=&quot;color: #16a34a;&quot;&gt;Access entries solve all of this.&lt;/span&gt;** They are managed through the AWS API (not YAML), auditable in CloudTrail, and support namespace-scoped policies.

### ⬆️ 6.2 Upgrading Authentication Mode (if needed)

```bash
# Check current mode
aws eks describe-cluster \
  --name my-cluster --region ap-south-1 \
  --query "cluster.accessConfig.authenticationMode" --output text

# If it returns CONFIG_MAP, upgrade it:
aws eks update-cluster-config \
  --name my-cluster --region ap-south-1 \
  --access-config authenticationMode=API_AND_CONFIG_MAP

# Wait for cluster to finish updating:
aws eks describe-cluster \
  --name my-cluster --region ap-south-1 \
  --query "cluster.status" --output text
# Wait until it shows: ACTIVE
```

> ⚠️ **&lt;span style=&quot;color: #b45309;&quot;&gt;API_AND_CONFIG_MAP vs API:&lt;/span&gt;**
> We use `API_AND_CONFIG_MAP` (not just `API`) because it is the **&lt;span style=&quot;color: #16a34a;&quot;&gt;safe migration path&lt;/span&gt;**. It keeps existing `aws-auth` entries working while also supporting access entries. Switching directly to `API`-only would break any existing `aws-auth` mappings. Use `API_AND_CONFIG_MAP` during migration, then `API` once you have fully moved off ConfigMap.

### 🪪 6.3 Creating the Access Entry

An access entry simply registers an IAM principal (our role) as a known identity in the EKS cluster. Think of it as creating a 'known user' record in Kubernetes for our IAM role.

First, make sure the AWS CLI is up to date and supports the EKS access-entry commands.

#### 💻 &lt;span style=&quot;color: #2563eb;&quot;&gt;Standard Access Entry with Kubernetes Groups and Username:&lt;/span&gt;

```bash
aws eks create-access-entry \
    --cluster-name <your-cluster-name> \
    --principal-arn <your-role-arn-here> \
    --kubernetes-groups github-runners \
    --type STANDARD \
    --username github-actions-oidc
```

Replace the placeholders with your EKS cluster name and IAM role ARN.

#### 💻 &lt;span style=&quot;color: #16a34a;&quot;&gt;Alternative AWS CLI Command (Principal ARN Registration & Verification):&lt;/span&gt;

```bash
# Create the access entry
aws eks create-access-entry \
  --cluster-name my-cluster \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole

# Verify it exists
aws eks describe-access-entry \
  --cluster-name my-cluster \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole
```

### 🎯 6.4 Associating an Access Policy (Cluster-Scoped vs Namespace-Scoped)

Creating the access entry only registers the identity. You still need to grant it Kubernetes RBAC permissions. AWS provides managed access policies that map to Kubernetes roles:

| 📜 AWS Managed Policy | ☸️ Kubernetes Equivalent | 🔐 What It Can Do |
| :--- | :--- | :--- |
| 🔴 **&lt;span style=&quot;color: #dc2626;&quot;&gt;`AmazonEKSClusterAdminPolicy`&lt;/span&gt;** | `cluster-admin` | Full cluster access — **&lt;span style=&quot;color: #dc2626;&quot;&gt;avoid for CI/CD&lt;/span&gt;** |
| 🟠 `AmazonEKSAdminPolicy` | `admin` (namespace) | Full namespace admin |
| 🟢 **&lt;span style=&quot;color: #16a34a;&quot;&gt;`AmazonEKSEditPolicy`&lt;/span&gt;** | `edit` | **&lt;span style=&quot;color: #16a34a;&quot;&gt;Create/update/delete most resources (no RBAC)&lt;/span&gt;** |
| 🔵 `AmazonEKSViewPolicy` | `view` | Read-only access to resources |

List the EKS access policies:

```bash
aws eks list-access-policies --output table
```

#### 📘 &lt;span style=&quot;color: #2563eb;&quot;&gt;Example 1: Cluster-Scoped View Policy (from DevOpsCube walkthrough)&lt;/span&gt;

The source walkthrough discusses using an EKS administrative policy for cluster management, while the command shown in the article associates the view policy. The exact command shown there is reproduced below:

```bash
aws eks associate-access-policy \
  --cluster-name <your-cluster-name> \
  --principal-arn <your-role-arn-here> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=cluster
```

⚠️ **&lt;span style=&quot;color: #dc2626;&quot;&gt;Important:&lt;/span&gt;** `AmazonEKSViewPolicy` is a view/read-oriented policy, not an administrative deployment policy. For a deployment workflow, choose an access policy and scope that provide the minimum permissions the workflow needs. **&lt;span style=&quot;color: #dc2626;&quot;&gt;Do not grant cluster-admin access merely to make a test pass.&lt;/span&gt;**

#### 🟢 &lt;span style=&quot;color: #16a34a;&quot;&gt;Example 2: Namespace-Scoped Edit Policy (`AmazonEKSEditPolicy` scoped to namespace `project`)&lt;/span&gt;

```bash
# Associate the edit policy, scoped to namespace 'project' only
aws eks associate-access-policy \
  --cluster-name my-cluster \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=project

# Verify the association
aws eks list-associated-access-policies \
  --cluster-name my-cluster \
  --region ap-south-1 \
  --principal-arn arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole
```

> 🛡️ **&lt;span style=&quot;color: #15803d;&quot;&gt;What namespace scoping achieves:&lt;/span&gt;**
> GitHub Actions can deploy to namespace `'project'` — and **&lt;span style=&quot;color: #15803d;&quot;&gt;ONLY namespace `'project'`&lt;/span&gt;**. It cannot touch `kube-system`, `default`, `monitoring`, or any other namespace. If the IAM role is ever compromised, the blast radius is limited to one namespace. **&lt;span style=&quot;color: #15803d;&quot;&gt;This is defence-in-depth.&lt;/span&gt;**

## 🚀 Step 6 / Chapter 7.2 & 7.3: Test and Run the EKS Deployment Workflow

The authentication and deployment sequence is:

1. 🪪 GitHub Actions requests an OIDC token from GitHub.
2. 📤 The workflow presents the token to AWS STS using `AssumeRoleWithWebIdentity`.
3. 🔍 AWS validates the token against the configured OIDC provider and role trust policy.
4. 🎫 AWS issues temporary credentials for the IAM role.
5. ☸️ The workflow uses those credentials to access AWS and configure EKS access.



### 🖥️ &lt;span style=&quot;color: #2563eb;&quot;&gt;Workflow Option 1: Manual Trigger (`workflow_dispatch`) NGINX Deployment&lt;/span&gt;

The following example uses `workflow_dispatch`, allowing you to start the deployment manually from the GitHub Actions page.

Create `.github/workflows/deploy-nginx-eks.yaml`:

```yaml
name: Deploy NGINX to EKS

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Configure AWS credentials using OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_OIDC_ROLE }}
          aws-region: us-west-2

      - name: Set up kubeconfig
        run: |
          aws eks update-kubeconfig --region us-west-2 --name eks-spot-cluster-bibin

      - name: Deploy NGINX to EKS
        run: |
          kubectl create deployment nginx --image=nginx --port=80 --dry-run=client -o yaml | kubectl apply -f -
```

📝 **Before running the workflow, update:**

* 🔑 `AWS_OIDC_ROLE` so it points to the correct IAM role ARN.
* 🌍 `us-west-2` if your EKS cluster is in another AWS region.
* ☸️ `eks-spot-cluster-bibin` to your actual EKS cluster name.

Also ensure that the runner has a compatible `kubectl` binary available. The IAM role must be authorized in the EKS cluster, and its EKS access policy must permit the deployment operation.

▶️ Run the workflow manually from **GitHub → Actions → Deploy NGINX to EKS → Run workflow**.



### 💻 &lt;span style=&quot;color: #16a34a;&quot;&gt;Workflow Option 2: Complete Push-to-`main` Production Workflow (7.2)&lt;/span&gt;

Here is a complete, production-ready workflow file that uses the OIDC pattern:

```yaml
# .github/workflows/deploy.yml
name: Deploy to EKS

on:
  push:
    branches: [main]

permissions:
  id-token: write # REQUIRED: allows requesting the OIDC JWT
  contents: read  # REQUIRED: allows reading repo contents

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ap-south-1
          # No access-key-id or secret-access-key needed!

      - name: Configure kubectl
        run: |
          aws eks update-kubeconfig \
            --name my-cluster \
            --region ap-south-1

      - name: Deploy to namespace project
        run: |
          kubectl apply -f k8s/ -n project
          kubectl rollout status deployment/my-app -n project
```

### 🐳 7.3 Docker Registry Secret (One-Time Setup)

If your Kubernetes pods pull images from a private Docker registry, you need an image pull secret in the `project` namespace. This is a one-time setup step:

```bash
kubectl create secret docker-registry regcred \
  --docker-username=devopsshack \
  --docker-password=YOUR_DOCKERHUB_PASSWORD \
  --docker-email=devopsshack2025@gmail.com \
  --namespace=project
```

> ⚠️ **&lt;span style=&quot;color: #b45309;&quot;&gt;Keep Docker credentials out of your workflow YAML:&lt;/span&gt;**
> The `kubectl create secret` command should be run **&lt;span style=&quot;color: #16a34a;&quot;&gt;once manually&lt;/span&gt;** (from your local machine or admin account), not in the CI/CD pipeline. The secret lives in Kubernetes and gets used automatically when pods are scheduled. **&lt;span style=&quot;color: #dc2626;&quot;&gt;Never put registry passwords in workflow files or GitHub Secrets in plain text.&lt;/span&gt;**

## 🔄 End-to-End OIDC Workflow & Runtime Trace (Chapter 8)

The following diagram shows the overall GitHub Actions-to-AWS OIDC exchange.



The process can be understood as follows:

1. 🛠️ **&lt;span style=&quot;color: #2563eb;&quot;&gt;One-time AWS setup:&lt;/span&gt;** create the GitHub OIDC identity provider in IAM and create an IAM role with a trust policy that permits the intended GitHub workflow identity.
2. 🪪 **&lt;span style=&quot;color: #7c3aed;&quot;&gt;Request an identity token:&lt;/span&gt;** `aws-actions/configure-aws-credentials` requests a JWT from GitHub's OIDC provider.
3. 📤 **&lt;span style=&quot;color: #ea580c;&quot;&gt;Exchange the token:&lt;/span&gt;** the action sends the token to AWS Security Token Service (STS).
4. 🔍 **&lt;span style=&quot;color: #d97706;&quot;&gt;Validate the identity:&lt;/span&gt;** AWS checks the token and its claims against the configured identity provider and IAM role trust policy.
5. 🎫 **&lt;span style=&quot;color: #16a34a;&quot;&gt;Issue temporary credentials:&lt;/span&gt;** after successful validation, STS returns temporary AWS credentials. The source article describes a default session duration of one hour and a configurable range of 15 minutes to 12 hours, subject to role and action configuration.
6. 📦 **&lt;span style=&quot;color: #2563eb;&quot;&gt;Expose credentials to the job:&lt;/span&gt;** the credentials action makes the temporary credentials available to subsequent workflow steps, including through environment variables such as:
   * `AWS_ACCESS_KEY_ID`
   * `AWS_SECRET_ACCESS_KEY`
   * `AWS_SESSION_TOKEN`
7. ☁️ **&lt;span style=&quot;color: #16a34a;&quot;&gt;Call AWS services:&lt;/span&gt;** AWS CLI commands and SDKs (for example, Boto3) use the credentials to call AWS APIs.

### ⏳ What if the workflow finishes before the credentials expire?

Temporary credentials remain valid until their expiration or revocation conditions apply. For example, if a job finishes after 10 minutes but received credentials valid for one hour, those credentials may remain technically valid for the rest of that session duration. The runner ending does not, by itself, mean the credentials have immediately expired.

### 🕵️ 8.1 Step-by-Step Runtime Trace (What Happens When You Push to main)

Now that every piece is in place, let us trace exactly what happens from the moment you `git push` to the moment your pods are running. This chapter is the payoff — every resource we created plays a role here.

| # | 👤 Actor | ⚡ What Happens |
| :--- | :--- | :--- |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;1&lt;/span&gt;** | 👨‍💻 **Developer** | `git push origin main` — triggers the GitHub Actions workflow. |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;2&lt;/span&gt;** | 🐙 **GitHub** | Workflow starts. Because `permissions: id-token: write` is set, GitHub generates a signed JWT containing: `iss`, `sub` (repo+branch), `aud` (`sts.amazonaws.com`), `exp` (~5 min). |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;3&lt;/span&gt;** | ⚙️ **aws-actions action** | Calls AWS STS `AssumeRoleWithWebIdentity`, passing the JWT and the role ARN from `AWS_ROLE_TO_ASSUME`. |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;4&lt;/span&gt;** | 🛡️ **AWS STS** | Looks up the OIDC provider (`token.actions.githubusercontent.com`). Verifies JWT signature using GitHub's public key. Evaluates trust policy conditions (`aud` and `sub`). Issues 15-minute temporary credentials. |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;5&lt;/span&gt;** | 🏃 **GitHub Actions runner** | Receives temp credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`. These are set as environment variables — not stored anywhere. |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;6&lt;/span&gt;** | 🔧 **aws eks update-kubeconfig** | Uses temp credentials to call `eks:DescribeCluster`. Writes kubeconfig to `~/.kube/config` with an exec plugin entry (calls `aws eks get-token` at runtime). |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;7&lt;/span&gt;** | 🚀 **kubectl apply** | `kubectl` calls the exec plugin → `aws eks get-token` → returns a 15-min Kubernetes bearer token. Sends `kubectl apply` request to EKS API server with this token. |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;8&lt;/span&gt;** | ☸️ **EKS API server** | Receives the `kubectl` request with the bearer token. Validates the token against the access entry for `GitHubActionsEKSDeployRole`. Checks that the namespace requested (`project`) is within the allowed scope of `AmazonEKSEditPolicy`. |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;9&lt;/span&gt;** | 📦 **EKS (Kubernetes)** | Applies the manifests in namespace `project`. Pods are scheduled, services created, deployments rolled out. |
| **&lt;span style=&quot;color: #ea580c;&quot;&gt;10&lt;/span&gt;** | 🏁 **End of job** | Workflow completes. Temp credentials expire. The kubeconfig is gone (ephemeral runner). Nothing persists. Next run starts fresh. |

### 🔒 8.2 Security Properties This Architecture Guarantees

* ✅ **&lt;span style=&quot;color: #16a34a;&quot;&gt;No static credentials anywhere&lt;/span&gt;** — nothing to leak, rotate, or accidentally commit.
* ⏱️ **&lt;span style=&quot;color: #16a34a;&quot;&gt;Every token expires within 15 minutes&lt;/span&gt;** — a compromised token has a very short attack window.
* 🌿 **&lt;span style=&quot;color: #16a34a;&quot;&gt;Branch-locked trust&lt;/span&gt;** — only the `main` branch can trigger deployments. PRs from forks cannot assume the role.
* 🎯 **&lt;span style=&quot;color: #16a34a;&quot;&gt;Namespace-scoped Kubernetes access&lt;/span&gt;** — even a fully compromised IAM role cannot touch other namespaces or cluster-level resources.
* 📋 **&lt;span style=&quot;color: #16a34a;&quot;&gt;Full audit trail&lt;/span&gt;** — CloudTrail records every STS `AssumeRole` event with the JWT subject (repo + branch), giving you per-commit, per-run audit logs.

## ⚡ Chapter 9: Quick Reference — All AWS CLI Commands in Order

Use this chapter as a cheat sheet. Run these commands in order on a fresh setup.

### 1️⃣ &lt;span style=&quot;color: #2563eb;&quot;&gt;Step 1 — Verify prerequisites&lt;/span&gt;

```bash
aws sts get-caller-identity
aws eks describe-cluster --name my-cluster --region ap-south-1 \
  --query "{status:cluster.status,authMode:cluster.accessConfig.authenticationMode}"
```

### 2️⃣ &lt;span style=&quot;color: #2563eb;&quot;&gt;Step 2 — Create OIDC provider&lt;/span&gt;

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 3️⃣ &lt;span style=&quot;color: #2563eb;&quot;&gt;Step 3 — Create IAM role&lt;/span&gt;

```bash
# Write trust policy as ASCII (Windows PowerShell):
'{ ... }' | Out-File -FilePath .\github-oidc-trust.json -Encoding ascii

aws iam create-role \
  --role-name GitHubActionsEKSDeployRole \
  --assume-role-policy-document file://github-oidc-trust.json
```

### 4️⃣ &lt;span style=&quot;color: #2563eb;&quot;&gt;Step 4 — Create and attach IAM policy&lt;/span&gt;

```bash
aws iam create-policy \
  --policy-name GitHubActionsEKSDescribeClusterPolicy \
  --policy-document file://eks-describe-cluster-policy.json

aws iam attach-role-policy \
  --role-name GitHubActionsEKSDeployRole \
  --policy-arn arn:aws:iam::585593375370:policy/GitHubActionsEKSDescribeClusterPolicy
```

### 5️⃣ &lt;span style=&quot;color: #2563eb;&quot;&gt;Step 5 — Enable access entries (if needed)&lt;/span&gt;

```bash
aws eks update-cluster-config \
  --name my-cluster --region ap-south-1 \
  --access-config authenticationMode=API_AND_CONFIG_MAP
```

### 6️⃣ &lt;span style=&quot;color: #2563eb;&quot;&gt;Step 6 — Create access entry and associate policy&lt;/span&gt;

```bash
aws eks create-access-entry \
  --cluster-name my-cluster --region ap-south-1 \
  --principal-arn arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole

aws eks associate-access-policy \
  --cluster-name my-cluster --region ap-south-1 \
  --principal-arn arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=project
```

### 7️⃣ &lt;span style=&quot;color: #2563eb;&quot;&gt;Step 7 — Add GitHub secret&lt;/span&gt;

```text
# In GitHub repo Settings > Secrets and variables > Actions:
# Name:  AWS_ROLE_TO_ASSUME
# Value: arn:aws:iam::585593375370:role/GitHubActionsEKSDeployRole
```

### 8️⃣ &lt;span style=&quot;color: #2563eb;&quot;&gt;Step 8 — Add workflow file and deploy&lt;/span&gt;

```bash
# Add .github/workflows/deploy.yml with the workflow from Chapter 7
git add .github/workflows/deploy.yml
git commit -m 'feat: add OIDC-based EKS deployment workflow'
git push origin main
```

## 🏢 Configuring OIDC for AWS with Self-Hosted GitHub Enterprise Server (GHES)

OIDC can also be configured with a self-hosted GitHub Enterprise Server instance. The issuer URL differs from GitHub.com.

For GHES, the issuer URL follows this form:

```text
https://<GHES_HOSTNAME>/_services/token
```

⚠️ **&lt;span style=&quot;color: #b45309;&quot;&gt;Important considerations:&lt;/span&gt;**

* 🌐 Use the GHES hostname as the issuer URL.
* 🔒 The GHES OIDC endpoint must be reachable by AWS over HTTPS, or otherwise be accessible in a way that permits AWS to retrieve the issuer metadata and keys.
* ❌ A **&lt;span style=&quot;color: #dc2626;&quot;&gt;fully private GHES instance&lt;/span&gt;** that AWS cannot reach cannot be used for this AWS OIDC setup, because AWS must retrieve the OIDC issuer metadata.

## 🏁 Conclusion

GitHub Actions OIDC provides a way to authenticate to AWS without keeping long-lived AWS access keys in GitHub Secrets. The workflow receives **&lt;span style=&quot;color: #16a34a;&quot;&gt;temporary credentials&lt;/span&gt;** only after AWS validates the GitHub-issued identity token and the IAM role trust policy.

The practical sequence in this guide is:

1. 🏛️ Register GitHub as an OIDC identity provider in AWS IAM.
2. 🛡️ Create a Web Identity IAM role and restrict its trust policy.
3. 🔑 Save the role ARN in GitHub as `AWS_OIDC_ROLE` (or `AWS_ROLE_TO_ASSUME`).
4. 🧪 Validate the integration with a simple AWS CLI command that lists EC2 instances.
5. ☸️ Configure EKS access for the IAM role.
6. 🚀 Run a GitHub Actions workflow to deploy workloads to EKS.

Use **&lt;span style=&quot;color: #16a34a;&quot;&gt;least-privilege IAM permissions and EKS access policies&lt;/span&gt;** in production. Review the role's trust conditions regularly so that only the intended repositories and workflows can assume it.

## 📚 Original Sources

* 🌐 [How to Configure GitHub Actions OIDC with AWS (Easy Tutorial) – DevOpsCube](https://devopscube.com/github-actions-oidc-aws/) — **Authors:** Nitheesh Poojary and Bibin Wilson | **Original publication date:** May 15, 2025
* 📘 **DevOps Shack — DevSecOps Deep Dive Series:** *GitHub OIDC-Based Secure Deployment Architecture for Amazon EKS* (`@devopsshack` | 2026)
* 📙 **DevOps Shack:** *GitHub OIDC — The Bootstrap Problem Explained* (`@devopsshack` | `devopsshack.com` | Aditya Jaiswal)
