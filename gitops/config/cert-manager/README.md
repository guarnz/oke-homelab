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

To switch providers, update the `ClusterIssuer` template in `resources/templates/` and replace the credentials in Vault accordingly.

The ACME registration email is templated from `global.email` in `gitops/global-values.yaml`, so it is set once for the whole cluster rather than hardcoded per issuer.

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

The ACME challenge type is selected with `challenge` in `resources/values.yaml` (`dns` or `http`). Only the matching `ClusterIssuer` is created, and the Cloudflare `ExternalSecret` is rendered only for `dns`.

| `challenge` | ClusterIssuer | Challenge | Description |
|-------------|---------------|-----------|-------------|
| `dns` | `letsencrypt-dns01` | DNS-01 via Cloudflare | Used for wildcard and standard certs — requires the Vault secret |
| `http` | `letsencrypt-http01` | HTTP-01 | Used without a DNS provider — works with nip.io, no secret needed |

## Adding a Certificate

Certificates are not created by hand. Each app ships a `Certificate` template in its own `resources/` chart that references the selected `ClusterIssuer` and derives its hostname from values — the issuer from `global.issuer` and the FQDN from the app's `subdomain` plus `global.domain` in `gitops/global-values.yaml`. To add TLS to a new app, add a `Certificate` template to that app's `resources/templates/` following the existing apps; nothing is set here.

## Using HTTP-01 with nip.io

If you don't have a custom domain, set `challenge: http` in `resources/values.yaml` so only the HTTP-01 issuer is created, and point `global.issuer` at `letsencrypt-http01`. For the challenge to work, the cluster's load balancer public IP must be reachable on port 80 from the internet.

Get the load balancer IP:

```bash
kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Then use `<load-balancer-ip>.nip.io` as `global.domain`, so every app resolves to `<subdomain>.<load-balancer-ip>.nip.io` without a DNS provider.
