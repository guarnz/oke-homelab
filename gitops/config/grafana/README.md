# Grafana Cloud Kubernetes Monitoring

Full observability stack for the cluster deployed via the [grafana/k8s-monitoring](https://github.com/grafana/k8s-monitoring-helm) Helm chart. Ships cluster metrics, pod logs, cluster events, kube-state-metrics and node-exporter samples to Grafana Cloud.

## What it deploys

The chart brings up the following workloads in the `monitoring` namespace:

| Workload | Kind | Role |
|----------|------|------|
| `grafana-alloy-metrics` | DaemonSet | Scrapes kubelet, cAdvisor, kube-state-metrics, node-exporter and pods annotated with `prometheus.io/scrape=true`, then remote-writes to Grafana Cloud Prometheus |
| `grafana-alloy-logs` | DaemonSet | Tails `/var/log/pods/**/*.log` on every node and ships to Grafana Cloud Loki |
| `grafana-alloy-singleton` | Deployment | Collects cluster-wide events and other single-instance signals |
| `grafana-kube-state-metrics` | Deployment | Exposes Kubernetes object state metrics (Deployments, Pods, PVCs, Jobs, Nodes, Ingresses) — scraped by `alloy-metrics` |
| `grafana-prometheus-node-exporter` | DaemonSet | Exposes host-level Linux metrics (CPU, memory, disk, filesystem, network) — scraped by `alloy-metrics` |

All samples carry an `external_labels` `cluster="oci-free-k8s"` so multiple clusters can share the same Grafana Cloud stack.

## Vault Secret

All Grafana Cloud credentials are stored in HashiCorp Vault at path `secret/grafana` and synced to the Kubernetes secret `grafana-credentials` via External Secrets Operator. The Alloy pods consume it via `envFrom.secretRef`, so every key in the Vault path is injected as an env var with the same name; URLs are read with `sys.env("KEY")` and username/password are looked up on the same Secret via `usernameKey` / `passwordKey`.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `PROMETHEUS_URL` | Prometheus remote_write endpoint of your Grafana Cloud stack | `https://prometheus-prod-XX-prod-<region>.grafana.net/api/prom/push` |
| `PROMETHEUS_USERNAME` | Grafana Cloud Metrics instance ID (numeric) | `1234567` |
| `PROMETHEUS_PASSWORD` | Grafana Cloud API token with `metrics:write` scope | `glc_...` |
| `LOKI_URL` | Loki push endpoint of your Grafana Cloud stack | `https://logs-prod-XXX.grafana.net/loki/api/v1/push` |
| `LOKI_USERNAME` | Grafana Cloud Logs instance ID (numeric) | `7654321` |
| `LOKI_PASSWORD` | Grafana Cloud API token with `logs:write` scope | `glc_...` |

A single access policy in Grafana Cloud with both `metrics:write` and `logs:write` scopes can back both `*_PASSWORD` values — reuse the same token if you prefer.

### Where to find each value

1. Log in at [grafana.com](https://grafana.com) and open your stack.
2. Go to **Home → Connections → Add new connection**.
3. Open **Hosted Prometheus metrics**:
   - `PROMETHEUS_URL` — field **Remote Write Endpoint** (ends in `/api/prom/push`)
   - `PROMETHEUS_USERNAME` — field **Username / Instance ID** (numeric)
   - `PROMETHEUS_PASSWORD` — click **Generate now** to create an access policy with the `metrics:write` scope and copy the returned token (`glc_...`). The token is shown once.
4. Open **Hosted Logs**:
   - `LOKI_URL` — field **URL** (ends in `/loki/api/v1/push`)
   - `LOKI_USERNAME` — field **User** (numeric)
   - `LOKI_PASSWORD` — reuse the token from step 3 if you created a single access policy with both `metrics:write` and `logs:write` scopes, otherwise generate a new one here with `logs:write`.

Tip: create one access policy in **Administration → Users and access → Cloud access policies** with both `metrics:write` and `logs:write` scopes and use the same token for both `*_PASSWORD` values — makes rotation a single-step operation.

### Populating Vault

```bash
vault kv put secret/grafana \
  PROMETHEUS_URL='https://prometheus-prod-XX-prod-<region>.grafana.net/api/prom/push' \
  PROMETHEUS_USERNAME='1234567' \
  PROMETHEUS_PASSWORD='glc_...' \
  LOKI_URL='https://logs-prod-XXX.grafana.net/loki/api/v1/push' \
  LOKI_USERNAME='7654321' \
  LOKI_PASSWORD='glc_...'
```

## Features enabled

The chart is organized around features that can be toggled independently. Currently enabled:

| Feature | Effect |
|---------|--------|
| `clusterMetrics` | Scrapes kube-state-metrics, node-exporter, kubelet, cAdvisor and API server for cluster-level metrics |
| `clusterEvents` | Ships Kubernetes events as logs to Loki |
| `podLogs` | Tails every pod's log on the node via `/var/log/pods` — no apiserver pressure |
| `annotationAutodiscovery` | Auto-scrapes any Pod or Service annotated with `prometheus.io/scrape=true` (honors `prometheus.io/port` and `prometheus.io/path`) |
| `telemetryServices.kube-state-metrics` | Deploys kube-state-metrics next to Alloy |
| `telemetryServices.node-exporter` | Deploys node-exporter as a DaemonSet |

## Resources

Tuned tight to fit the OKE Free node budget while leaving headroom for the remote_write WAL when Grafana Cloud is briefly slow.

| Workload | requests.cpu | requests.memory | limits.cpu | limits.memory |
|----------|--------------|-----------------|------------|---------------|
| `alloy-metrics` | 50m | 128Mi | 300m | 384Mi |
| `alloy-logs` | 50m | 128Mi | 200m | 256Mi |
| `alloy-singleton` | 25m | 64Mi | 100m | 128Mi |
| `kube-state-metrics` | 25m | 64Mi | 100m | 128Mi |
| `prometheus-node-exporter` | 25m | 32Mi | 100m | 64Mi |

If Alloy starts dropping samples or WAL-truncating under load, bump `alloy-metrics` memory first — remote_write buffers scale with memory, not CPU.

## Notes

- **DaemonSet log tailing** — `alloy-logs` mounts `/var/log` read-only from the host and reads pod logs directly from disk. No `pods/log` API calls, no client-go throttling.
- **Auto-discovered pod metrics** — any pod with the annotation `prometheus.io/scrape: "true"` is scraped automatically. Add `prometheus.io/port` and `prometheus.io/path` on the pod spec to onboard a new target with zero chart changes.
- **`cluster="oci-free-k8s"` external label** stamped on every metric and log line so future multi-cluster setups filter cleanly.
- **RBAC** is created automatically by each subchart (Alloy needs `get/list/watch` on Pods, Nodes, Services, Endpoints and Events; kube-state-metrics needs read access to most object types).
- **CRDs are not managed** by this chart.
- **Chart version** is pinned at the Application level (`gitops/apps/grafana.yaml`). Renovate opens a PR when a new version drops upstream.
