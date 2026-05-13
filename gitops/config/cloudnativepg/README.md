# CloudNativePG

PostgreSQL operator for Kubernetes, deployed via the [cloudnative-pg](https://cloudnative-pg.github.io/charts) Helm chart.

## How It Works

CloudNativePG manages the full lifecycle of PostgreSQL clusters — provisioning, replication, failover, backup and credential rotation — via Kubernetes custom resources.

```
Cluster CR → CloudNativePG Operator → PostgreSQL Pods + Secrets
```

The operator watches for `Cluster` resources and automatically provisions the PostgreSQL pods, services, and credentials within the cluster's namespace.

## No Vault Secret Required

The operator itself does not require any secrets to operate. It runs in the `cnpg-system` namespace and manages clusters across any namespace.

## Deploying a Cluster

Clusters are defined separately per application. This repository includes one cluster at [gitops/config/postgres/](../postgres/README.md). The operator only needs to be installed once to manage multiple clusters.

To deploy a new cluster, create a Helm release using the `cnpg/cluster` chart with a `Cluster` CR definition. See the [CloudNativePG documentation](https://cloudnative-pg.io/documentation/) for all available options.
