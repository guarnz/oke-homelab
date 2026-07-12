# Tailscale Operator

Exposes Kubernetes Services and the Kubernetes API server on the tailnet, deployed via the [tailscale-operator](https://pkgs.tailscale.com/helmcharts) Helm chart.

## What it does

The operator runs in the `networking` namespace and connects cluster resources to the tailnet. Once running, expose a Service by annotating it:

```yaml
metadata:
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "vault"
```

The operator creates a proxy device for each exposed Service (tagged `tag:k8s`), reachable at `<hostname>.<tailnet>.ts.net` from any device on the tailnet. The Kubernetes API server is also exposed, allowing `kubectl` from any tailnet device without a public endpoint.

## Prerequisites

The operator registers itself as `tag:k8s-operator` and tags the proxies it creates as `tag:k8s`. Both must be declared in the tailnet ACL (Access Controls):

```json
{
  "tagOwners": {
    "tag:k8s-operator": ["autogroup:admin"],
    "tag:k8s": ["tag:k8s-operator"]
  }
}
```

`tag:k8s-operator` identifies the operator itself (only an admin may apply it, done once during OAuth registration). `tag:k8s` identifies the proxy devices; the delegation `["tag:k8s-operator"]` lets the operator tag its own proxies without manual intervention.

Create the tags first (Access controls → Tags), in order: `k8s-operator` owned by `autogroup:admin`, then `k8s` owned by `k8s-operator`. The OAuth client below cannot reference `tag:k8s` until it exists.

### OAuth client

Create the client the operator authenticates with, under **Settings → Trust credentials → Credential → OAuth**:

- Scopes: expand **Devices** and enable **Core → Write**
- Tags: add `tag:k8s` (required for the write scope; this is the tag the operator assigns to the proxies it creates)

Copy the resulting Client ID and Client Secret into Vault (see below); the secret is shown only once.

## Vault Secret

The OAuth credentials are stored in HashiCorp Vault at path `secret/tailscale` and synced to the Kubernetes secret `operator-oauth` (the fixed name the chart expects) via External Secrets Operator.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `client_id` | OAuth client ID from the Tailscale admin console | `k123456CNTRL` |
| `client_secret` | OAuth client secret (shown once on creation) | `tskey-client-k123456CNTRL-...` |

## Populating Vault

```bash
vault kv put secret/tailscale \
  client_id='k123456CNTRL' \
  client_secret='tskey-client-k123456CNTRL-...'
```
