variable "tenancy_id" {
  type        = string
  description = "OCI tenancy OCID"
}

variable "compartment_id" {
  type        = string
  description = "OCI compartment (or tenancy) OCID where resources will be created"
}

variable "region" {
  type        = string
  description = "OCI region"
}

variable "kubernetes_version" {
  type        = string
  description = "OKE Kubernetes version — see https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutk8sversions.htm"
  default     = "v1.35.2"
}

variable "kubernetes_worker_nodes" {
  type        = number
  description = "Number of worker nodes in the node pool"
  default     = 2
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for node access"
}

variable "admin_public_ip" {
  type        = string
  description = "Your public IP in CIDR notation for Kubernetes API access (e.g. 1.2.3.4/32)"
}

variable "budget_alert_email" {
  type        = string
  description = "Email address to receive OCI budget alerts"
}

variable "budget_amount" {
  type        = number
  description = "Monthly budget limit in USD"
}
