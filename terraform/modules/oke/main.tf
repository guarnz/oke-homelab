resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "oci-free-k8s"
  vcn_id             = var.vcn_id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = var.public_subnet_id
  }

  options {
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
    service_lb_subnet_ids = [var.public_subnet_id]
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_containerengine_node_pool_option" "this" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

data "jq_query" "latest_image" {
  data  = jsonencode({ sources = jsondecode(jsonencode(data.oci_containerengine_node_pool_option.this.sources)) })
  query = "[.sources[] | select(.source_name | test(\".*aarch.*OKE-${replace(var.kubernetes_version, "v", "")}.*\")?) .image_id][0]"
}

resource "oci_containerengine_node_pool" "this" {
  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "oci-free-k8s-node-pool"

  node_metadata = {
    user_data = base64encode(file("${path.module}/../../files/node-pool-init.sh"))
  }

  node_config_details {
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = var.private_subnet_1_id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = var.private_subnet_2_id
    }
    size = var.kubernetes_worker_nodes
  }

  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    memory_in_gbs = 12
    ocpus         = 2
  }

  node_source_details {
    image_id                      = jsondecode(data.jq_query.latest_image.result)
    source_type                   = "image"
    boot_volume_size_in_gbs       = 100
    is_transit_encryption_enabled = true
  }

  initial_node_labels {
    key   = "name"
    value = "oci-free-k8s"
  }

  ssh_public_key = var.ssh_public_key
}


data "oci_containerengine_cluster_kube_config" "this" {
  cluster_id = oci_containerengine_cluster.this.id
}

resource "local_file" "kube_config" {
  depends_on      = [oci_containerengine_node_pool.this]
  content         = data.oci_containerengine_cluster_kube_config.this.content
  filename        = "${path.module}/../../.kube.config"
  file_permission = "0400"
}
