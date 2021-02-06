variable env               {}
variable rg_location       {}
variable rg_name           {}
variable subnetEgressCidr  {}
variable subnetEgressId    {}


locals {
    name                              = replace("ubuntu-${var.env}", "_", "-")
}


resource "azurerm_storage_account" "ubuntu" {
    name                              = "pmack${replace(var.env, "_", "")}"
    resource_group_name               = var.rg_name
    location                          = var.rg_location
    account_replication_type          = "LRS"
    account_tier                      = "Standard"
    enable_https_traffic_only         = true
}


resource "azurerm_network_interface" "ubuntu" {
    name                              = "${local.name}-in"
    location                          = var.rg_location
    resource_group_name               = var.rg_name

    ip_configuration {
        name                          = "config"
        private_ip_address_allocation = "Static"
        private_ip_address            = cidrhost(var.subnetEgressCidr, 4)
        subnet_id                     = var.subnetEgressId
    }
}


resource "azurerm_linux_virtual_machine" "ubuntu" {
    name                              = local.name
    resource_group_name               = var.rg_name
    location                          = var.rg_location
    size                              = "Standard_B2ms"
    admin_username                    = "adminuser"
    admin_password                    = "$loppy0ats!"
    disable_password_authentication   = false
    network_interface_ids             = [azurerm_network_interface.ubuntu.id]

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
