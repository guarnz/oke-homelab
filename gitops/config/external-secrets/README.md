# External Secrets Operator

Syncs secrets from HashiCorp Vault into Kubernetes Secrets automatically. Deployed via the [external-secrets/external-secrets](https://charts.external-secrets.io) Helm chart.

## How It Works

External Secrets Operator (ESO) watches `ExternalSecret` resources and pulls values from Vault, creating and keeping native Kubernetes Secrets up to date.

```
Vault (secret/app) → ExternalSecret → Kubernetes Secret → Pod env/volume
```

## ClusterSecretStore

A single `ClusterSecretStore` named `vault` is configured cluster-wide, pointing to the internal Vault service:

| Field | Value |
|-------|-------|
| Server | `http://vault.security.svc.cluster.local:8200` |
| KV path | `secret` |
| KV version | `v2` |
| Auth method | Kubernetes (ServiceAccount) |
| Vault role | `external-secrets` |

## Vault Configuration (Bootstrap)

ESO authenticates to Vault using Kubernetes auth. Run these commands after Vault is initialized:

```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure the auth method
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

# Create a policy that allows reading secrets
vault policy write external-secrets - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
EOF

# Create the role bound to the ESO service account
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=security \
  policies=external-secrets \
  ttl=1h
```

> All of the above is handled automatically by the Vault bootstrap script (`scripts/vault-bootstrap.sh`).

## Adding Secrets for an App

### 1. Write the secret to Vault

```bash
vault kv put secret/<app> \
  key1='value1' \
  key2='value2'
```

### 2. Create an ExternalSecret manifest

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app>-credentials
  namespace: <app-namespace>
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: <app>-credentials
  data:
    - secretKey: myKey
      remoteRef:
        key: secret/<app>
        property: key1
```

The resulting Kubernetes Secret `<app>-credentials` will be created and refreshed every hour.
