resource "azurerm_resource_group" "this" {
  name     = var.resource_group.name
  location = var.resource_group.location
  tags     = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_virtual_network" "this" {
  name                = var.network.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.network.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each             = var.network.subnets
  name                 = each.key
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value

  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true
}
