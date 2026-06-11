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

## Non-sensitive environment variables

Deployment-level configuration that is not a secret lives directly in `values.yaml` under `main.extraEnvVars`. Use this section for any plain n8n env var that needs to be tuned per-environment (reverse proxy behavior, feature flags, log levels, timeouts, telemetry toggles, etc.). Sensitive values stay in Vault — see [Vault Secret](#vault-secret) above.

### Currently set

| Variable | Value | Purpose |
|----------|-------|---------|
| `N8N_TRUST_PROXY` | `true` | Enables Express `trust proxy` so n8n parses the `X-Forwarded-For` header set by the Istio Ingress Gateway. Without it, n8n logs `ERR_ERL_UNEXPECTED_X_FORWARDED_FOR`, attributes every request to the gateway pod IP and breaks rate-limiting plus client-IP audit logs |
| `N8N_PROXY_HOPS` | `1` | Number of trusted proxies between the client and n8n. Istio Gateway is the single hop — bump to `2+` if another proxy (e.g. Cloudflare in front of Istio) is ever inserted |

### Adding more

Append to the same map — keys are env var names, values must be strings (quote numbers and booleans):

```yaml
main:
  extraEnvVars:
    N8N_TRUST_PROXY: "true"
    N8N_PROXY_HOPS: "1"
    N8N_LOG_LEVEL: "info"
    N8N_DIAGNOSTICS_ENABLED: "false"
```

For the full catalogue of n8n env vars see the [official reference](https://docs.n8n.io/hosting/configuration/environment-variables/).

## Post-Deploy Configuration

On first access, n8n will prompt you to create an admin account via the web UI.
