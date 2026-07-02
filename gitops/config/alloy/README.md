# Alloy

Telemetry collector deployed via the [grafana/alloy](https://github.com/grafana/alloy) Helm chart. Runs as a DaemonSet in the `monitoring` namespace and forwards cluster metrics and pod logs to Grafana Cloud (Mimir + Loki).

## What it collects

| Signal | Source | Destination |
|--------|--------|-------------|
| Metrics | kubelet `/metrics/cadvisor` and `/metrics`, plus pods annotated with `prometheus.io/scrape=true` | Grafana Cloud Mimir (`prometheus.remote_write`) |
| Logs | Every pod on the node, tailed from the container runtime | Grafana Cloud Loki (`loki.write`) |

All samples carry an `external_label` `cluster="oci-free-k8s"` so multiple clusters can share the same Grafana Cloud stack.

## Vault Secret

All Grafana Cloud credentials are stored in HashiCorp Vault at path `secret/alloy` and synced to the Kubernetes secret `alloy-credentials` via External Secrets Operator. The Alloy pod consumes it via `alloy.envFrom.secretRef`, so every key in the Vault path is injected as an env var with the same name and referenced inside the River config with `env("KEY")`. Add or rename keys in Vault and update the River config accordingly.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `MIMIR_URL` | Prometheus remote_write endpoint of your Grafana Cloud stack | `https://prometheus-prod-XX-prod-us-east-0.grafana.net/api/prom/push` |
| `MIMIR_USERNAME` | Grafana Cloud Metrics instance ID (numeric) | `1234567` |
| `MIMIR_PASSWORD` | Grafana Cloud API token with `MetricsPublisher` scope | `glc_...` |
| `LOKI_URL` | Loki push endpoint of your Grafana Cloud stack | `https://logs-prod-XXX.grafana.net/loki/api/v1/push` |
| `LOKI_USERNAME` | Grafana Cloud Logs instance ID (numeric) | `7654321` |
| `LOKI_PASSWORD` | Grafana Cloud API token with `LogsPublisher` scope | `glc_...` |

A single access policy in Grafana Cloud with both `metrics:write` and `logs:write` scopes can back both `*_PASSWORD` values — reuse the same token if you prefer.

### Where to find each value

1. Log in at [grafana.com](https://grafana.com) and open your stack.
2. Go to **Home → Connections → Add new connection**.
3. Open **Hosted Prometheus metrics**:
   - `MIMIR_URL` — field **Remote Write Endpoint** (ends in `/api/prom/push`)
   - `MIMIR_USERNAME` — field **Username / Instance ID** (numeric)
   - `MIMIR_PASSWORD` — click **Generate now** to create an access policy with the `metrics:write` scope and copy the returned token (`glc_...`). The token is shown once.
4. Open **Hosted Logs**:
   - `LOKI_URL` — field **URL** (ends in `/loki/api/v1/push`)
   - `LOKI_USERNAME` — field **User** (numeric)
   - `LOKI_PASSWORD` — reuse the token from step 3 if you created a single access policy with both `metrics:write` and `logs:write` scopes, otherwise generate a new one here with `logs:write`.

Tip: create one access policy in **Administration → Users and access → Cloud access policies** with both `metrics:write` and `logs:write` scopes and use the same token for both `*_PASSWORD` values — makes rotation a single-step operation.

### Populating Vault

```bash
vault kv put secret/alloy \
  MIMIR_URL='https://prometheus-prod-XX-prod-us-east-0.grafana.net/api/prom/push' \
  MIMIR_USERNAME='1234567' \
  MIMIR_PASSWORD='glc_...' \
  LOKI_URL='https://logs-prod-XXX.grafana.net/loki/api/v1/push' \
  LOKI_USERNAME='7654321' \
  LOKI_PASSWORD='glc_...'
```

The URLs and usernames are shown under **Connections → Add new connection → Hosted Prometheus metrics** and **Hosted logs** in the Grafana Cloud UI. Generate the token under **Access Policies**.

## River config

The full River pipeline lives inline in `values.yaml` under `alloy.configMap.content`. Blocks:

- `discovery.kubernetes` — lists nodes and pods
- `prometheus.scrape "cadvisor"` / `"kubelet"` — hits every node's kubelet through the apiserver proxy using the ServiceAccount token
- `prometheus.scrape "pods"` — scrapes pods annotated with `prometheus.io/scrape=true` (respects `prometheus.io/port` and `prometheus.io/path`)
- `prometheus.remote_write "mimir"` — ships all metrics to Grafana Cloud
- `loki.source.kubernetes "pods"` — tails logs of every pod running on the same node as this Alloy instance
- `loki.write "grafana_cloud"` — ships logs to Grafana Cloud

Each collector filters its targets to the local node via `env("HOSTNAME")` so the DaemonSet does not duplicate work across pods.

## Resources

| Knob | Value | Why |
|------|-------|-----|
| `alloy.resources.requests.cpu` | `50m` | Matches idle CPU of a single-node scrape + tail pipeline |
| `alloy.resources.requests.memory` | `128Mi` | Covers the base Alloy runtime plus in-memory WAL for remote_write |
| `alloy.resources.limits.cpu` | `200m` | Absorbs bursts during scrape rounds and backlog drains |
| `alloy.resources.limits.memory` | `256Mi` | Leaves headroom for the metrics/logs WAL when Grafana Cloud is briefly slow |

Sizing is intentionally tight because the DaemonSet runs on every node of a Free-tier cluster. If Alloy starts dropping samples or WAL-truncating under load, bump memory first — remote_write buffers scale with memory, not CPU.

## Notes

- Chart pins `crds.create: false` — Alloy does not ship CRDs and the flag skips the empty subchart.
- `controller.type: daemonset` — one Alloy per node so both scrape targets and pod logs stay node-local. Switching to `statefulset` would centralize collection but drop the log tailer.
- The chart creates a ClusterRole/ClusterRoleBinding that gives Alloy `get`/`list`/`watch` on nodes, pods and services — required for discovery and for scraping kubelet through the apiserver proxy.
- Pod-metric scraping is opt-in: only pods with `prometheus.io/scrape: "true"` annotation are collected. Add the annotation on a Deployment/Pod spec to onboard a new target.
- Log tailing is not opt-in — every pod on the node is shipped to Loki. Trim volume with `loki.process` stages inside the River config if any app becomes noisy.
