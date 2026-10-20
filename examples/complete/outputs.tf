output "installation" {
  description = "Non-secret metadata for platform, chart and database initialization."
  value = {
    release                 = var.release_name
    namespace               = var.namespace
    backend_service_account = local.backend_service_account
    cluster                 = module.foundation.cluster
    postgres                = module.foundation.postgres
    artifacts = {
      provider         = "azure"
      account          = azapi_resource.artifacts.name
      endpoint         = "https://${azapi_resource.artifacts.name}.blob.core.windows.net/"
      container        = azapi_resource.container.name
      prefix           = var.artifacts_prefix
      credentials_mode = "workloadIdentity"
      backend_identity = azurerm_user_assigned_identity.backend.client_id
      service_account_annotations = {
        "azure.workload.identity/client-id" = azurerm_user_assigned_identity.backend.client_id
        "azure.workload.identity/tenant-id" = var.tenant_id
      }
      backend_pod_labels = { "azure.workload.identity/use" = "true" }
    }
    registry = azurerm_container_registry.runtime.login_server
    gateway = {
      address        = azurerm_public_ip.gateway.ip_address
      address_name   = azurerm_public_ip.gateway.name
      resource_group = module.foundation.resource_group.name
    }
  }
  depends_on = [azurerm_federated_identity_credential.backend, azurerm_role_assignment.artifacts, azurerm_role_assignment.gateway]
}

output "helm_values" {
  description = "Partial Dispatch chart values. Export as JSON and merge with reviewed platform/application values; no credentials are included."
  value = {
    postgres = {
      host = module.foundation.postgres.host
      port = module.foundation.postgres.port
    }
    artifacts = {
      kind            = "azure"
      endpoint        = "https://${azapi_resource.artifacts.name}.blob.core.windows.net/"
      container       = azapi_resource.container.name
      prefix          = var.artifacts_prefix
      credentialsMode = "workloadIdentity"
    }
    backend = {
      podLabels = { "azure.workload.identity/use" = "true" }
      serviceAccount = {
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.backend.client_id
          "azure.workload.identity/tenant-id" = var.tenant_id
        }
      }
    }
    networkPolicy = {
      databaseCidrs = ["${module.foundation.postgres.private_ip}/32"]
    }
  }
}
