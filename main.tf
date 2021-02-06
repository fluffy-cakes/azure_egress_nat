provider "azurerm" {
    features {}
}



# resource groups
resource "azurerm_resource_group" "uks_hub" {
    name                          = "uks_hub"
    location                      = "uksouth"
}

resource "azurerm_resource_group" "uks_spoke" {
    name                          = "uks_spoke"
    location                      = "uksouth"
}



# network security groups
resource "azurerm_network_security_group" "uks_hub_egress" {
    name                          = "uks_hub_egress"
    location                      = azurerm_resource_group.uks_hub.location
    resource_group_name           = azurerm_resource_group.uks_hub.name
}

resource "azurerm_network_security_group" "uks_hub_ingress" {
    name                          = "uks_hub_ingress"
    location                      = azurerm_resource_group.uks_hub.location
    resource_group_name           = azurerm_resource_group.uks_hub.name
}


resource "azurerm_network_security_group" "uks_spoke_egress" {
    name                          = "uks_spoke_egress"
    location                      = azurerm_resource_group.uks_spoke.location
    resource_group_name           = azurerm_resource_group.uks_spoke.name
}



# vnet hub
resource "azurerm_virtual_network" "uks_hub" {
    name                          = "uks_hub"
    location                      = azurerm_resource_group.uks_hub.location
    resource_group_name           = azurerm_resource_group.uks_hub.name
    address_space                 = ["10.0.0.0/23"]
}

resource "azurerm_subnet" "uks_hub_subnetEgress" {
    name                          = "subnetEgress"
    resource_group_name           = azurerm_virtual_network.uks_hub.resource_group_name
    virtual_network_name          = azurerm_virtual_network.uks_hub.name
    address_prefixes              = ["10.0.0.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "uks_hub_subnetEgress" {
    subnet_id                     = azurerm_subnet.uks_hub_subnetEgress.id
    network_security_group_id     = azurerm_network_security_group.uks_hub_egress.id
}

resource "azurerm_subnet" "uks_hub_subnetHub" {
    name                          = "subnetHub"
    resource_group_name           = azurerm_virtual_network.uks_hub.resource_group_name
    virtual_network_name          = azurerm_virtual_network.uks_hub.name
    address_prefixes              = ["10.0.1.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "uks_hub_subnetHub" {
    subnet_id                     = azurerm_subnet.uks_hub_subnetHub.id
    network_security_group_id     = azurerm_network_security_group.uks_hub_ingress.id
}



# vnet spoke
resource "azurerm_virtual_network" "uks_spoke" {
    name                          = "uks_spoke"
    location                      = azurerm_resource_group.uks_spoke.location
    resource_group_name           = azurerm_resource_group.uks_spoke.name
    address_space                 = ["10.0.2.0/23"]
}

resource "azurerm_subnet" "uks_spoke_subnetEgress" {
    name                          = "subnetEgress"
    resource_group_name           = azurerm_virtual_network.uks_spoke.resource_group_name
    virtual_network_name          = azurerm_virtual_network.uks_spoke.name
    address_prefixes              = ["10.0.2.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "uks_spoke_subnetEgress" {
    subnet_id                     = azurerm_subnet.uks_spoke_subnetEgress.id
    network_security_group_id     = azurerm_network_security_group.uks_spoke_egress.id
}



# route hub
resource "azurerm_route_table" "uks_hub_ingress" {
    name                          = "uks_hub_ingress"
    location                      = azurerm_resource_group.uks_hub.location
    resource_group_name           = azurerm_resource_group.uks_hub.name
    disable_bgp_route_propagation = false

    route {
        name                      = "Default"
        address_prefix            = "0.0.0.0/0"
        next_hop_type             = "VirtualAppliance"
        next_hop_in_ip_address    = module.ub_uks_hub.lb_ip
    }
}

resource "azurerm_subnet_route_table_association" "uks_hub_ingress" {
    subnet_id                     = azurerm_subnet.uks_hub_subnetHub.id
    route_table_id                = azurerm_route_table.uks_hub_ingress.id
}


# route spoke
resource "azurerm_route_table" "uks_spoke_egress" {
    name                          = "uks_spoke_egress"
    location                      = azurerm_resource_group.uks_spoke.location
    resource_group_name           = azurerm_resource_group.uks_spoke.name
    disable_bgp_route_propagation = false

    route {
        name                      = "Default"
        address_prefix            = "0.0.0.0/0"
        next_hop_type             = "VirtualAppliance"
        next_hop_in_ip_address    = module.ub_uks_hub.lb_ip
    }
}

resource "azurerm_subnet_route_table_association" "uks_spoke_egress" {
    subnet_id                     = azurerm_subnet.uks_spoke_subnetEgress.id
    route_table_id                = azurerm_route_table.uks_spoke_egress.id
}



# peering
resource "azurerm_virtual_network_peering" "uks_hubSpoke" {
    name                          = "uks_spoke"
    resource_group_name           = azurerm_virtual_network.uks_hub.resource_group_name
    virtual_network_name          = azurerm_virtual_network.uks_hub.name
    remote_virtual_network_id     = azurerm_virtual_network.uks_spoke.id
    allow_forwarded_traffic       = true
    allow_gateway_transit         = true
    allow_virtual_network_access  = true
    use_remote_gateways           = false
}

resource "azurerm_virtual_network_peering" "uks_spokeHub" {
    name                          = "uks_hub"
    resource_group_name           = azurerm_virtual_network.uks_spoke.resource_group_name
    virtual_network_name          = azurerm_virtual_network.uks_spoke.name
    remote_virtual_network_id     = azurerm_virtual_network.uks_hub.id
    allow_forwarded_traffic       = true
    allow_gateway_transit         = false
    allow_virtual_network_access  = true
    use_remote_gateways           = false
}



# ubuntu vms
module "ub_uks_hub" {
    source                        = "./ubuntu_hub"
    env                           = "uks_hub"
    nsg                           = azurerm_network_security_group.uks_hub_ingress.id
    rg_location                   = azurerm_resource_group.uks_hub.location
    rg_name                       = azurerm_resource_group.uks_hub.name
    subnetIngressId               = azurerm_subnet.uks_hub_subnetHub.id
    subnetIngressCidr             = azurerm_subnet.uks_hub_subnetHub.address_prefixes[0]
    subnetEgressId                = azurerm_subnet.uks_hub_subnetEgress.id
    subnetEgressCidr              = azurerm_subnet.uks_hub_subnetEgress.address_prefixes[0]
}

module "ub_uks_spoke" {
    source                        = "./ubuntu_spoke"
    env                           = "uks_spoke"
    rg_location                   = azurerm_resource_group.uks_spoke.location
    rg_name                       = azurerm_resource_group.uks_spoke.name
    subnetEgressId                = azurerm_subnet.uks_spoke_subnetEgress.id
    subnetEgressCidr              = azurerm_subnet.uks_spoke_subnetEgress.address_prefixes[0]
}
