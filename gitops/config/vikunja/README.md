# Vikunja

Self-hosted task and project management app ([Vikunja](https://vikunja.io)) deployed as plain Kubernetes manifests reconciled by Kustomize. The single-binary image ships both the API and the web frontend, so no separate frontend deployment is needed.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | Vikunja web UI and API |

The `manifests/` directory contains the Istio Gateway, VirtualService and cert-manager Certificate. Update the domain in these files to match your own FQDN before deploying.

## Vault Secret

All sensitive configuration is stored in HashiCorp Vault at path `secret/vikunja` and synced to the Kubernetes secret `vikunja-credentials` via External Secrets Operator. The Deployment consumes it via `envFrom.secretRef`, so every key in the Vault path is injected as an env var with the same name — add or rename keys in Vault and the Deployment picks them up without a manifest change.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `VIKUNJA_SERVICE_SECRET` | JWT signing key for user sessions. Rotating it invalidates all logins | `$(openssl rand -hex 32)` |

### SMTP (optional — enables email, password reset and notifications)

| Key | Description | Example |
|-----|-------------|---------|
| `VIKUNJA_MAILER_ENABLED` | Turn the mailer on | `true` |
| `VIKUNJA_MAILER_HOST` | SMTP server hostname | `smtp.example.com` |
| `VIKUNJA_MAILER_PORT` | SMTP port | `587` |
| `VIKUNJA_MAILER_USERNAME` | SMTP authentication username | `mail@example.com` |
| `VIKUNJA_MAILER_PASSWORD` | SMTP password or app password | `your-smtp-password` |
| `VIKUNJA_MAILER_FROMEMAIL` | Sender email address | `planner@example.com` |

### Populating Vault

```bash
vault kv put secret/vikunja \
  VIKUNJA_SERVICE_SECRET="$(openssl rand -hex 32)" \
  VIKUNJA_MAILER_ENABLED='true' \
  VIKUNJA_MAILER_HOST='smtp.example.com' \
  VIKUNJA_MAILER_PORT='587' \
  VIKUNJA_MAILER_USERNAME='mail@example.com' \
  VIKUNJA_MAILER_PASSWORD='your-smtp-password' \
  VIKUNJA_MAILER_FROMEMAIL='planner@example.com'
```

## Storage

Vikunja stores everything in a local **SQLite** database — no external database is required. A single Longhorn PVC (`vikunja-data`, 1Gi, RWO) is mounted at both `/db` (the `vikunja.db` file) and `/files` (user attachments). Because the volume is `ReadWriteOnce` the Deployment is pinned to one replica with `strategy: Recreate` so the old pod releases the volume before the new one claims it.

## Non-sensitive environment variables

Deployment-level configuration that is not a secret lives directly in `manifests/deployment.yaml` under `containers[0].env`. Sensitive values stay in Vault — see [Vault Secret](#vault-secret) above.

### Currently set

| Variable | Value | Purpose |
|----------|-------|---------|
| `VIKUNJA_SERVICE_PUBLICURL` | `https://<your-domain>` | Public base URL used for CORS and links in outgoing emails |
| `VIKUNJA_SERVICE_INTERFACE` | `:3456` | Listen address inside the container |
| `VIKUNJA_SERVICE_ENABLEREGISTRATION` | `false` | Disables public self-registration — create the single user manually |
| `VIKUNJA_SERVICE_TIMEZONE` | `America/Sao_Paulo` | Timezone for reminders and due dates |
| `VIKUNJA_DATABASE_TYPE` | `sqlite` | Selects the local SQLite backend |
| `VIKUNJA_DATABASE_PATH` | `/db/vikunja.db` | SQLite file location on the mounted PVC |
| `VIKUNJA_FILES_BASEPATH` | `/files` | Where uploaded attachments are stored on the PVC |

For the full catalogue of config options see the [official reference](https://vikunja.io/docs/config-options/).

## Post-Deploy Configuration

With registration disabled, create the first (and only) account from the CLI inside the running pod:

```bash
kubectl exec -n apps -it deploy/vikunja -- \
  /app/vikunja/vikunja user create -u <username> -e <email> -p <password>
```

Then log in at `https://<your-domain>`.

## Notes

- Image is pinned to `docker.io/vikunja/vikunja:0.24.6` — the OKE node image enforces fully qualified short names (see [OCI CRI-O short-name enforce note](../../../README.md)), so the registry prefix is required.
- `VIKUNJA_SERVICE_JWTSECRET` is deprecated upstream in favour of `VIKUNJA_SERVICE_SECRET`; only the latter is used here.
