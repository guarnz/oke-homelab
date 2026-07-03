# Prometheus + Grafana (kube-prometheus-stack)

Self-hosted metrics stack deployed via the [prometheus-community/kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) Helm chart. Runs Prometheus in **server mode** with a local TSDB, kube-state-metrics, node-exporter and Grafana — everything the cluster needs to be observed without a managed backend.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | Grafana UI |

The `manifests/` directory contains the Istio Gateway, VirtualService and cert-manager Certificate. Update the domain in these files to match your own FQDN before deploying.

## What it deploys

The chart brings up the following workloads in the `monitoring` namespace:

| Workload | Kind | Role |
|----------|------|------|
| `prometheus-kube-prometheus-operator` | Deployment | Prometheus Operator — reconciles the Prometheus CR and every `ServiceMonitor`/`PodMonitor` created cluster-wide |
| `prometheus-prometheus-kube-prometheus-prometheus` | StatefulSet | Prometheus Server (local TSDB, 15d retention) that scrapes cluster targets |
| `prometheus-grafana` | Deployment | Grafana UI with Prometheus datasource pre-configured |
| `prometheus-kube-state-metrics` | Deployment | Exposes Kubernetes object state metrics |
| `prometheus-prometheus-node-exporter` | DaemonSet | Exposes host-level Linux metrics |

## What is intentionally disabled

The chart bundles a full observability stack; components that are not used are turned off explicitly:

| Component | Why disabled |
|-----------|--------------|
| `alertmanager` | Alerting will be handled separately |
| `thanosRuler` | Not needed for single-cluster setup |
| `kubeControllerManager` / `kubeScheduler` / `kubeProxy` / `kubeEtcd` / `kubeDns` | Managed control plane on OKE — not exposed to scraping |

## Vault Secret

The Grafana admin credentials are stored in HashiCorp Vault at path `secret/grafana` and synced to the Kubernetes secret `prometheus-credentials` via External Secrets Operator. Grafana reads the username/password directly from that Secret via the `admin.existingSecret` field of the chart.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `GRAFANA_ADMIN_USER` | Grafana admin username | `admin` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password | `long-random-string` |

### Populating Vault

```bash
vault kv patch secret/grafana \
  GRAFANA_ADMIN_USER='admin' \
  GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 32)"
```

## Storage

Both Prometheus and Grafana persist data on Longhorn PVCs.

| Workload | PVC | Retention |
|----------|-----|-----------|
| Prometheus TSDB | 15Gi | 15 days (or 12GB soft limit, whichever comes first) |
| Grafana | 5Gi | permanent |

At the current cluster workload count (~15-20 pods, ~7-10k active series) 15Gi covers roughly 30 days of samples with the 15d retention as an upper bound. If the disk fills up, Prometheus stops accepting new samples until compaction reclaims space — the `retentionSize: 12GB` acts as a soft ceiling and starts dropping the oldest blocks before the volume is exhausted.

## Adding new scrape targets

Prometheus is configured with `serviceMonitorSelectorNilUsesHelmValues: false` and the equivalent flags for `PodMonitor`, `Probe` and `ScrapeConfig`, which means **any `ServiceMonitor` or `PodMonitor` created in any namespace is picked up automatically** (no `release: prometheus` label required).

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

The operator will detect it within seconds, add it to the Prometheus config and start scraping.

## Resources

Tuned for the OKE Free node budget.

| Workload | requests.cpu | requests.memory | limits.cpu | limits.memory |
|----------|--------------|-----------------|------------|---------------|
| `prometheus-operator` | 50m | 128Mi | 200m | 256Mi |
| `prometheus` | 200m | 512Mi | 1000m | 1536Mi |
| `grafana` | 50m | 128Mi | 200m | 256Mi |
| `kube-state-metrics` | 25m | 64Mi | 100m | 128Mi |
| `prometheus-node-exporter` | 25m | 32Mi | 100m | 64Mi |
| `admission webhook patch job` | 10m | 32Mi | 100m | 64Mi |

Prometheus memory is the main lever — if scrape targets grow, bump `prometheus.prometheusSpec.resources.limits.memory` first.

## Notes

- **Prometheus datasource is auto-provisioned** in Grafana by the chart, pointing at the internal `http://prometheus-operated:9090` service. No manual configuration needed.
- **Default Kubernetes dashboards** are provisioned automatically via `grafana.defaultDashboardsEnabled: true` (~15 dashboards covering nodes, pods, deployments, kubelet, apiserver).
- **Dashboard sidecar** watches all namespaces for ConfigMaps labelled `grafana_dashboard: "1"` and imports them automatically — drop a ConfigMap next to any app to add its dashboard.
- **`external_labels.cluster = oci-free-k8s`** stamped on every sample so multi-cluster setups filter cleanly in the future.
- **CRDs are installed by this chart** (`crds.enabled: true`) and upgrade in lockstep with the operator via Renovate.
