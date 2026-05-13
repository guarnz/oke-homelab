variable "compartment_id" {
  type        = string
  description = "OCI compartment OCID"
}

variable "region" {
  type        = string
  description = "OCI region"
}

variable "admin_public_ip" {
  type        = string
  description = "Admin public IP in CIDR notation for Kubernetes API access"
}
