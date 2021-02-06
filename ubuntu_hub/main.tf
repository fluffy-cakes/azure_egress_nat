variable env               {}
variable nsg               {}
variable rg_location       {}
variable rg_name           {}
variable subnetEgressCidr  {}
variable subnetEgressId    {}
variable subnetIngressCidr {}
variable subnetIngressId   {}


locals {
    name                              = replace("ubuntu-${var.env}", "_", "-")
}

resource "azurerm_lb" "lb" {
    name                              = local.name
    location                          = var.rg_location
    resource_group_name               = var.rg_name
    sku                               = "Standard"

    frontend_ip_configuration {
        name                          = "frontend"
        private_ip_address            = cidrhost(var.subnetIngressCidr, 5)
        private_ip_address_allocation = "Static"
        subnet_id                     = var.subnetIngressId
    }
}


resource "azurerm_lb_backend_address_pool" "lb" {
    name                              = "backend"
    resource_group_name               = var.rg_name
    loadbalancer_id                   = azurerm_lb.lb.id
}


resource "azurerm_lb_probe" "lb" {
    name                              = "ssh"
    resource_group_name               = var.rg_name
    loadbalancer_id                   = azurerm_lb.lb.id
    port                              = 22
}


resource "azurerm_lb_rule" "lb" {
    name                              = "ha"
    resource_group_name               = var.rg_name
    backend_address_pool_id           = azurerm_lb_backend_address_pool.lb.id
    backend_port                      = 0
    frontend_ip_configuration_name    = "frontend"
    frontend_port                     = 0
    loadbalancer_id                   = azurerm_lb.lb.id
    probe_id                          = azurerm_lb_probe.lb.id
    protocol                          = "All"
}


resource "azurerm_storage_account" "ubuntu" {
    name                              = "pmack${replace(var.env, "_", "")}"
    resource_group_name               = var.rg_name
    location                          = var.rg_location
    account_replication_type          = "LRS"
    account_tier                      = "Standard"
    enable_https_traffic_only         = true
}


resource "azurerm_network_interface" "ubuntu_in" {
    name                              = "${local.name}-in"
    location                          = var.rg_location
    resource_group_name               = var.rg_name
    enable_ip_forwarding              = true

    ip_configuration {
        name                          = "config"
        private_ip_address_allocation = "Static"
        private_ip_address            = cidrhost(var.subnetIngressCidr, 4)
        subnet_id                     = var.subnetIngressId
    }
}


resource "azurerm_network_interface_security_group_association" "ubuntu_in" {
    network_interface_id              = azurerm_network_interface.ubuntu_in.id
    network_security_group_id         = var.nsg
}


resource "azurerm_network_interface_backend_address_pool_association" "ubuntu_in" {
    backend_address_pool_id           = azurerm_lb_backend_address_pool.lb.id
    ip_configuration_name             = "config"
    network_interface_id              = azurerm_network_interface.ubuntu_in.id
}


resource "azurerm_public_ip" "ubuntu" {
    name                              = local.name
    resource_group_name               = var.rg_name
    location                          = var.rg_location
    allocation_method                 = "Static"
    sku                               = "Standard"
}


resource "azurerm_network_interface" "ubuntu_out" {
    name                              = "${local.name}-out"
    location                          = var.rg_location
    resource_group_name               = var.rg_name

    ip_configuration {
        name                          = "config"
        private_ip_address_allocation = "Static"
        private_ip_address            = cidrhost(var.subnetEgressCidr, 4)
        public_ip_address_id          = azurerm_public_ip.ubuntu.id
        subnet_id                     = var.subnetEgressId
    }
}


data "template_file" "routing" {
    template                          = file("${path.module}/routing.sh")
}


locals {
    base64_template                  = base64encode(data.template_file.routing.rendered)
}


resource "azurerm_linux_virtual_machine" "ubuntu" {
    name                              = local.name
    resource_group_name               = var.rg_name
    location                          = var.rg_location
    size                              = "Standard_B2ms"
    admin_username                    = "adminuser"
    admin_password                    = "$loppy0ats!"
    custom_data                       = local.base64_template
    disable_password_authentication   = false
    network_interface_ids             = [
        azurerm_network_interface.ubuntu_out.id,
        azurerm_network_interface.ubuntu_in.id
    ]

    boot_diagnostics {
        storage_account_uri           = azurerm_storage_account.ubuntu.primary_blob_endpoint
    }

    os_disk {
        caching                       = "ReadWrite"
        storage_account_type          = "Standard_LRS"
    }

    source_image_reference {
        publisher                     = "Canonical"
        offer                         = "0001-com-ubuntu-server-focal"
        sku                           = "20_04-lts"
        version                       = "latest"
    }
}


output lb_ip {
    value                             = azurerm_lb.lb.frontend_ip_configuration[0].private_ip_address
}