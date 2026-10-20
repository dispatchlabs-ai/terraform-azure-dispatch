locals {
  backend_service_account = "${var.release_name}-backend"
}

terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.10" }
    azapi   = { source = "Azure/azapi", version = "~> 2.13" }
  }
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  features {}
}

provider "azapi" {
  subscription_id            = var.subscription_id
  tenant_id                  = var.tenant_id
  skip_provider_registration = true
  disable_default_output     = true
}

module "foundation" {
  source = "../.."

  name     = var.name
  location = var.location
  network  = var.network
  cluster = {
    version        = var.kubernetes_version
    ssh_public_key = var.ssh_public_key
  }
  postgres                        = var.postgres
  postgres_administrator_password = var.postgres_administrator_password
  postgres_password_version       = var.postgres_password_version
  tags                            = var.tags
}

# AzAPI manages ARM metadata without AzureRM's computed storage-account keys.
# Objects use an authenticated TLS endpoint; anonymous and shared-key access
# are disabled. No listKeys action or object payload belongs in this state.
resource "azapi_resource" "artifacts" {
  type      = "Microsoft.Storage/storageAccounts@2025-01-01"
  name      = var.artifacts_account
  parent_id = module.foundation.resource_group.id
  location  = var.location
  tags      = var.tags
  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }
    properties = {
      accessTier                  = "Hot"
      allowBlobPublicAccess       = false
      allowSharedKeyAccess        = false
      allowCrossTenantReplication = false
      supportsHttpsTrafficOnly    = true
      minimumTlsVersion           = "TLS1_2"
      encryption = {
        keySource = "Microsoft.Storage"
        services  = { blob = { enabled = true, keyType = "Account" } }
      }
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "blob_service" {
  type      = "Microsoft.Storage/storageAccounts/blobServices@2025-01-01"
  name      = "default"
  parent_id = azapi_resource.artifacts.id
  body = {
    properties = {
      isVersioningEnabled            = true
      deleteRetentionPolicy          = { enabled = true, days = 7, allowPermanentDelete = false }
      containerDeleteRetentionPolicy = { enabled = true, days = 7 }
    }
  }
}

resource "azapi_resource" "container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01"
  name      = var.artifacts_container
  parent_id = azapi_resource.blob_service.id
  body      = { properties = { publicAccess = "None" } }
  lifecycle { prevent_destroy = true }
}

resource "azurerm_user_assigned_identity" "backend" {
  name                = "${var.name}-backend"
  resource_group_name = module.foundation.resource_group.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "backend" {
  name                      = "dispatch-backend"
  user_assigned_identity_id = azurerm_user_assigned_identity.backend.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = module.foundation.cluster.oidc_issuer
  subject                   = "system:serviceaccount:${var.namespace}:${local.backend_service_account}"
}

# Scope this installation to its dedicated container, not the whole account.
# Blob write permits replacement; Dispatch must use conditional create. Retained
# object versions and the paired restore procedure remain necessary.
resource "azurerm_role_definition" "artifacts" {
  name              = "${var.name} artifact read/write"
  scope             = module.foundation.resource_group.id
  assignable_scopes = [module.foundation.resource_group.id]
  permissions {
    actions = ["Microsoft.Storage/storageAccounts/blobServices/containers/read"]
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
    ]
  }
}

resource "azurerm_role_assignment" "artifacts" {
  scope              = azapi_resource.container.id
  role_definition_id = azurerm_role_definition.artifacts.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.backend.principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_container_registry" "runtime" {
  name                = var.registry_name
  resource_group_name = module.foundation.resource_group.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_role_assignment" "image_pull" {
  scope                = azurerm_container_registry.runtime.id
  role_definition_name = "AcrPull"
  principal_id         = module.foundation.identities.kubelet_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_public_ip" "gateway" {
  name                = "${var.name}-gateway"
  resource_group_name = module.foundation.resource_group.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_role_assignment" "gateway" {
  scope                = azurerm_public_ip.gateway.id
  role_definition_name = "Network Contributor"
  principal_id         = module.foundation.identities.control_plane_principal_id
  principal_type       = "ServicePrincipal"
}
