# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please **do not open a public issue**. Send an email to the repository owner via GitHub with a description of the issue and steps to reproduce. You can expect an acknowledgment within 48 hours.

## Security Measures

### Secrets Management

- **No hardcoded secrets** in the repository
- **OCI KMS auto-unseal** — Vault unseal key is managed by OCI KMS via Instance Principal, never exposed
- Secrets are managed via:
  - HashiCorp Vault (in-cluster)
  - External Secrets Operator (sync from Vault to Kubernetes)
- Sensitive files are excluded via `.gitignore`:
  - `*.tfvars`
  - `.kube.config`
  - Private keys

### Access Control

- **SSO** for all externally exposed web UIs via Zitadel (OIDC), except those accessed via port-forward
- **Single ingress point** — all external traffic goes through Istio Gateway
- **Instance Principal** — OCI authentication uses Instance Principal, no API keys stored in the repository

### Network Security

- **Worker nodes in private subnet** — not directly exposed to the internet
- **Network Security Groups (NSGs)** — traffic restricted at the OCI level
- **Automatic TLS** — all exposed services use Let's Encrypt certificates via Cert Manager

### Supply Chain

- **Gitleaks** — scans commits for secrets and credentials before push
- **Pre-commit hooks** — additional checks for private keys and large files
- **Terraform provider pinning** — all provider versions are pinned to prevent supply chain attacks
- **Renovate Bot** — keeps dependencies up to date automatically

## Dependencies

This project relies on several third-party components. Security updates are managed via:

- **Renovate Bot** — Automated dependency updates
- **Helm Charts** — Regular version updates
- **Container Images** — Pinned versions where possible

## Supported Versions

| Version | Supported |
|---------|-----------|
| main    | Yes       |
