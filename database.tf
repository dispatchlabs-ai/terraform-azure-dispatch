resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.postgres.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  version             = var.postgres.version
  sku_name            = var.postgres.sku_name
  storage_mb          = var.postgres.storage_mb
  storage_tier        = var.postgres.storage_tier
  storage_type        = "Premium_LRS"
  zone                = var.postgres.zone

  administrator_login = var.postgres.administrator_login
  # Terraform 1.14 promotes a sensitivity-mark-only difference on an imported
  # null to Update. Strip only that mark at this write-only sink: the input's
  # Ephemeral mark remains, and AzureRM never stores this field in plan/state.
  # This avoids invoking a server update merely to mark a missing credential.
  administrator_password_wo         = nonsensitive(var.postgres_administrator_password)
  administrator_password_wo_version = var.postgres_password_version
  public_network_access_enabled     = false
  backup_retention_days             = var.postgres.backup_retention_days
  geo_redundant_backup_enabled      = false
  auto_grow_enabled                 = false
  tags                              = var.tags

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# These inherited settings are part of the worker isolation contract. Explicitly
# adopt the safe defaults as well as the four operator-changed values.
locals {
  postgres_parameters = {
    log_statement                      = "none"
    log_min_duration_statement         = "-1"
    log_min_duration_sample            = "-1"
    log_min_error_statement            = "panic"
    log_error_verbosity                = "terse"
    log_parameter_max_length           = "0"
    log_parameter_max_length_on_error  = "0"
    password_encryption                = "scram-sha-256"
    "pgaudit.log"                      = "none"
    "pg_stat_statements.track_utility" = "off"
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "runtime" {
  for_each  = local.postgres_parameters
  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = each.value
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "retained" {
  for_each         = var.retained_postgres_firewall_rules
  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = each.value.start_ip
  end_ip_address   = each.value.end_ip
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = var.postgres.dns_zone_name
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                 = var.postgres.dns_link_name
  private_dns_zone_id  = azurerm_private_dns_zone.postgres.id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
}

resource "azurerm_private_endpoint" "postgres" {
  name                = var.postgres.private_endpoint_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  subnet_id           = azurerm_subnet.this["private-endpoints"].id

  private_service_connection {
    name                           = var.postgres.private_endpoint_name
    private_connection_resource_id = azurerm_postgresql_flexible_server.this.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  # The endpoint controller owns its generated NIC and the A record.
  private_dns_zone_group {
    name                 = "postgres"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgres.id]
  }
}
