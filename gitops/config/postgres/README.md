# PostgreSQL

PostgreSQL cluster deployed via the [CloudNativePG cluster](https://cloudnative-pg.github.io/charts) Helm chart, managed by the CloudNativePG operator.

## How It Works

The cluster chart creates a `Cluster` custom resource that the CloudNativePG operator uses to provision and manage PostgreSQL pods, replication, and credentials.

## Vault Secret

The superuser (`postgres`) credentials are managed via HashiCorp Vault at path `secret/postgres` and synced to the Kubernetes secret `postgres-credentials` via External Secrets Operator.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `username` | PostgreSQL superuser name | `postgres` |
| `password` | PostgreSQL superuser password | `your-password` |

### Populating Vault

```bash
vault kv put secret/postgres \
  username='postgres' \
  password='your-password'
```

## Auto-generated Secrets

The remaining credentials are generated automatically by the CloudNativePG operator and stored in Kubernetes secrets within the `databases` namespace:

| Secret | Description |
|--------|-------------|
| `postgres-cluster-app` | Credentials for the `app` database user — auto-generated |
| `postgres-cluster-superuser` | Superuser credentials — auto-generated on first deploy, then managed via Vault |

Each secret contains `username`, `password`, `host`, `port`, `uri` and `jdbc-uri` ready to use.

## Connecting to the Database

Use the read-write service for writes and the read-only service for reads:

| Service | Description |
|---------|-------------|
| `postgres-cluster-rw.databases` | Read-write (primary) |
| `postgres-cluster-ro.databases` | Read-only (replicas) |

## Remote Access over Tailscale

`manifests/tailscale-service.yaml` defines an extra `postgres-tailscale` service that targets the primary and is exposed on the tailnet by the [Tailscale operator](../tailscale/README.md), tagged `tag:shared`. It is reachable from any tailnet device allowed to access `tag:shared` at:

```
postgres.<tailnet>.ts.net:5432
```

CloudNativePG does not allow annotating the built-in `rw`/`ro`/`r` services, so this is a separate service selecting the primary pod directly.
