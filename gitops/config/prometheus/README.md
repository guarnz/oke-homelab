# Prometheus (kube-prometheus-stack, agent mode)

Cluster metrics collection deployed via the [prometheus-community/kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) Helm chart. Runs Prometheus in **agent mode** — no local TSDB, no query API, no Prometheus UI, no Alertmanager, no bundled Grafana. Scrapes the cluster and remote-writes everything to Grafana Cloud.

## What it deploys

The chart brings up the following workloads in the `monitoring` namespace:

| Workload | Kind | Role |
|----------|------|------|
| `prometheus-kube-prometheus-operator` | Deployment | Prometheus Operator — reconciles the PrometheusAgent CR and all `ServiceMonitor`/`PodMonitor` resources across the cluster |
| `prometheus-prometheus-kube-prometheus-prometheus` | StatefulSet | Prometheus Agent that scrapes and forwards to Grafana Cloud via `remote_write` |
| `prometheus-kube-state-metrics` | Deployment | Exposes Kubernetes object state metrics (Deployments, Pods, PVCs, Jobs, Nodes, Ingresses) — scraped via a chart-provided ServiceMonitor |
| `prometheus-prometheus-node-exporter` | DaemonSet | Exposes host-level Linux metrics (CPU, memory, disk, filesystem, network) — scraped via a chart-provided ServiceMonitor |

All samples carry an `external_labels` `cluster="oci-free-k8s"` so multiple clusters can share the same Grafana Cloud stack.

## Why agent mode

Prometheus in **agent mode** does not run a TSDB, does not expose the query API and does not serve the Prometheus UI. The only job is to scrape targets and push samples to a remote destination via `remote_write`. Since Grafana Cloud is the single source of truth for querying metrics on this cluster, keeping a full Prometheus Server locally would only add memory pressure and a persistent volume for a TSDB nobody queries. Agent mode keeps the operator and `ServiceMonitor`/`PodMonitor` UX from the ecosystem while cutting the Prometheus pod down to a plain forwarder (~256Mi–512Mi and no PVC).

## What is intentionally disabled

The chart bundles a full observability stack; this deployment deliberately turns most of it off to keep the footprint tight and avoid duplicating what the cluster already runs:

| Component | Why disabled |
|-----------|--------------|
| `alertmanager` | Alerts run in Grafana Cloud Alerting |
| `grafana` | Grafana Cloud is the UI |
| `thanosRuler` | Not needed with agent mode |
| `defaultRules` | Alert rules are managed in Grafana Cloud |
| `kubeControllerManager` / `kubeScheduler` / `kubeProxy` / `kubeEtcd` / `kubeDns` | Managed control plane on OKE — not exposed to scraping |

## Vault Secret

The `remote_write` endpoint credentials are stored in HashiCorp Vault at path `secret/grafana` and synced to the Kubernetes secret `prometheus-credentials` via External Secrets Operator. The `PrometheusAgent` CR references the Secret keys directly (`basicAuth.username.key` and `basicAuth.password.key`), so the token never lands on disk in a ConfigMap — the operator wires it into the Prometheus pod as a projected volume at runtime.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `PROMETHEUS_USERNAME` | Grafana Cloud Metrics instance ID (numeric) | `1234567` |
| `PROMETHEUS_PASSWORD` | Grafana Cloud API token with `metrics:write` scope | `glc_...` |

The `PROMETHEUS_URL` value is baked into `values.yaml` because it is not sensitive (the endpoint appears in every failed request log line). Additional keys stored on the same Vault path (`LOKI_URL`, `LOKI_USERNAME`, `LOKI_PASSWORD`) are ignored by this app and are consumed by whichever tool eventually ships logs to Grafana Cloud Loki.

### Where to find each value

1. Log in at [grafana.com](https://grafana.com) and open your stack.
2. Go to **Home → Connections → Add new connection → Hosted Prometheus metrics**.
3. Copy:
   - **Username / Instance ID** → `PROMETHEUS_USERNAME`
   - Click **Generate now** to create an access policy with the `metrics:write` scope and copy the returned token — that is `PROMETHEUS_PASSWORD` (shown once).
4. The **Remote Write Endpoint** shown on the same screen matches the `remoteWrite.url` set in `values.yaml` — bump it here whenever you rotate stacks or regions.

### Populating Vault

```bash
vault kv put secret/grafana \
  PROMETHEUS_USERNAME='1234567' \
  PROMETHEUS_PASSWORD='glc_...'
```

Use `vault kv patch secret/grafana ...` to add these keys without touching other values already stored on the same path.

## Adding new scrape targets

The Prometheus Agent is configured with `serviceMonitorSelectorNilUsesHelmValues: false` and the equivalent flags for `PodMonitor`, `Probe` and `ScrapeConfig`, which means **any `ServiceMonitor` or `PodMonitor` created in any namespace is picked up automatically** (no `release: prometheus` label required).

To onboard a new app:

1. Expose a `/metrics` endpoint on a stable port
2. Create a `ServiceMonitor` next to the Service:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: apps
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: my-app
  endpoints:
    - port: metrics
      interval: 60s
```

The operator will detect it within seconds, add it to the Prometheus Agent config and start remote-writing the samples to Grafana Cloud. No values.yaml change needed.

## Resources

Tuned tight to fit the OKE Free node budget while leaving headroom for the `remote_write` WAL when Grafana Cloud is briefly slow.

| Workload | requests.cpu | requests.memory | limits.cpu | limits.memory |
|----------|--------------|-----------------|------------|---------------|
| `prometheus-operator` | 50m | 128Mi | 200m | 256Mi |
| `prometheus-agent` | 100m | 256Mi | 500m | 512Mi |
| `kube-state-metrics` | 25m | 64Mi | 100m | 128Mi |
| `prometheus-node-exporter` | 25m | 32Mi | 100m | 64Mi |
| `admission webhook patch job` | 10m | 32Mi | 100m | 64Mi |

If the Prometheus Agent starts truncating its WAL under load, bump `prometheus.agent.prometheusSpec.resources.limits.memory` first — the WAL fits in whatever RAM is left over after the Go heap.

## Notes

- **Agent mode CRD** — the operator provisions a `PrometheusAgent` (not `Prometheus`) resource. It has no `retention`, no `storage`, no `alerting` fields — anything that only makes sense with a local TSDB is intentionally missing from the CR.
- **CRDs are installed by this chart** — `crds.enabled: true` makes the chart apply the Prometheus Operator CRDs (`Prometheus`, `PrometheusAgent`, `ServiceMonitor`, `PodMonitor`, `Probe`, `PrometheusRule`, `AlertmanagerConfig`, etc.) directly. No separate CRD chart is needed and Renovate updates them together with the operator.
- **`cluster="oci-free-k8s"` external label** stamped on every remote_write sample so future multi-cluster setups filter cleanly.
- **RBAC** is created automatically by the chart. The operator needs cluster-wide read on ServiceMonitors and their targets; kube-state-metrics needs read access to most object types; node-exporter reads `/proc`, `/sys` and `/rootfs` from the host.
- **Chart version** is pinned at the Application level (`gitops/apps/prometheus.yaml`). Renovate opens a PR when a new version drops upstream.
