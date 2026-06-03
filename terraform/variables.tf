variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name."
}

variable "cluster_name" {
  type        = string
  description = "Logical cluster name used for naming."
}

variable "admin_username" {
  type        = string
  description = "Admin user created on each VM."
  default     = "azureuser"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key contents."
}

variable "vm_size" {
  type        = string
  description = "VM size for all nodes."
  default     = "Standard_B2s"
}

variable "vnet_cidr" {
  type        = string
  description = "Azure VNet CIDR."
  default     = "10.100.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "Azure subnet CIDR."
  default     = "10.100.0.0/24"
}

variable "k3s_cluster_cidr" {
  type        = string
  description = "K3s pod network CIDR."
  default     = "10.42.0.0/16"
}

variable "k3s_service_cidr" {
  type        = string
  description = "K3s service network CIDR."
  default     = "10.43.0.0/16"
}

variable "k3s_version" {
  type        = string
  description = "K3s version to install."
  default     = "v1.35.5+k3s1"
}

variable "container_runtime" {
  type        = string
  description = "Node container runtime profile for K3s. Supported values: containerd, crio, gvisor, kata."
  default     = "containerd"

  validation {
    condition     = contains(["containerd", "crio", "gvisor", "kata"], var.container_runtime)
    error_message = "container_runtime must be one of 'containerd', 'crio', 'gvisor', or 'kata'."
  }
}

variable "crio_version" {
  type        = string
  description = "CRI-O minor stream to install when container_runtime=crio, for example v1.35."
  default     = "v1.35"
}

variable "server_name" {
  type        = string
  description = "Control plane VM name."
  default     = "cp-0"
}

variable "worker_names" {
  type        = list(string)
  description = "Worker VM names."
  default     = ["worker-1", "worker-2"]
}

variable "ubuntu_image_sku" {
  type        = string
  description = "Ubuntu image SKU."
  default     = "22_04-lts"
}

variable "tags" {
  type        = map(string)
  description = "Azure tags."
  default = {
    managed-by = "terraform"
    workload   = "k3s"
  }
}
