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
  default     = "eastus"
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

variable "k3s_version" {
  type        = string
  description = "K3s version to install."
  default     = "v1.34.1+k3s1"
}

variable "crio_version" {
  type        = string
  description = "CRI-O minor stream to install."
  default     = "v1.34"
}

variable "ubuntu_image_sku" {
  type        = string
  description = "Ubuntu image SKU."
  default     = "22_04-lts"
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
