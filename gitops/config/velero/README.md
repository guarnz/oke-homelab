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

The `manifests/` directory contains the External Secret that hydrates the `velero-credentials` Kubernetes secret from Vault.

> **OCI Free Tier limit — Object Storage caps at 20 GB Standard storage across the tenancy.** Anything above is billed at the standard per-GB rate. Keep backup retention bounded with `--ttl` on schedules (e.g. `--ttl 168h` for a rolling 7-day window) and prefer incremental backups via Kopia (already enabled by `uploaderType: kopia`) so the bucket stays comfortably below the free quota. Monitor usage with `oci os bucket get-bucket --bucket-name <bucket> --fields approximateSize`.

## Vault Secret

The S3-compatible credential is stored in HashiCorp Vault at path `secret/velero` and synced to the Kubernetes secret `velero-credentials` via External Secrets Operator.

### Required keys

| Key | Description | Format |
|-----|-------------|--------|
| `cloud` | AWS-style credentials profile consumed by `velero-plugin-for-aws` | Multi-line INI |

### `cloud` value format

```ini
[default]
aws_access_key_id=<oci-customer-secret-key-access-key>
aws_secret_access_key=<oci-customer-secret-key-secret-key>
```

Generate the access/secret key pair from the OCI Console under **My profile → Customer Secret Keys → Generate Secret Key**. The secret value is shown only once at creation time.

### Populating Vault

```bash
vault kv put secret/velero \
  cloud='[default]
aws_access_key_id=<access-key>
aws_secret_access_key=<secret-key>'
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
