variable "name" {
  description = "Installation and AKS cluster name."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "Use 3–40 lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "resource_group" {
  description = "Dedicated resource group overrides. Defaults to the installation name and resource location; existing callers retain their explicit names."
  type        = object({ name = optional(string), location = optional(string) })
  default     = {}
}

variable "location" {
  description = "Azure region for the foundation resources."
  type        = string
}

variable "network" {
  description = "Dedicated VNet and explicit node/operator/private-endpoint subnet address spaces."
  type = object({
    name           = optional(string)
    address_space  = list(string)
    subnets        = map(list(string))
    pod_cidr       = string
    service_cidr   = string
    dns_service_ip = string
  })
  validation {
    condition = alltrue([
      for name in ["nodes", "operator", "private-endpoints"] : contains(keys(var.network.subnets), name)
    ])
    error_message = "Supply nodes, operator and private-endpoints subnets."
  }
  validation {
    condition = (
      length(var.network.address_space) > 0 &&
      alltrue([for cidr in concat(var.network.address_space, flatten(values(var.network.subnets)), [var.network.pod_cidr, var.network.service_cidr]) : can(cidrnetmask(cidr))]) &&
      alltrue([for cidrs in values(var.network.subnets) : length(cidrs) > 0]) &&
      can(cidrnetmask("${var.network.dns_service_ip}/32"))
    )
    error_message = "Use nonempty IPv4 VNet/subnet ranges and valid Pod, Service and DNS IPv4 inputs."
  }
}

variable "cluster" {
  description = "Reviewed AKS version and node capacity. Platform upgrades are independent of application releases."
  type = object({
    version                 = string
    dns_prefix              = optional(string)
    node_resource_group     = optional(string)
    node_pool_name          = optional(string, "system")
    node_vm_size            = optional(string, "Standard_D2s_v5")
    node_count              = optional(number, 2)
    node_os_disk_size_gb    = optional(number, 64)
    node_os_sku             = optional(string, "Ubuntu")
    max_pods                = optional(number, 110)
    max_surge               = optional(string, "1")
    node_os_upgrade_channel = optional(string, "None")
    admin_username          = optional(string, "dispatchadmin")
    ssh_public_key          = string
  })
  validation {
    condition = (
      var.cluster.node_count >= 1 && var.cluster.node_count <= 10 &&
      floor(var.cluster.node_count) == var.cluster.node_count &&
      can(regex("^1\\.[0-9]+\\.[0-9]+$", var.cluster.version)) &&
      var.cluster.max_pods >= 10 && var.cluster.max_pods <= 250
    )
    error_message = "Pin an explicit Kubernetes patch, 1–10 whole nodes and 10–250 Pods per node."
  }
}

variable "postgres" {
  description = "Private PostgreSQL Flexible Server. Database contents, scoped roles and passwords remain explicit operator-owned state."
  type = object({
    name                  = optional(string)
    version               = optional(string, "17")
    sku_name              = optional(string, "GP_Standard_D2ds_v5")
    storage_mb            = optional(number, 32768)
    storage_tier          = optional(string, "P4")
    zone                  = optional(string, "1")
    administrator_login   = optional(string, "dispatch_operator")
    backup_retention_days = optional(number, 7)
    private_endpoint_name = optional(string)
    dns_zone_name         = optional(string, "privatelink.postgres.database.azure.com")
    dns_link_name         = optional(string)
  })
  default = {}
  validation {
    condition = (
      var.postgres.version == "17" &&
      var.postgres.backup_retention_days >= 7 &&
      var.postgres.backup_retention_days <= 35
    )
    error_message = "Use the qualified PostgreSQL 17 major and retain 7–35 days of backups."
  }
}

variable "postgres_administrator_password" {
  description = "Ephemeral administrator password for creation or explicit rotation. Null leaves the credential unmanaged."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "postgres_password_version" {
  description = "Explicit write-only password change trigger. Supply with the password and increment only for rotation; null leaves the credential unmanaged."
  type        = number
  default     = null
}

variable "retained_postgres_firewall_rules" {
  description = "Optional named PostgreSQL firewall rules. Public server access remains disabled; these rules do not enable connectivity."
  type        = map(object({ start_ip = string, end_ip = string }))
  default     = {}
}

variable "tags" {
  description = "Caller-owned resource tags."
  type        = map(string)
  default     = {}
}
