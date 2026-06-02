output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "control_plane_public_ip" {
  value = azurerm_public_ip.nodes[var.server_name].ip_address
}

output "control_plane_private_ip" {
  value = azurerm_network_interface.nodes[var.server_name].private_ip_address
}

output "worker_public_ips" {
  value = {
    for name in var.worker_names : name => azurerm_public_ip.nodes[name].ip_address
  }
}

output "kubeconfig_fetch_command" {
  value = "scp -o StrictHostKeyChecking=no ${var.admin_username}@${azurerm_public_ip.nodes[var.server_name].ip_address}:/etc/rancher/k3s/k3s.yaml ./generated/kubeconfig.raw"
}

output "ssh_commands" {
  value = {
    for name in local.node_names : name => "ssh ${var.admin_username}@${azurerm_public_ip.nodes[name].ip_address}"
  }
}

