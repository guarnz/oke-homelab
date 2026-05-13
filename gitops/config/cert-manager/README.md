# Cert Manager

Automatic TLS certificate provisioning via Let's Encrypt, deployed via the [cert-manager](https://charts.jetstack.io) Helm chart.

## How It Works

Cert Manager watches for `Certificate` resources and requests TLS certificates from Let's Encrypt using DNS-01 or HTTP-01 challenges.

```
Certificate → ClusterIssuer → Let's Encrypt → TLS Secret
```

## Vault Secret

All sensitive configuration is stored in HashiCorp Vault at path `secret/cert-manager` and synced to the Kubernetes secret `cert-manager-credentials` via External Secrets Operator.

The current setup uses **Cloudflare** for DNS-01, but cert-manager supports many other providers such as Route53, Google Cloud DNS, Azure DNS, and others. See the full list at:

**[cert-manager DNS01 Providers Documentation](https://cert-manager.io/docs/configuration/acme/dns01/)**

To switch providers, update the `ClusterIssuer` manifest in `manifests/` and replace the credentials in Vault accordingly.

### Required keys (Cloudflare DNS-01)

| Key | Description | Example |
|-----|-------------|---------|
| `token` | Cloudflare API token with DNS edit permissions | `your-cloudflare-api-token` |

### Populating Vault

```bash
vault kv put secret/cert-manager \
  token='your-cloudflare-api-token'
```

### Cloudflare API Token permissions

- **Zone / DNS / Edit** — for the target zone
- **Zone / Zone / Read** — to list zones

## ClusterIssuers

| Name | Challenge | Description |
|------|-----------|-------------|
| `letsencrypt-dns01` | DNS-01 via Cloudflare | Used for wildcard and standard certs — requires Vault secret |
| `letsencrypt-http01` | HTTP-01 | Used without a DNS provider — works with nip.io |

## Using HTTP-01 with nip.io

If you don't have a custom domain, you can use [nip.io](https://nip.io) with the HTTP-01 issuer to get a valid Let's Encrypt certificate. For the challenge to work, the cluster's load balancer public IP must be reachable on port 80 from the internet.

Get the load balancer IP:

```bash
kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Then use the IP as part of the nip.io hostname:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: istio-system
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-http01
    kind: ClusterIssuer
  dnsNames:
    - myapp.<load-balancer-ip>.nip.io
```

## Adding a Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: istio-system
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-dns01
    kind: ClusterIssuer
  dnsNames:
    - myapp.example.com
```
