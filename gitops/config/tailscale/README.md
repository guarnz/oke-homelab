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

The operator registers itself as `tag:k8s-operator` and tags the proxies it creates as `tag:k8s`.

### 1. Create the tags

Under **Access controls → Tags**, create both tags (this writes them to `tagOwners` automatically):

- `k8s-operator`
- `k8s` — owned by `k8s-operator`

### 2. Create the OAuth client

Under **Settings → Trust credentials → Credential → OAuth**:

- Scopes: enable **Devices → Core → Write** and **Keys → Auth Keys → Write** (the operator generates auth keys to register itself and its proxies; without the Auth Keys scope it fails with a `403`)
- Tags: add `tag:k8s-operator` on both scopes

Copy the resulting Client ID and Client Secret into Vault (see below); the secret is shown only once.

### 3. Fix the operator tag owner (JSON editor)

Creating the OAuth client rewrites `tagOwners` and leaves `tag:k8s-operator` without a valid owner for the client. The visual editor cannot make a tag own itself, so edit the policy file directly (**Access controls → JSON editor**) and set `tag:k8s-operator` to be owned by itself:

```json
{
  "tagOwners": {
    "tag:k8s-operator": ["tag:k8s-operator"],
    "tag:k8s": ["tag:k8s-operator"]
  }
}
```

The operator authenticates with an OAuth client that carries `tag:k8s-operator`, and to create its own registration auth key it must own that tag — so the tag has to list itself as owner. Owning it with `autogroup:admin` (or an empty list) instead makes the operator fail with `creating operator authkey: requested tags [tag:k8s-operator] are invalid or not permitted (400)`. `tag:k8s` is owned by `tag:k8s-operator`, so the operator can tag the proxies it creates.

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
