# n8n

Workflow automation platform deployed via the [n8n](https://charts.n8n.io) Helm chart.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | n8n UI |

The `manifests/` directory contains the Istio Gateway, VirtualService and cert-manager Certificate. Update the domain in these files to match your own FQDN before deploying.

## Vault Secret

All sensitive configuration is stored in HashiCorp Vault at path `secret/n8n` and synced to the Kubernetes secret `n8n-credentials` via External Secrets Operator.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `N8N_ENCRYPTION_KEY` | Key used to encrypt credentials stored in the database — do not change after first install | `long-random-string` |

### SMTP (optional)

| Key | Description | Example |
|-----|-------------|---------|
| `N8N_SMTP_HOST` | SMTP server hostname | `smtp.example.com` |
| `N8N_SMTP_PORT` | SMTP port | `587` |
| `N8N_SMTP_USER` | SMTP username | `user@example.com` |
| `N8N_SMTP_PASS` | SMTP password | `your-smtp-password` |
| `N8N_SMTP_SENDER` | Sender email address | `n8n@example.com` |

### Populating Vault

```bash
vault kv put secret/n8n \
  N8N_ENCRYPTION_KEY='long-random-string'
```

## Post-Deploy Configuration

On first access, n8n will prompt you to create an admin account via the web UI.
