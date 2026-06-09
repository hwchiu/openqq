locals {
  tags = {
    managed-by = "terraform"
    workload   = "k3s"
    scenario   = "k3s-gvisor"
  }
}

module "cluster" {
  source = "../.."

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  location        = var.location
  admin_username  = var.admin_username
  ssh_public_key  = var.ssh_public_key

  resource_group_name = "rg-k3s-gvisor"
  cluster_name        = "k3s-gvisor"
  vm_size             = "Standard_B2s"
  vnet_cidr           = "10.110.0.0/16"
  subnet_cidr         = "10.110.0.0/24"
  k3s_cluster_cidr    = "10.210.0.0/16"
  k3s_service_cidr    = "10.211.0.0/16"
  k3s_version         = var.k3s_version
  container_runtime   = "crio"
  crio_version        = var.crio_version
  ubuntu_image_sku    = var.ubuntu_image_sku
  server_name         = var.server_name
  worker_names        = var.worker_names
  tags                = local.tags
}
