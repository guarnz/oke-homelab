# Evolution API

WhatsApp HTTP API ([Evolution API](https://github.com/EvolutionAPI/evolution-api)) deployed as plain Kubernetes manifests reconciled by Kustomize. No upstream Helm chart is available, so the Deployment, Service, Gateway, VirtualService, Certificate and ExternalSecret are tracked directly under `manifests/`.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | Evolution API HTTP endpoint |
| `https://<your-domain>/manager` | Built-in manager UI |

The `manifests/` directory contains the Istio Gateway, VirtualService and cert-manager Certificate. Update the domain in these files to match your own FQDN before deploying.

## Vault Secret

All sensitive configuration is stored in HashiCorp Vault at path `secret/evolution-api` and synced to the Kubernetes secret `evolution-api-credentials` via External Secrets Operator. The Deployment consumes it via `envFrom.secretRef`, so every key in the Vault path is injected as an env var with the same name — add or rename keys in Vault and the Deployment picks them up without a manifest change.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `DATABASE_CONNECTION_URI` | PostgreSQL connection string pointing to the `evolution` database on the cluster's `postgres-cluster` | `postgresql://evolution:<password>@postgres-cluster-rw.databases.svc.cluster.local:5432/evolution?schema=public` |
| `AUTHENTICATION_API_KEY` | Master API key used by clients to authenticate against every endpoint | `long-random-string` |

### Populating Vault

```bash
vault kv put secret/evolution-api \
  DATABASE_CONNECTION_URI='postgresql://evolution:your-evolution-db-password@postgres-cluster-rw.databases.svc.cluster.local:5432/evolution?schema=public' \
  AUTHENTICATION_API_KEY="$(openssl rand -hex 32)"
```

## Database

Evolution uses the cluster's shared **`postgres-cluster`** (CloudNativePG) in the `databases` namespace. The `evolution` user and `evolution` database must exist **before** the first pod starts — Evolution runs Prisma migrations on boot but does not create the role or database.

### Bootstrapping the database

```bash
EVOLUTION_PASS='your-evolution-db-password'
kubectl -n databases exec postgres-cluster-1 -c postgres -- psql -U postgres -v ON_ERROR_STOP=1 <<SQL
CREATE USER evolution WITH PASSWORD '${EVOLUTION_PASS}';
CREATE DATABASE evolution OWNER evolution;
GRANT ALL PRIVILEGES ON DATABASE evolution TO evolution;
SQL
```

The password set here must match the one embedded in `DATABASE_CONNECTION_URI` under `secret/evolution-api` in Vault.

## Non-sensitive environment variables

Deployment-level configuration that is not a secret lives directly in `manifests/deployment.yaml` under `containers[0].env`. Use this section for any plain Evolution env var that needs to be tuned per-environment (database behavior, cache toggles, log levels, session phone version, etc.). Sensitive values stay in Vault — see [Vault Secret](#vault-secret) above.

### Currently set

| Variable | Value | Purpose |
|----------|-------|---------|
| `SERVER_URL` | `https://evolution.nieri0x73.com` | Public base URL used by Evolution to build webhook and media URLs returned to clients |
| `DATABASE_PROVIDER` | `postgresql` | Selects the Prisma driver |
| `DATABASE_CONNECTION_CLIENT_NAME` | `evolution_v2` | Identifies this instance in the Postgres `application_name` field |
| `DATABASE_SAVE_DATA_*` / `BAILEYS_SYNC_FULL_HISTORY` | mixed | Trim what gets persisted — only instances/messages/updates are kept, contacts/chats and full history sync are disabled to keep the database small |
| `CONFIG_SESSION_PHONE_VERSION` | `2.3000.1023204200` | Pinned WhatsApp Web version reported on session start — bump when WhatsApp forces an upgrade |
| `CACHE_LOCAL_ENABLED` | `true` | Uses in-process cache instead of Redis, since no Redis is deployed |
| `LOG_LEVEL` | `INFO` | Default log verbosity |
| `QRCODE_LIMIT` | `10` | Maximum QR code regenerations before a session is considered failed |

For the full catalogue of Evolution env vars see the [official reference](https://doc.evolution-api.com/v2/en/env).

## Resources

| Knob | Value | Why |
|------|-------|-----|
| `requests.cpu` | `50m` | Matches idle CPU usage of a single-instance deployment without webhooks under load |
| `requests.memory` | `256Mi` | Covers the Node.js RSS plus the in-process cache at rest |
| `limits.cpu` | `500m` | Absorbs bursts during QR code generation, Baileys reconnects and message fan-out |
| `limits.memory` | `768Mi` | Leaves headroom over the working set for V8 GC and Baileys session buffers |

A single replica is enough — Evolution holds WhatsApp sessions in process, so horizontal scaling requires sticky routing and is not configured here. The Deployment uses `strategy: Recreate` so the old pod fully releases the session before the new one tries to claim it.

## Notes

- Image is pinned to `docker.io/evoapicloud/evolution-api:v2.3.7` — the OKE node image enforces fully qualified short names (see [OCI CRI-O short-name enforce note](../../../README.md)), so the registry prefix is required.
- Evolution stores WhatsApp session data in Postgres, not on disk — no PVC is mounted and pods are fully stateless from a Kubernetes perspective.
- Cache is in-process (`CACHE_LOCAL_ENABLED=true`). Switching to Redis later means adding a Redis dependency and flipping `CACHE_REDIS_ENABLED` plus the connection env vars in `deployment.yaml`.
