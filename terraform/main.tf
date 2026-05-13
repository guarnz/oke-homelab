module "networking" {
  source = "./modules/networking"

  compartment_id  = var.compartment_id
  region          = var.region
  admin_public_ip = var.admin_public_ip
}

module "oke" {
  source = "./modules/oke"

  compartment_id          = var.compartment_id
  kubernetes_version      = var.kubernetes_version
  kubernetes_worker_nodes = var.kubernetes_worker_nodes
  ssh_public_key          = var.ssh_public_key
  vcn_id                  = module.networking.vcn_id
  public_subnet_id        = module.networking.public_subnet_id
  private_subnet_1_id     = module.networking.private_subnet_1_id
  private_subnet_2_id     = module.networking.private_subnet_2_id
}

module "budget" {
  source = "./modules/budget"

  compartment_id     = var.compartment_id
  budget_amount      = var.budget_amount
  budget_alert_email = var.budget_alert_email
}

module "kms" {
  source = "./modules/kms"

  compartment_id = var.compartment_id
  region         = var.region
}
