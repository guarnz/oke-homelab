# Vaultwarden

Password manager deployed via the [guerzon/vaultwarden](https://github.com/guerzon/vaultwarden) Helm chart.

## Access

| URL | Description |
|-----|-------------|
| `https://<your-domain>` | Vaultwarden vault |
| `https://<your-domain>/admin` | Admin panel |

The `manifests/` directory contains the Istio Gateway, VirtualService and cert-manager Certificate. Update the domain in these files to match your own FQDN before deploying.

## Vault Secret

All sensitive configuration is stored in HashiCorp Vault at path `secret/vaultwarden` and synced to the Kubernetes secret `vaultwarden-credentials` via External Secrets Operator.

### Required keys

| Key | Description | Example |
|-----|-------------|---------|
| `ADMIN_TOKEN` | Argon2 PHC hash for the admin panel. Generate with `vaultwarden hash --preset owasp` | `$argon2id$v=19$...` |

### SMTP

| Key | Description | Example |
|-----|-------------|---------|
| `SMTP_HOST` | SMTP server hostname | `smtp.example.com` |
| `SMTP_PORT` | SMTP port | `587` |
| `SMTP_SECURITY` | Encryption method (`starttls`, `force_tls`, `off`) | `starttls` |
| `SMTP_FROM` | Sender email address | `vault@example.com` |
| `SMTP_FROM_NAME` | Sender display name | `My Vaultwarden` |
| `SMTP_USERNAME` | SMTP authentication username | `vault@example.com` |
| `SMTP_PASSWORD` | SMTP password or app password | `your-smtp-password` |

### Zitadel SSO (OpenID Connect)

| Key | Description | Example |
|-----|-------------|---------|
| `SSO_ENABLED` | Enable SSO login | `true` |
| `SSO_CLIENT_ID` | Client ID issued by Zitadel | `123456789012345678@homelab` |
| `SSO_CLIENT_SECRET` | Client secret from Zitadel | `your-client-secret` |
| `SSO_AUTHORITY` | Zitadel issuer URL (the instance domain) | `https://<zitadel-domain>` |
| `SSO_SCOPES` | Additional OIDC scopes (optional) | `email profile` |
| `SSO_PKCE` | Use PKCE during auth flow (recommended) | `true` |

### Optional

| Key | Description | Example |
|-----|-------------|---------|
| `HIBP_API_KEY` | HaveIBeenPwned API key to check for breached passwords | `your-hibp-key` |
| `PUSH_ENABLED` | Enable mobile push notifications | `true` |
| `PUSH_INSTALLATION_ID` | Bitwarden installation ID for push notifications | `your-installation-id` |
| `PUSH_INSTALLATION_KEY` | Bitwarden installation key for push notifications | `your-installation-key` |

## Populating Vault

```bash
vault kv put secret/vaultwarden \
  ADMIN_TOKEN='$argon2id$...' \
  SMTP_HOST='smtp.example.com' \
  SMTP_PORT='587' \
  SMTP_SECURITY='starttls' \
  SMTP_FROM='vault@example.com' \
  SMTP_FROM_NAME='My Vaultwarden' \
  SMTP_USERNAME='vault@example.com' \
  SMTP_PASSWORD='your-smtp-password' \
  SSO_ENABLED='true' \
  SSO_CLIENT_ID='vaultwarden' \
  SSO_CLIENT_SECRET='your-client-secret' \
  SSO_AUTHORITY='https://<zitadel-domain>'
```

## Generating the Admin Token

Run inside the Vaultwarden pod:

```bash
kubectl exec -n apps -it $(kubectl get pod -n apps -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].metadata.name}') -- vaultwarden hash --preset owasp
```

Enter your desired admin password when prompted. Use the resulting `$argon2id$...` string as the `ADMIN_TOKEN` value in Vault.
