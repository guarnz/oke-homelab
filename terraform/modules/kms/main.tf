resource "oci_kms_vault" "this" {
  compartment_id = var.compartment_id
  display_name   = "vault-unseal"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "vault_unseal" {
  compartment_id      = var.compartment_id
  display_name        = "vault-unseal-key"
  management_endpoint = oci_kms_vault.this.management_endpoint

  key_shape {
    algorithm = "AES"
    length    = 32
  }

  protection_mode = "HSM"
}

resource "oci_identity_dynamic_group" "oke_nodes" {
  compartment_id = var.compartment_id
  name           = "oke-nodes"
  description    = "OKE worker nodes for Vault KMS unseal"
  matching_rule  = "instance.compartment.id = '${var.compartment_id}'"
}

resource "oci_identity_policy" "vault_kms_unseal" {
  compartment_id = var.compartment_id
  name           = "vault-kms-unseal"
  description    = "Allow OKE nodes to use KMS key for Vault unseal"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to use keys in compartment id ${var.compartment_id} where target.key.id = '${oci_kms_key.vault_unseal.id}'"
  ]
}
