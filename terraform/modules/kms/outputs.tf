output "vault_kms_key_id" {
  value       = oci_kms_key.vault_unseal.id
  description = "OCID of the KMS key used for Vault unseal"
}

output "vault_kms_crypto_endpoint" {
  value       = oci_kms_vault.this.crypto_endpoint
  description = "KMS crypto endpoint for Vault unseal"
}

output "vault_kms_management_endpoint" {
  value       = oci_kms_vault.this.management_endpoint
  description = "KMS management endpoint"
}
