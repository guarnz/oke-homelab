variable "compartment_id" {
  type        = string
  description = "OCI compartment OCID"
}

variable "kubernetes_version" {
  type        = string
  description = "OKE Kubernetes version"
}

variable "kubernetes_worker_nodes" {
  type        = number
  description = "Number of worker nodes"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for node access"
}

variable "vcn_id" {
  type        = string
  description = "VCN ID from networking module"
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet ID for the cluster endpoint and load balancer"
}

variable "private_subnet_1_id" {
  type        = string
  description = "Private subnet ID for worker nodes (subnet 1)"
}

variable "private_subnet_2_id" {
  type        = string
  description = "Private subnet ID for worker nodes (subnet 2)"
}
