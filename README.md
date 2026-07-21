# OCI Free Kubernetes

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.35.2-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![OCI](https://img.shields.io/badge/Cloud-Oracle_OCI-F80000?logo=oracle&logoColor=white)](https://www.oracle.com/cloud/)
[![Vault](https://img.shields.io/badge/Secrets-HashiCorp_Vault-FFEC6E?logo=vault&logoColor=black)](https://www.vaultproject.io/)

Production-grade Kubernetes cluster running **entirely free** on OCI Always Free tier — GitOps with ArgoCD, Istio, Vault and Terraform.

## Overview

This repository contains the complete infrastructure and application stack for a personal Kubernetes cluster, following GitOps principles with Argo CD. Everything is managed as code — from the underlying OCI infrastructure (Terraform) to the Kubernetes applications (Helm), including secrets management (Vault), SSO (Zitadel) and distributed storage (Longhorn).

Enterprise-grade architecture running at **zero cost**, made possible by the OCI Always Free tier.

## Stack

| Component | Description |
|-----------|-------------|
| [Kubernetes (OKE)](https://www.oracle.com/cloud/cloud-native/kubernetes-engine/) | Managed Kubernetes on OCI Always Free tier |
| [Terraform](terraform/) | Infrastructure provisioning (OKE, VCN, budgets) |
| [Argo CD](gitops/bootstrap/argocd/) | GitOps continuous delivery |
| [Istio](gitops/config/istio/README.md) | Service mesh and ingress gateway |
| [HashiCorp Vault](gitops/config/vault/README.md) | Secrets management with OCI KMS auto-unseal |
| [External Secrets](gitops/config/external-secrets/README.md) | Sync Vault secrets to Kubernetes |
| [Cert Manager](gitops/config/cert-manager/README.md) | Automatic TLS certificates via Let's Encrypt |
| [ExternalDNS](gitops/config/external-dns/README.md) | Automatic DNS records in Cloudflare |
| [Tailscale Operator](gitops/config/tailscale/README.md) | Private access to cluster Services over the tailnet |
| [Longhorn](gitops/config/longhorn/README.md) | Distributed block storage |
| [CloudNativePG](gitops/config/cloudnativepg/) | PostgreSQL operator |
| [PostgreSQL](gitops/config/postgres/README.md) | PostgreSQL cluster |
| [Zitadel](gitops/config/zitadel/README.md) | Identity and Access Management (SSO) |
| [Vaultwarden](gitops/config/vaultwarden/README.md) | Self-hosted password manager |
| [N8N](gitops/config/n8n/README.md) | Workflow automation |
| [Actual Budget](gitops/config/actualbudget/README.md) | Local-first personal finance app |
| [Vikunja](gitops/config/vikunja/README.md) | Self-hosted task and project management |
| [Metrics Server](gitops/config/metrics-server/README.md) | Resource metrics for HPA and kubectl top |
| [Prometheus](gitops/config/prometheus/README.md) | Metrics collection with Grafana dashboards |

## Structure

```
.
├── terraform/          # OCI infrastructure (OKE, VCN, networking, budgets)
├── gitops/
│   ├── bootstrap/      # ArgoCD install and App of Apps
│   ├── apps/           # ArgoCD Application manifests
│   └── config/         # Helm values and manifests per app
└── scripts/            # Vault bootstrap and helper scripts
```

## Quick Start

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.15
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.10
- [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) (optional)

### 1. Infrastructure Setup

```bash
# Clone the repository
git clone https://github.com/nieri0x73/oci-free-k8s.git
cd oci-free-k8s

# Configure OCI credentials
oci setup config

# Create Terraform state bucket
oci os bucket create --name terraform-states --versioning Enabled --compartment-id <your-compartment-id>

# Deploy infrastructure
cd terraform
cp terraform.tfvars.example terraform.tfvars    # Edit with your values

# Optional: configure remote state on OCI Object Storage
cp backend.hcl.example backend.hcl              # Edit with your OCI namespace and region
terraform init -backend-config=backend.hcl      # Or just: terraform init (uses local state)
terraform plan
terraform apply
```

### 2. Access the Cluster

```bash
# Kubeconfig is generated automatically by Terraform
export KUBECONFIG=$(pwd)/.kube.config
kubectl get nodes
```

### 3. Configuration

Update the following to match your environment before proceeding:

- **FQDNs** — replace all domain references in `gitops/config/*/manifests/` with your own domain
- **DNS zone** — make sure your domain zone exists in Cloudflare before deploying ([External DNS](gitops/config/external-dns/README.md) will manage records automatically)
- **Vault KMS** — update `key_id`, `crypto_endpoint` and `management_endpoint` in `gitops/config/vault/values.yaml` with your OCI KMS values
- **Secrets** — populate Vault with the required keys for each app (see each app's README)

### 4. Install ArgoCD

Run the bootstrap script:

```bash
bash scripts/argocd-bootstrap.sh
```

Or manually:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  -f gitops/bootstrap/argocd/values.yaml --wait

# Apply the App of Apps
kubectl apply -f gitops/bootstrap/apps-of-apps.yaml
```

### 5. Install Vault

Run the bootstrap script:

```bash
bash scripts/vault-bootstrap.sh
```

Or manually:

```bash
# Initialize Vault (first time only) — save vault-init.json securely, do NOT commit it
kubectl exec -n security vault-0 -- vault operator init \
  -recovery-shares=5 \
  -recovery-threshold=3 \
  -format=json > vault-init.json

# Enable secrets engine and Kubernetes auth
kubectl exec -n security vault-0 -- vault secrets enable -path=secret kv-v2
kubectl exec -n security vault-0 -- vault auth enable kubernetes
kubectl exec -n security vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

# Populate secrets for each app
kubectl exec -n security vault-0 -- vault kv put secret/zitadel masterkey='...'
kubectl exec -n security vault-0 -- vault kv put secret/vaultwarden ADMIN_TOKEN='...'
# See each app README for required secret keys
```

### 6. Private Git Repositories (optional)

If any ArgoCD Application points to a private repository, register credentials in Vault at `secret/argocd-repo`. The ExternalSecret in `gitops/bootstrap/argocd/manifests/external-secret.yaml` renders a `repo-creds`-typed Secret that ArgoCD picks up automatically for every repo URL matching the stored prefix.

Required keys in `secret/argocd-repo`:

| Key | Value |
|-----|-------|
| `type` | `git` |
| `url` | URL prefix that matches every private repo (e.g. `https://github.com/<user>`) |
| `username` | Git username |
| `password` | Personal Access Token with `repo` scope |

```bash
kubectl exec -n security vault-0 -- vault kv put secret/argocd-repo \
  type=git \
  url=https://github.com/<user> \
  username=<user> \
  password=<github-pat>
```

## Contributing

Contributions are welcome! Feel free to open issues or pull requests to improve this project.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
- [ArgoCD](https://argoproj.github.io/cd/)
- [Istio](https://istio.io/)
- [HashiCorp Vault](https://www.vaultproject.io/)
- All the amazing open-source projects that make this possible
