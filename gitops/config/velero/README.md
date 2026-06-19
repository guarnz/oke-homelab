# Velero

Cluster backup and disaster recovery deployed via the [vmware-tanzu/velero](https://github.com/vmware-tanzu/helm-charts/tree/main/charts/velero) Helm chart.

Backups are written to an OCI Object Storage bucket through the AWS S3-compatible endpoint, using the [velero-plugin-for-aws](https://github.com/vmware-tanzu/velero-plugin-for-aws).

## Backup target

| Field | Value |
|-------|-------|
| Bucket | `<your-bucket-name>` |
| Region | `<your-oci-region>` |
| S3 endpoint | `https://<your-namespace>.compat.objectstorage.<your-oci-region>.oraclecloud.com` |
| Path style | `s3ForcePathStyle: true` (required for OCI S3 compat) |

Update `bucket`, `config.region` and `config.s3Url` in `values.yaml` to match your tenancy. The Object Storage namespace can be retrieved with `oci os ns get`.

Velero is installed in the `backup` namespace. The `manifests/` directory contains two `ExternalSecret` resources that both consume the same Vault path (`secret/velero`) and hydrate two Kubernetes secrets that Velero looks up under fixed names: `velero-credentials` (bucket access) and `velero-repo-credentials` (Kopia repository encryption password).

> **OCI Free Tier limit — Object Storage caps at 20 GB Standard storage across the tenancy.** Anything above is billed at the standard per-GB rate. Keep backup retention bounded with `--ttl` on schedules (e.g. `--ttl 168h` for a rolling 7-day window) and prefer incremental backups via Kopia (already enabled by `uploaderType: kopia`) so the bucket stays comfortably below the free quota. Monitor usage with `oci os bucket get-bucket --bucket-name <bucket> --fields approximateSize`.

## Vault Secret

> **Populate Vault before syncing this app.** The two `ExternalSecret` resources fail to reconcile until `secret/velero` exists in Vault with both required keys (`cloud` and `repository-password`). If Velero starts and runs its first backup before `velero-repo-credentials` is hydrated, it generates its own random Kopia password — pinning a stable one afterwards is no longer possible without wiping the bucket. Populate Vault first, then let ArgoCD sync.

All Velero credentials live in HashiCorp Vault at a single path: `secret/velero`. Two `ExternalSecret` resources read from this path and produce two distinct Kubernetes secrets that Velero looks up by fixed names.

### Required keys

| Key | Used by | Description | Format |
|-----|---------|-------------|--------|
| `cloud` | `velero-credentials` Kubernetes secret | AWS-style credentials profile consumed by `velero-plugin-for-aws` to authenticate against the OCI Object Storage S3-compatible endpoint | Multi-line INI |
| `repository-password` | `velero-repo-credentials` Kubernetes secret | Passphrase used by Kopia to encrypt every block written to the backup bucket. Treat as long-lived — losing it makes existing backups unrestorable | Random string (32+ chars) |

### `cloud` value format

```ini
[default]
aws_access_key_id=<oci-customer-secret-key-access-key>
aws_secret_access_key=<oci-customer-secret-key-secret-key>
```

Generate the access/secret key pair from the OCI Console under **My profile → Customer Secret Keys → Generate Secret Key**. The secret value is shown only once at creation time.

### `repository-password` value format

Any high-entropy string. Generate with:

```bash
openssl rand -base64 32
```

### Populating Vault

```bash
vault kv put secret/velero \
  cloud='[default]
aws_access_key_id=<access-key>
aws_secret_access_key=<secret-key>' \
  repository-password="$(openssl rand -base64 32)"
```

After the first successful backup, also export the rendered Kubernetes secret to an offline location (or a second Vault path) so the Kopia password can be recovered in a full disaster-recovery scenario where Vault itself has to be restored from a Velero backup:

```bash
kubectl -n backup get secret velero-repo-credentials \
  -o jsonpath='{.data.repository-password}' | base64 -d
```

## Volume backups

Filesystem-level backups of Persistent Volumes are enabled via the Kopia uploader (`uploaderType: kopia`). The node-agent DaemonSet (`deployNodeAgent: true`) runs on every node and streams PV contents into the Object Storage bucket — no CSI snapshot support is required, which keeps the setup portable between Longhorn and the OCI Block Volume CSI driver during the storage class migration.

Volume snapshots are disabled (`snapshotsEnabled: false`) because OCI Block Volume snapshots are not used as the backup transport.

`defaultVolumesToFsBackup: true` means every PV attached to a backed-up pod is included unless explicitly opted out via the `backup.velero.io/backup-volumes-excludes` annotation on the pod.

## Common operations

### Trigger an on-demand backup

```bash
velero backup create pre-migration \
  --include-namespaces apps,databases,security \
  --wait
```

### List backups

```bash
velero backup get
```

### Restore from a backup

```bash
velero restore create --from-backup pre-migration --wait
```

### Schedule a daily backup at 03:00

```bash
velero schedule create daily-full \
  --schedule="0 3 * * *" \
  --include-namespaces apps,databases,security \
  --ttl 168h
```

## Resources

| Component | CPU request | Memory request | Memory limit |
|-----------|-------------|----------------|--------------|
| Velero server | `50m` | `128Mi` | `384Mi` |
| Node agent (per node) | `50m` | `128Mi` | `512Mi` |

Sized for the free-tier OKE cluster — bump the node-agent memory limit if Kopia OOMs while streaming large volumes.
