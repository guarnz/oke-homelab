# External DNS

Automatically creates and updates DNS records based on Kubernetes Service and Ingress resources. Deployed via the [kubernetes-sigs/external-dns](https://kubernetes-sigs.github.io/external-dns) Helm chart.

## How It Works

External DNS watches for Services (type `LoadBalancer`) and Ingress resources with the appropriate annotations, then creates the corresponding DNS records in your DNS provider automatically.

```
Service/Ingress → ExternalDNS → DNS Record (Cloudflare, Route53, OCI DNS, etc.)
```

## DNS Provider

The provider is configured in `values.yaml`. You can use any supported DNS provider — each one requires different credentials and environment variables. See the full list at:

**[External DNS Providers Documentation](https://github.com/kubernetes-sigs/external-dns/blob/master/charts/external-dns/README.md#providers)**

The current setup uses **Cloudflare**:

```yaml
provider:
  name: cloudflare
env:
  - name: CF_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: externaldns-credentials
        key: token
```

To switch providers, update `provider.name` and replace the `env` block with the credentials required by your provider.

## Vault Secret

All sensitive configuration is stored in HashiCorp Vault at path `secret/external-dns` and synced to the Kubernetes secret `externaldns-credentials` via External Secrets Operator.

### Required keys (Cloudflare)

| Key | Description | Example |
|-----|-------------|---------|
| `token` | Cloudflare API token with DNS edit permissions | `your-cloudflare-api-token` |

### Populating Vault

```bash
vault kv put secret/external-dns \
  token='your-cloudflare-api-token'
```

### Cloudflare API Token permissions

Your DNS zone must already exist in Cloudflare before ExternalDNS can manage records in it.

When creating the token in Cloudflare, grant the following permissions:

- **Zone / DNS / Edit** — for the target zone
- **Zone / Zone / Read** — to list zones

## Annotations

To have ExternalDNS manage a record for a specific hostname, add the annotation to your Service or Ingress:

```yaml
external-dns.alpha.kubernetes.io/hostname: myapp.example.com
```
