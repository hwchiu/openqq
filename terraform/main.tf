locals {
  node_names = concat([var.server_name], var.worker_names)
}

resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.cluster_name}"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  name                 = "snet-${var.cluster_name}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidr]
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-${var.cluster_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "allow-ssh"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this.name
}

resource "azurerm_network_security_rule" "k8s_api" {
  name                        = "allow-k8s-api"
  priority                    = 1010
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this.name
}

resource "azurerm_network_security_rule" "nodeport" {
  name                        = "allow-nodeport"
  priority                    = 1020
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "30000-32767"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this.name
}

resource "azurerm_public_ip" "nodes" {
  for_each            = toset(local.node_names)
  name                = "${each.key}-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "nodes" {
  for_each            = toset(local.node_names)
  name                = "${each.key}-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.nodes[each.key].id
  }
}

resource "azurerm_network_interface_security_group_association" "nodes" {
  for_each                  = toset(local.node_names)
  network_interface_id      = azurerm_network_interface.nodes[each.key].id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_linux_virtual_machine" "server" {
  name                            = var.server_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nodes[var.server_name].id]
  tags                            = merge(var.tags, { role = "control-plane" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = var.ubuntu_image_sku
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init-server.yaml.tftpl", {
    k3s_version    = var.k3s_version
    k3s_token      = random_password.k3s_token.result
    public_ip      = azurerm_public_ip.nodes[var.server_name].ip_address
    cluster_cidr   = var.k3s_cluster_cidr
    service_cidr   = var.k3s_service_cidr
    admin_username = var.admin_username
  }))
}

resource "azurerm_linux_virtual_machine" "workers" {
  for_each                        = toset(var.worker_names)
  name                            = each.key
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nodes[each.key].id]
  tags                            = merge(var.tags, { role = "worker" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = var.ubuntu_image_sku
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init-agent.yaml.tftpl", {
    k3s_version    = var.k3s_version
    k3s_token      = random_password.k3s_token.result
    server_private = azurerm_network_interface.nodes[var.server_name].private_ip_address
    admin_username = var.admin_username
  }))

  depends_on = [azurerm_linux_virtual_machine.server]
}
