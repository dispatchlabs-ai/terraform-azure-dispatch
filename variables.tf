variable "name" {
  description = "Installation and AKS cluster name. Named infrastructure must retain its identity during adoption."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "Use 3–40 lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "resource_group" {
  description = "Dedicated resource group name and metadata location; its location may differ from the deployed resources."
  type        = object({ name = string, location = string })
}

variable "location" {
  description = "Azure region for the foundation resources."
  type        = string
}

variable "network" {
  description = "Dedicated VNet and explicit node/operator/private-endpoint subnet address spaces."
  type = object({
    name           = string
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
    dns_prefix              = string
    node_resource_group     = string
    node_pool_name          = string
    node_vm_size            = string
    node_count              = number
    node_os_disk_size_gb    = number
    node_os_sku             = string
    max_pods                = number
    max_surge               = string
    node_os_upgrade_channel = string
    admin_username          = string
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
    name                  = string
    version               = string
    sku_name              = string
    storage_mb            = number
    storage_tier          = string
    zone                  = string
    administrator_login   = string
    backup_retention_days = number
    private_endpoint_name = string
    dns_zone_name         = string
    dns_link_name         = string
  })
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
  description = "Write-only creation credential. Leave null when adopting an existing server; never reads or rotates the retained password."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "postgres_password_version" {
  description = "Explicit write-only password change trigger; null preserves the imported credential."
  type        = number
  default     = null
}

variable "retained_postgres_firewall_rules" {
  description = "Existing firewall rules retained during adoption. Public server access remains disabled; do not add rules as a private-access substitute."
  type        = map(object({ start_ip = string, end_ip = string }))
  default     = {}
}

variable "tags" {
  description = "Caller-owned resource tags."
  type        = map(string)
  default     = {}
}
