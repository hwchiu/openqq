locals {
  tags = {
    managed-by = "terraform"
    workload   = "k3s"
    scenario   = "k3s-gvisor-134"
  }
}

module "cluster" {
  source = "../.."

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  location        = var.location
  admin_username  = var.admin_username
  ssh_public_key  = var.ssh_public_key

  resource_group_name = "rg-k3s-gvisor-134"
  cluster_name        = "k3s-gvisor-134"
  vm_size             = "Standard_B2s"
  vnet_cidr           = "10.160.0.0/16"
  subnet_cidr         = "10.160.0.0/24"
  k3s_cluster_cidr    = "10.60.0.0/16"
  k3s_service_cidr    = "10.61.0.0/16"
  k3s_version         = var.k3s_version
  container_runtime   = "crio"
  crio_version        = var.crio_version
  ubuntu_image_sku    = var.ubuntu_image_sku
  server_name         = var.server_name
  worker_names        = var.worker_names
  tags                = local.tags
}
