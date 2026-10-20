output "resource_group" {
  description = "Foundation resource group metadata for caller-owned services."
  value = {
    id       = azurerm_resource_group.this.id
    name     = azurerm_resource_group.this.name
    location = azurerm_resource_group.this.location
  }
}

output "cluster" {
  description = "Public integration metadata only; no Kubernetes credentials."
  value = {
    id           = azapi_resource.cluster.id
    name         = azapi_resource.cluster.name
    private_fqdn = data.azapi_resource.cluster_metadata.output.properties.privateFQDN
    oidc_issuer  = data.azapi_resource.cluster_metadata.output.properties.oidcIssuerProfile.issuerURL
  }
}

output "identities" {
  description = "Scoped platform identities; application storage identity remains caller-owned."
  value = {
    control_plane_principal_id = azurerm_user_assigned_identity.control_plane.principal_id
    kubelet_principal_id       = azurerm_user_assigned_identity.kubelet.principal_id
  }
}

output "subnet_ids" {
  description = "Explicit subnet identities for the caller's operator access."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}

output "postgres" {
  description = "Private PostgreSQL endpoint; passwords and SQL state are never outputs."
  value = {
    id   = azurerm_postgresql_flexible_server.this.id
    host = azurerm_postgresql_flexible_server.this.fqdn
    port = 5432
  }
}
