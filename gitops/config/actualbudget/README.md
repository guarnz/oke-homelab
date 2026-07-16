# Actual Budget

Local-first personal finance app deployed via the [community-charts actualbudget](https://community-charts.github.io/helm-charts) Helm chart.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | Actual Budget UI |

The `manifests/` directory contains the Istio Gateway, VirtualService and cert-manager Certificate. Update the domain in these files to match your own FQDN before deploying.

## Storage

Actual Budget stores everything in local SQLite files — no external database is required. A Longhorn PVC (1Gi) holds both the server files (hashed password, session tokens) and the budget files.

## Authentication

Login uses the built-in password method. The server password is set on first access via the web UI and stored hashed inside the SQLite database on the PVC — no Vault secret is needed.

## Non-sensitive environment variables

Deployment-level configuration lives in `values.yaml` under `extraEnvVars`. Keys are env var names, values must be strings.

### Currently set

| Variable | Value | Purpose |
|----------|-------|---------|
| `TZ` | `America/Sao_Paulo` | Container timezone |
| `ACTUAL_TRUSTED_PROXIES` | `0.0.0.0/0` | Trusts the `X-Forwarded-For` header set by the Istio Ingress Gateway so client IPs are logged correctly |

For the full catalogue of env vars see the [official reference](https://actualbudget.org/docs/config/).

## Post-Deploy Configuration

On first access, Actual Budget will prompt you to set the server password via the web UI. Budget data can be imported from other tools (including CSV) through Settings → Import.
