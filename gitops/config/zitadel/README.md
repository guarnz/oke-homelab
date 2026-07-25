# Zitadel

Identity and Access Management deployed via the [zitadel](https://charts.zitadel.com) Helm chart. Provides SSO (Single Sign-On) for all cluster applications via OpenID Connect.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | Zitadel Console |
| `https://<your-domain>/ui/console` | Admin console |

The chart in this directory renders the Istio Gateway, VirtualService, cert-manager Certificate and the ExternalSecret. The public hostname is built from `subdomain` (in `local-values.yaml`) and `global.domain` (in `gitops/global-values.yaml`), so no FQDN is hard-coded here — set your domain once in `global-values.yaml`.

## Vault Secret

All sensitive and identity configuration is stored in HashiCorp Vault at path `secret/zitadel` and synced to the Kubernetes secret `zitadel-credentials` via External Secrets Operator. The secret is consumed three ways: the chart injects `masterkey` via `masterkeySecretName`, loads every other key as an environment variable via `envVarsSecret`, and the same keys back the database bootstrap. Because injection uses `envVarsSecret`, most keys are named exactly as the ZITADEL environment variable they set — so no domain, email or password ever appears in the repository.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `masterkey` | Encryption key used to seal events and tokens — must be exactly 32 characters and never changed after first install (chart reads this fixed key name) | `32-char-random-alphanumeric` |
| `ZITADEL_EXTERNALDOMAIN` | Public FQDN of the instance — must match `<subdomain>.<global.domain>` | `iam.<your-domain>` |
| `ZITADEL_FIRSTINSTANCE_ORG_HUMAN_EMAIL_ADDRESS` | Contact email of the first admin user | `admin@<your-domain>` |
| `ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD` | Password of the `postgres` superuser in `postgres-cluster` — used for migrations. Must match `secret/postgres` | `same-as-postgres-cluster-superuser` |
| `ZITADEL_DATABASE_POSTGRES_USER_PASSWORD` | Password of the `zitadel` application user at runtime. Must match the role created in `postgres-cluster` | `your-zitadel-db-password` |
| `ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD` | Initial password for the first admin user — change required on first login | `your-initial-admin-password` |

### Populating Vault

```bash
vault kv put secret/zitadel \
  masterkey="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)" \
  ZITADEL_EXTERNALDOMAIN='iam.<your-domain>' \
  ZITADEL_FIRSTINSTANCE_ORG_HUMAN_EMAIL_ADDRESS='admin@<your-domain>' \
  ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD='your-postgres-admin-password' \
  ZITADEL_DATABASE_POSTGRES_USER_PASSWORD='your-zitadel-db-password' \
  ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD='your-initial-admin-password'
```

> The vault-bootstrap.sh script handles Vault initialization and Kubernetes auth setup. Run it before populating the secrets above.

## Initial Admin User

The first instance is created automatically by the chart on bootstrap. The non-sensitive user attributes live in `values.yaml` under `zitadel.configmapConfig.FirstInstance.Org.Human`, while the admin email and initial password come from Vault (`ZITADEL_FIRSTINSTANCE_ORG_HUMAN_EMAIL_ADDRESS`, `ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD`). Password change is required on first login.

The organization name is left unset, so ZITADEL uses its default first-organization name. The auto-generated login name follows the pattern `<UserName>@<OrgName>.<ExternalDomain>`; rename the organization in the Console after first login if you want a cleaner login name. The contact email is separate from the login name and can later be enabled as an alternative login method in the Login Policy.

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
ZITADEL_PASS=$(kubectl -n security get secret zitadel-credentials -o jsonpath='{.data.ZITADEL_DATABASE_POSTGRES_USER_PASSWORD}' | base64 -d)
kubectl -n databases exec postgres-cluster-1 -c postgres -- psql -U postgres -v ON_ERROR_STOP=1 <<SQL
CREATE USER zitadel WITH PASSWORD '${ZITADEL_PASS}';
CREATE DATABASE zitadel OWNER zitadel;
GRANT ALL PRIVILEGES ON DATABASE zitadel TO zitadel;
SQL
```

The password set here must match the `ZITADEL_DATABASE_POSTGRES_USER_PASSWORD` key in Vault `secret/zitadel`.

#### Declarative (GitOps, via CNPG `Database` CR)

If you'd rather keep the bootstrap in the repo, add a `Database` resource under `gitops/config/postgres/manifests/` so ArgoCD reconciles it alongside `postgres-cluster`. The CRD is documented at <https://cloudnative-pg.io/documentation/current/declarative_database_management/>.

Either approach is fine — the inline form is faster for the first install, the declarative form survives full cluster rebuilds.

## Notes

- Configuration is split between the ConfigMap (`zitadel.configmapConfig`, non-sensitive static settings) and environment variables injected from `zitadel-credentials` via `envVarsSecret` (domain, email and passwords). Keys consumed through `envVarsSecret` are named exactly as their ZITADEL environment variable, so nothing sensitive or environment-specific is stored in the repository.
- The `ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD` in Vault must match the superuser password of `postgres-cluster` (the same value stored in `secret/postgres`). Without this, the chart's setup Job cannot run migrations.
- Losing `masterkey` means losing access to all encrypted data in the database. Back it up alongside the Vault unseal/recovery keys.
