# Alloy

Log collection agent deployed via the [alloy](https://grafana.github.io/helm-charts) Helm chart. Runs on every node, reads container logs and ships them to [Loki](../loki/README.md).

Alloy is the successor to Promtail, which reached end of life in March 2026. It can also collect metrics and traces, but this install is scoped to logs — metrics stay with the kube-prometheus-stack.

## Access

Alloy has no UI exposed and no persistence. It is a DaemonSet that reads from the node filesystem and pushes to `http://loki:3100`.

## Controller

| Setting | Value | Notes |
|---------|-------|-------|
| `controller.type` | `daemonset` | One pod per node, so every node's container logs are collected |
| `clustering.enabled` | `false` | Clustering coordinates work sharding between Alloy instances; unnecessary when each pod only reads its own node |
| `mounts.varlog` | `true` | Mounts `/var/log` so the pod can read container log files |

## Pipeline

The collection pipeline is defined in River under `alloy.configMap.content`. It runs in four stages:

| Stage | Component | Role |
|-------|-----------|------|
| Discover | `discovery.kubernetes` | Lists pods from the Kubernetes API |
| Label | `discovery.relabel` | Maps pod metadata onto log labels |
| Read | `loki.source.kubernetes` | Tails container logs for the discovered targets |
| Filter | `loki.process` | Drops blank lines |
| Ship | `loki.write` | Pushes batches to Loki |

### Labels

Only low-cardinality metadata is promoted to labels:

| Label | Source |
|-------|--------|
| `namespace` | `__meta_kubernetes_namespace` |
| `pod` | `__meta_kubernetes_pod_name` |
| `container` | `__meta_kubernetes_pod_container_name` |
| `node` | `__meta_kubernetes_pod_node_name` |
| `app` | `app.kubernetes.io/name` label |

This matters more than it looks. Every unique label combination creates a separate stream in Loki, and each open stream holds a chunk in memory. Adding a label with an unbounded value — pod IP, request ID, trace ID — multiplies stream count and is the most common cause of Loki memory blowups. Keep high-cardinality data in the log line itself, where it stays queryable via LogQL filters without touching the index.

## Resources

| | Request | Limit |
|---|---------|-------|
| CPU | 50m | 200m |
| Memory | 128Mi | 256Mi |

Applied per pod, so the DaemonSet reserves 128Mi × node count. Alloy's footprint tracks the number of targets it watches rather than log throughput.

## Monitoring

`serviceMonitor.enabled: true` exposes Alloy's own metrics to the existing Prometheus, which picks the ServiceMonitor up without a `release` label thanks to `serviceMonitorSelectorNilUsesHelmValues: false`.
