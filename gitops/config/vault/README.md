# Vault

HashiCorp Vault deployed via the [hashicorp/vault](https://helm.releases.hashicorp.com) Helm chart.

## Auto-Unseal via OCI KMS

Vault is configured to auto-unseal using OCI Key Management Service (KMS) via Instance Principal authentication. The OKE worker nodes have an OCI IAM policy granting them permission to use the KMS key — no API key or secret is required.

The `seal "ocikms"` block in the HCL config contains:
- `key_id` — OCID of the KMS key used for sealing/unsealing
- `crypto_endpoint` — KMS crypto endpoint for the key's vault
- `management_endpoint` — KMS management endpoint for the key's vault
- `auth_type_api_key = false` — uses Instance Principal instead of API key

These values are specific to your OCI tenancy and region. To find them, go to OCI Console → Key Management → your key → copy the endpoints.

## Bootstrap (after ArgoCD is configured)

Once ArgoCD is running and has synced, Vault will be deployed automatically. Wait for the pod to be ready before proceeding.

### 1. Initialize Vault (first time only)

```bash
kubectl exec -n security vault-0 -- vault operator init \
  -recovery-shares=5 \
  -recovery-threshold=3 \
  -format=json > vault-init.json
```

> **Important:** Save `vault-init.json` securely. It contains the recovery keys needed to recover Vault if the KMS key is lost. Do NOT commit this file.

### 2. Verify Vault is Unsealed

Because OCI KMS auto-unseal is configured, Vault should unseal automatically after init. Verify:

```bash
kubectl exec -n security vault-0 -- vault status
```

`Sealed: false` means it is working correctly.

### 3. Configure Vault

```bash
kubectl exec -n security vault-0 -- vault secrets enable -path=secret kv-v2
kubectl exec -n security vault-0 -- vault auth enable kubernetes
kubectl exec -n security vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

kubectl exec -n security vault-0 -- vault policy write external-secrets - <<'EOF'
path "secret/data/*"     { capabilities = ["read"] }
path "secret/metadata/*" { capabilities = ["read", "list"] }
EOF

kubectl exec -n security vault-0 -- vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names="external-secrets" \
  bound_service_account_namespaces="security" \
  policies="external-secrets" \
  ttl="1h"
```

This configures:
- KV secrets engine at `secret/`
- Kubernetes auth method
- Policy `external-secrets` with read access to `secret/*`
- Role `external-secrets` bound to the External Secrets service account

> All of the above is handled automatically by `scripts/vault-bootstrap.sh`.

## External Secrets Operator Integration

After bootstrap, applications retrieve secrets from Vault automatically via the External Secrets Operator (ESO). The flow is:

**ESO → Vault (Kubernetes auth) → syncs to K8s Secret → consumed by the app**

The `vault-bootstrap.sh` script configures everything needed for this: the Kubernetes auth method, the `external-secrets` policy and role. Each app has an `ExternalSecret` manifest in its `manifests/` directory that points to its path in Vault.

## Audit Log

Vault writes an audit log to `/vault/audit/audit.log` inside the pod (emptyDir volume). Every request and response is recorded with sensitive values hashed. It is not persisted across pod restarts — for production, consider shipping logs to an external system.

```bash
kubectl exec -n security vault-0 -- cat /vault/audit/audit.log | head -20
```

## Secrets Structure

All secrets are stored under the `secret/` KV engine. Each application has its own path:

| Path | Application |
|------|-------------|
| `secret/postgres` | PostgreSQL credentials |
| `secret/vaultwarden` | Vaultwarden config (admin token, SMTP, SSO) |
| `secret/zitadel` | Zitadel masterkey and database credentials |
| `secret/n8n` | n8n config |
| `secret/cert-manager` | OCI DNS credentials for cert-manager |
| `secret/external-dns` | OCI DNS credentials for external-dns |

To add a new application secret, create an ExternalSecret manifest pointing to the desired path and populate the secret in Vault:

```bash
vault kv put secret/<app-name> \
  KEY1='value1' \
  KEY2='value2'
```

Each application's README documents the required keys for its path.

## Accessing Vault UI

```bash
kubectl port-forward -n security svc/vault 8200:8200
```

Open `http://localhost:8200` in your browser.
