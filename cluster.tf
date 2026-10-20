resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.name}-control-plane"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "${var.name}-kubelet"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "control_plane_network" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# Keep node-subnet authority explicit alongside the VNet-scoped platform grant.
resource "azurerm_role_assignment" "control_plane_nodes" {
  scope                = azurerm_subnet.this["nodes"].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "control_plane_kubelet" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# AzureRM exports admin kubeconfigs as computed state. This explicit ARM resource
# manages the same AKS settings without calling listClusterAdminCredentials.
# AKS owns its node resource group, VMSS, API private endpoint/DNS and system LB.
resource "azapi_resource" "cluster" {
  type      = "Microsoft.ContainerService/managedClusters@2025-10-01"
  name      = var.name
  parent_id = azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  body = {
    kind = "Base"
    sku  = { name = "Base", tier = "Free" }
    properties = {
      kubernetesVersion       = var.cluster.version
      dnsPrefix               = var.cluster.dns_prefix
      nodeResourceGroup       = var.cluster.node_resource_group
      enableRBAC              = true
      disableLocalAccounts    = false
      supportPlan             = "KubernetesOfficial"
      bootstrapProfile        = { artifactSource = "Direct" }
      metricsProfile          = { costAnalysis = { enabled = false } }
      servicePrincipalProfile = { clientId = "msi" }
      windowsProfile = {
        adminUsername  = var.cluster.admin_username
        enableCSIProxy = true
      }
      workloadAutoScalerProfile = {}
      apiServerAccessProfile = {
        enablePrivateCluster           = true
        enablePrivateClusterPublicFQDN = false
        privateDNSZone                 = "system"
      }
      autoUpgradeProfile = {
        nodeOSUpgradeChannel = var.cluster.node_os_upgrade_channel
      }
      nodeProvisioningProfile = { mode = "Manual" }
      oidcIssuerProfile       = { enabled = true }
      securityProfile         = { workloadIdentity = { enabled = true } }
      identityProfile = {
        kubeletidentity = {
          resourceId = azurerm_user_assigned_identity.kubelet.id
          clientId   = azurerm_user_assigned_identity.kubelet.client_id
          objectId   = azurerm_user_assigned_identity.kubelet.principal_id
        }
      }
      linuxProfile = {
        adminUsername = var.cluster.admin_username
        ssh           = { publicKeys = [{ keyData = var.cluster.ssh_public_key }] }
      }
      agentPoolProfiles = [{
        name                   = var.cluster.node_pool_name
        count                  = var.cluster.node_count
        vmSize                 = var.cluster.node_vm_size
        osDiskSizeGB           = var.cluster.node_os_disk_size_gb
        osDiskType             = "Managed"
        osSKU                  = var.cluster.node_os_sku
        osType                 = "Linux"
        kubeletDiskType        = "OS"
        mode                   = "System"
        type                   = "VirtualMachineScaleSets"
        maxPods                = var.cluster.max_pods
        orchestratorVersion    = var.cluster.version
        vnetSubnetID           = azurerm_subnet.this["nodes"].id
        enableAutoScaling      = false
        enableNodePublicIP     = false
        enableEncryptionAtHost = false
        enableFIPS             = false
        enableUltraSSD         = false
        securityProfile = {
          enableSecureBoot = false
          enableVTPM       = false
          sshAccess        = "LocalUser"
        }
        scaleDownMode   = "Delete"
        upgradeSettings = { maxSurge = var.cluster.max_surge, maxUnavailable = "0" }
      }]
      networkProfile = {
        networkPlugin     = "azure"
        networkPluginMode = "overlay"
        networkDataplane  = "cilium"
        networkPolicy     = "cilium"
        loadBalancerSku   = "standard"
        outboundType      = "loadBalancer"
        podCidr           = var.network.pod_cidr
        podCidrs          = [var.network.pod_cidr]
        serviceCidr       = var.network.service_cidr
        serviceCidrs      = [var.network.service_cidr]
        dnsServiceIP      = var.network.dns_service_ip
        ipFamilies        = ["IPv4"]
        loadBalancerProfile = {
          managedOutboundIPs = { count = 1 }
          backendPoolType    = "nodeIPConfiguration"
        }
      }
      storageProfile = {
        diskCSIDriver      = { enabled = true }
        fileCSIDriver      = { enabled = true }
        snapshotController = { enabled = true }
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.control_plane_network,
    azurerm_role_assignment.control_plane_nodes,
    azurerm_role_assignment.control_plane_kubelet,
  ]

  lifecycle {
    prevent_destroy = true
    # These ARM fields have lifecycle owners outside this module:
    # AKS owns its API private-link descriptor, and the operator owns pool
    # start/stop actions. Terraform must not restart an intentionally stopped
    # pool. All networking/security/version/capacity settings remain compared.
    ignore_changes = [
      body.properties.privateLinkResources,
      body.properties.agentPoolProfiles[0].powerState,
    ]
  }
}

# A metadata-only GET projects public connection fields independently of the
# managed resource; no listClusterAdminCredentials action is issued.
data "azapi_resource" "cluster_metadata" {
  type                   = "Microsoft.ContainerService/managedClusters@2025-10-01"
  resource_id            = azapi_resource.cluster.id
  response_export_values = ["properties.privateFQDN", "properties.oidcIssuerProfile.issuerURL"]
}
