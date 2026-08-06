# Loki

Log aggregation backend deployed via the [loki](https://grafana.github.io/helm-charts) Helm chart. Stores and indexes the logs shipped by [Alloy](../alloy/README.md) and serves them to Grafana.

## Access

Loki is not exposed publicly — there is no Gateway, Certificate or VirtualService. It listens on a ClusterIP service reachable inside the cluster at `http://loki:3100`, which is what Alloy pushes to and what the Grafana datasource queries.

## Deployment mode

The chart supports three topologies (`SingleBinary`, `SimpleScalable`, `Distributed`). This install runs `SingleBinary`: every Loki component lives in one process backed by a single StatefulSet.

The chart defaults target the distributed topology, so the components that would otherwise be separate Deployments are explicitly disabled:

| Component | Chart default | Why disabled |
|-----------|---------------|--------------|
| `backend` / `read` / `write` | 3 replicas each | Their work happens inside the single binary |
| `chunksCache` / `resultsCache` | enabled | Each runs a Memcached pod sized for production ingest |
| `gateway` | enabled | An nginx that routes between distributed components — nothing to route |
| `lokiCanary` | enabled | DaemonSet injecting synthetic logs to monitor Loki itself |
| `test` | enabled | Helm test pod |

Components that already default to `0`/`false` in the chart (ingester, querier, distributor, compactor, index gateway, bloom) are left untouched rather than restated.

## Storage

| Setting | Value | Notes |
|---------|-------|-------|
| PVC | 5Gi (Longhorn) | Mounted at `/var/loki` |
| `storage.type` | `filesystem` | Chunks and index live on the PVC — no object storage required |
| `schemaConfig` | `tsdb` / `v13` | Current recommended index format |

At the measured cluster log volume (~600 KB/h raw across all pods, dominated by `argocd-application-controller`) the compressed footprint is roughly 1.4 MB/day, so 7 days occupies well under 100 MB. The 5Gi PVC is headroom for log spikes — a CrashLoopBackOff or an app switched to debug logging can multiply the daily volume several times over.

## Retention

| Setting | Value |
|---------|-------|
| `retention_period` | `168h` (7 days) |
| `reject_old_samples` | `true`, capped at `168h` |
| `compactor.retention_enabled` | `true` |

Retention is aligned with the Prometheus TSDB window so logs and metrics can be correlated over the same range.

`compactor.retention_enabled: true` is what actually enforces deletion. Setting `retention_period` alone silently keeps every log forever — the compactor is the component that drops expired chunks.

`reject_old_samples` guards against an agent with a skewed clock (or a replay) backfilling data that is already past the retention window.

## Grafana datasource

The datasource is declared in `gitops/config/prometheus/values.yaml` under `grafana.additionalDataSources`, since the Grafana instance ships with the kube-prometheus-stack:

```yaml
grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      uid: loki
      url: http://loki:3100
      access: proxy
```

## Monitoring

`monitoring.serviceMonitor.enabled: true` creates a ServiceMonitor so the existing Prometheus scrapes Loki's own metrics. It is picked up without a `release` label because Prometheus runs with `serviceMonitorSelectorNilUsesHelmValues: false`.

`selfMonitoring` and its Grafana Agent Operator are disabled — Prometheus and Alloy already cover that ground, and enabling it would install a second operator plus its CRDs.
