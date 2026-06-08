output "stack_name" {
  value = basename(path.cwd)
}

output "admin_username" {
  value = var.admin_username
}

output "resource_group_name" {
  value = module.cluster.resource_group_name
}

output "control_plane_public_ip" {
  value = module.cluster.control_plane_public_ip
}

output "control_plane_private_ip" {
  value = module.cluster.control_plane_private_ip
}

output "worker_public_ips" {
  value = module.cluster.worker_public_ips
}

output "kubeconfig_fetch_command" {
  value = module.cluster.kubeconfig_fetch_command
}

output "ssh_commands" {
  value = module.cluster.ssh_commands
}
