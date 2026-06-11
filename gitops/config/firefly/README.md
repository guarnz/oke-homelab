# Firefly III

Personal finance manager deployed via the [firefly-iii-stack](https://firefly-iii.github.io/kubernetes/) Helm chart. Bundles the Firefly III core application and the Data Importer (OFX/CSV/Nordigen/SimpleFIN). The bundled PostgreSQL subchart is disabled — the shared `postgres-cluster` (CloudNativePG) is used instead.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | Firefly III UI |
| `https://<importer-domain>` | Data Importer UI |

The `manifests/` directory contains the Istio Gateway, VirtualServices and cert-manager Certificate. Update the domains in these files to match your own FQDNs before deploying.

## Vault Secret

All sensitive configuration is stored in HashiCorp Vault at path `secret/firefly` and synced to the Kubernetes secret `firefly-credentials` via External Secrets Operator. The same secret is consumed by both Firefly III (`APP_KEY`, `DB_PASSWORD`, cron token) and the Data Importer (`accessToken`).

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `APP_KEY` | Laravel `APP_KEY` used to encrypt the session and database fields — must be exactly 32 characters and never changed after first install. Overrides the chart's auto-generated `firefly-firefly-iii-app-key` Secret via `envFrom` ordering | `32-char-random-alphanumeric` |
| `DB_PASSWORD` | Password of the `firefly` application user in the external `postgres-cluster` — must match the password configured on the role when it was created | `your-firefly-db-password` |
| `STATIC_CRON_TOKEN` | Token consumed by the recurring transactions CronJob — must be exactly 32 characters | `32-char-random-alphanumeric` |
| `accessToken` | Personal Access Token used by the Data Importer to authenticate against Firefly III. Generated on the Firefly III UI after the first login (see [Post-Deploy Configuration](#post-deploy-configuration)) | `eyJ0eXAiOiJKV1QiLCJhbGciOi...` |

### Populating Vault

```bash
vault kv put secret/firefly \
  APP_KEY="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)" \
  DB_PASSWORD='your-firefly-db-password' \
  STATIC_CRON_TOKEN="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)" \
  accessToken='placeholder-replace-after-first-login'
```

> The `accessToken` is generated on the Firefly III UI **after** the first login — populate the Vault key with a placeholder during bootstrap and patch it once the real token is issued (see below).

## Database

Firefly III uses the cluster's shared **`postgres-cluster`** (CloudNativePG) in the `databases` namespace as its database. The bundled PostgreSQL subchart is disabled (`firefly-db.enabled: false`). Connection target:

```
postgres-cluster-rw.databases.svc.cluster.local:5432
```

### Bootstrapping the database

The `firefly` user and `firefly` database must exist in `postgres-cluster` **before** the chart runs its initial migration — Firefly III does not create them.

Run once against the cluster:

```bash
FIREFLY_PASS=$(kubectl -n apps get secret firefly-credentials -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)
kubectl -n databases exec postgres-cluster-1 -c postgres -- psql -U postgres -v ON_ERROR_STOP=1 <<SQL
CREATE USER firefly WITH PASSWORD '${FIREFLY_PASS}';
CREATE DATABASE firefly OWNER firefly;
GRANT ALL PRIVILEGES ON DATABASE firefly TO firefly;
SQL
```

The password set here must match the `DB_PASSWORD` key in Vault `secret/firefly`.

### Alternative: use the bundled PostgreSQL subchart

If you do not want to share `postgres-cluster` (or you are running Firefly III standalone outside this repo), the `firefly-iii-stack` chart ships its own PostgreSQL subchart. Swap `values.yaml` to:

```yaml
firefly-db:
  enabled: true
  storage:
    class: longhorn
    accessModes: ReadWriteOnce
    dataSize: 2Gi
  configs:
    DBNAME: firefly
    DBUSER: firefly
    PGPASSWORD: "" # leave empty, supply via existingSecret below
    TZ: America/Sao_Paulo
  backupSchedule: "0 3 * * *"

firefly-iii:
  config:
    existingSecret: firefly-credentials
    env:
      DB_CONNECTION: pgsql
      DB_HOST: firefly-firefly-db # service name of the bundled subchart
      DB_PORT: "5432"
      DB_DATABASE: firefly
      DB_USERNAME: firefly
      # ...rest unchanged
```

Trade-offs versus CNPG:

| Aspect | Bundled subchart | Shared `postgres-cluster` (CNPG) |
|--------|------------------|----------------------------------|
| Setup | Zero — chart provisions the DB | Manual `CREATE USER`/`CREATE DATABASE` step |
| Postgres version | Pinned to `postgres:10-alpine` (legacy) | Tracks the cluster image (currently 18.x) |
| HA / failover | Single replica, no replication | Multi-instance with synchronous replication |
| Backups | Local cron pg_dump only | CNPG continuous WAL + retention policy |
| Resource cost | Extra pod + PVC just for one app | Reuses the existing cluster |
| Operability | Isolated, but no shared tooling | One Postgres to monitor, patch, back up |

For this repo, **CNPG is the default and recommended path** — it matches how every other stateful app (Zitadel) wires up to Postgres and survives node loss. The bundled subchart is documented here as an escape hatch for standalone deployments or environments without CNPG.

When using the bundled subchart, also add `PGPASSWORD` to the Vault path so the subchart picks it up via its own env vars (the chart reads it directly from `firefly-db.configs.PGPASSWORD` or from a secret you mount — see the [subchart README](https://github.com/firefly-iii/kubernetes/tree/main/charts/firefly-db) for details).

## Post-Deploy Configuration

### 1. First login

On first access, Firefly III prompts you to register the first user via the web UI. The first registered account becomes the instance owner. Email registration can be disabled afterwards in `Profile → Settings → Disable registration` to lock down the instance.

### 2. Generate the importer access token

The Data Importer needs a Personal Access Token to talk to Firefly III. Generate it once after the first login:

1. Sign in to Firefly III at `https://<your-domain>`
2. Navigate to **Options → Profile → OAuth → Personal Access Tokens**
3. Click **Create new token** and copy the value (shown only once)
4. Update the Vault key:

```bash
vault kv patch secret/firefly accessToken='<token-from-firefly>'
```

5. Force the ExternalSecret to refresh and restart the importer pod:

```bash
kubectl -n apps annotate externalsecret firefly-credentials force-sync=$(date +%s) --overwrite
kubectl -n apps rollout restart deployment firefly-importer
```

6. Open the importer at `https://<importer-domain>` and click **Reauthenticate** if prompted — it should now reach the Firefly III API successfully.

### 3. Recurring transactions CronJob

The chart deploys a CronJob that hits Firefly's `/cron/<STATIC_CRON_TOKEN>` endpoint daily at 03:00 to process recurring transactions and bills. Token authentication is wired via `cronjob.auth.existingSecret`, so no extra configuration is required — just keep `STATIC_CRON_TOKEN` in Vault stable.

## Notes

- Configuration is split between non-sensitive env vars in `values.yaml` (host, ports, timezone, `APP_URL`) and sensitive ones sourced from `firefly-credentials` (`APP_KEY`, `DB_PASSWORD`, `STATIC_CRON_TOKEN`, `accessToken`).
- Losing `APP_KEY` means losing access to all encrypted data in the database — back it up alongside the Vault unseal/recovery keys.
- The chart's auto-generated `firefly-firefly-iii-app-key` Secret holds a random `APP_KEY`, but `firefly-credentials` is loaded **after** it in `envFrom`, so the Vault value wins. Do not delete the auto-generated Secret — the chart will recreate it on every sync and it is harmless.
- The importer's `vanityUrl` is set to the public Firefly URL so OAuth redirects work correctly behind Istio; the internal `url` stays as the in-cluster service for actual API calls.
- Uploaded attachments (receipts, statements) live on a Longhorn PVC (`firefly-iii.persistence`) — sized at 2Gi by default, bump it if you start archiving heavy PDFs.
