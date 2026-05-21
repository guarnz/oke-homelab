# Zitadel

Identity and Access Management deployed via the [zitadel](https://charts.zitadel.com) Helm chart. Provides SSO (Single Sign-On) for all cluster applications via OpenID Connect.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | Zitadel Console |
| `https://<your-domain>/ui/console` | Admin console |

The `manifests/` directory contains the Istio Gateway, VirtualService and cert-manager Certificate. Update the domain in these files to match your own FQDN before deploying.

## Vault Secret

All sensitive configuration is stored in HashiCorp Vault at path `secret/zitadel` and synced to the Kubernetes secret `zitadel-credentials` via External Secrets Operator. The same secret is consumed by both the Zitadel server (`masterkey` and database env vars) and the bundled Bitnami PostgreSQL subchart (`existingSecret`).

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `masterkey` | Encryption key used to seal events and tokens — must be exactly 32 characters and never changed after first install | `32-char-random-alphanumeric` |
| `postgres-password` | Password of the external `postgres` superuser in `postgres-cluster` — used by Zitadel for migrations. Must match the value stored in the `postgres-credentials` secret under the `databases` namespace | `same-as-postgres-cluster-superuser` |
| `password` | Password of the `zitadel` application user in the external `postgres-cluster` — used by Zitadel at runtime. Must match the password configured on the role when it was created | `your-zitadel-db-password` |
| `admin-password` | Initial password for the first human admin user. Must be changed on first login (`PasswordChangeRequired: true`) | `your-initial-admin-password` |

### Populating Vault

```bash
vault kv put secret/zitadel \
  masterkey="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)" \
  postgres-password='your-postgres-admin-password' \
  password='your-zitadel-db-password' \
  admin-password='your-initial-admin-password'
```

> The vault-bootstrap.sh script handles Vault initialization and Kubernetes auth setup. Run it before populating the secrets above.

## Initial Admin User

The first instance is created automatically by the chart on bootstrap, using the user defined in `values.yaml` under `zitadel.configmapConfig.FirstInstance.Org.Human`. The initial password is sourced from the `admin-password` key in `zitadel-credentials` and password change is required on first login.

The auto-generated login name follows the pattern `<UserName>@<OrgName>.<ExternalDomain>` — for example `admin@nieri0x73.iam.nieri0x73.com`. The contact email defined under `Email.Address` is separate from the login name and can later be enabled as an alternative login method in the Login Policy.

Sign in at `https://<your-domain>` with the generated login name and the password stored in Vault.

## Post-Deploy Configuration

After Zitadel is running, configure the following via the admin console.

### 1. OIDC Applications

Each application that should use SSO is registered as an Application inside a Project in Zitadel:

1. Navigate to **Projects → Create new project** (e.g. `homelab`)
2. Inside the project, **Applications → New**, then for each app:
   - **Type:** Web (for ArgoCD, n8n, Vaultwarden)
   - **Authentication Method:** Code + PKCE (or `Basic Auth` if the client cannot do PKCE)
   - **Redirect URI** per app:

| Application | Redirect URI |
|-------------|--------------|
| ArgoCD | `https://<argocd-domain>/auth/callback` |
| n8n | `https://<n8n-domain>/rest/sso/oauth2/callback` |
| Vaultwarden | `https://<vaultwarden-domain>/identity/connect/oidc-signin` |

After creating each application, copy:
- **Client ID**
- **Client Secret** (shown only once; if you regenerate, the previous one is invalidated)
- **Issuer URL**: `https://<your-domain>` (Zitadel uses the instance domain as the OIDC issuer)

These values feed into the consuming app's Vault path (see each app's README).

### 2. GitHub Social Login

Add GitHub as an Identity Provider so users can sign in with their GitHub account:

1. Create an OAuth App on GitHub: **Settings → Developer Settings → OAuth Apps → New OAuth App**
   - **Homepage URL**: `https://<your-domain>`
   - **Callback URL**: `https://<your-domain>/ui/login/login/externalidp/callback`
2. In Zitadel Console: **Instance → Identity Providers → New → GitHub**
   - Paste **Client ID** and **Client Secret** from GitHub
   - **Scopes**: leave default (`openid`, `profile`, `email`)
3. Activate the IdP on the default Login Policy: **Instance → Login Policy → Identity Providers → Add**

When `autoRegister` is enabled on the IdP, the first GitHub login provisions a matching Zitadel user automatically.

## Database

Zitadel uses the cluster's shared **`postgres-cluster`** (CloudNativePG) in the `databases` namespace as its database. The bundled Bitnami PostgreSQL subchart is disabled (`postgresql.enabled: false`). Connection target:

```
postgres-cluster-rw.databases.svc.cluster.local:5432
```

### Bootstrapping the database

The `zitadel` user and `zitadel` database must exist in `postgres-cluster` **before** the chart runs its setup Job — Zitadel does not create them, and the `postgres` superuser is only used for migrations. Pick whichever style fits your workflow:

#### Inline (one-off, via psql)

Run once against the cluster:

```bash
ZITADEL_PASS=$(kubectl -n security get secret zitadel-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl -n databases exec postgres-cluster-1 -c postgres -- psql -U postgres -v ON_ERROR_STOP=1 <<SQL
CREATE USER zitadel WITH PASSWORD '${ZITADEL_PASS}';
CREATE DATABASE zitadel OWNER zitadel;
GRANT ALL PRIVILEGES ON DATABASE zitadel TO zitadel;
SQL
```

The password set here must match the `password` key in Vault `secret/zitadel`.

#### Declarative (GitOps, via CNPG `Database` CR)

If you'd rather keep the bootstrap in the repo, add a `Database` resource under `gitops/config/postgres/manifests/` so ArgoCD reconciles it alongside `postgres-cluster`. The CRD is documented at <https://cloudnative-pg.io/documentation/current/declarative_database_management/>.

Either approach is fine — the inline form is faster for the first install, the declarative form survives full cluster rebuilds.

## Notes

- Configuration is split between the ConfigMap (`zitadel.configmapConfig`, non-sensitive) and environment variables sourced from `zitadel-credentials` (sensitive — database passwords and admin bootstrap password).
- The `postgres-password` in Vault must match the superuser password of `postgres-cluster` (the same value stored in `secret/postgres`). Without this, the chart's setup Job cannot run migrations.
- Losing `masterkey` means losing access to all encrypted data in the database. Back it up alongside the Vault unseal/recovery keys.
