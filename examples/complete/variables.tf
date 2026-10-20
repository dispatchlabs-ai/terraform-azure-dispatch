variable "subscription_id" {
  description = "Subscription in which all resources will be created."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant containing the subscription and workload identity."
  type        = string
}

variable "name" {
  description = "Unique installation prefix; derived resource names must also be globally available where Azure requires it."
  type        = string
  default     = "dispatch"
}

variable "location" {
  description = "Region supporting the selected AKS version, node SKU and PostgreSQL SKU."
  type        = string
  default     = "eastus2"
}

variable "kubernetes_version" {
  description = "Explicit supported AKS patch version."
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key for node administration. Never supply a private key."
  type        = string
}

variable "network" {
  description = "Dedicated, non-overlapping VNet/subnet/Pod/Service ranges."
  type = object({
    name           = optional(string)
    address_space  = list(string)
    subnets        = map(list(string))
    pod_cidr       = string
    service_cidr   = string
    dns_service_ip = string
  })
  default = {
    address_space = ["10.70.0.0/16"]
    subnets = {
      nodes               = ["10.70.0.0/22"]
      operator            = ["10.70.4.0/24"]
      "private-endpoints" = ["10.70.5.0/24"]
    }
    pod_cidr       = "10.71.0.0/16"
    service_cidr   = "10.72.0.0/16"
    dns_service_ip = "10.72.0.10"
  }
}

variable "postgres" {
  description = "Optional PostgreSQL name/capacity overrides; the module supplies PostgreSQL 17 defaults."
  type = object({
    name                  = optional(string)
    sku_name              = optional(string, "GP_Standard_D2ds_v5")
    storage_mb            = optional(number, 32768)
    storage_tier          = optional(string, "P4")
    zone                  = optional(string, "1")
    backup_retention_days = optional(number, 7)
  })
  default = {}
}

variable "postgres_administrator_password" {
  description = "Administrator password supplied securely at plan/apply; never saved in tfvars or state."
  type        = string
  sensitive   = true
  ephemeral   = true
  nullable    = false
}

variable "postgres_password_version" {
  description = "Keep configured and increment only when intentionally rotating the supplied password."
  type        = number
  default     = 1
}

variable "artifacts_account" {
  description = "Globally unique new Azure Storage account name."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.artifacts_account))
    error_message = "Use 3–24 lowercase letters or digits."
  }
}

variable "artifacts_container" {
  description = "Dedicated private container for this installation."
  type        = string
  default     = "dispatch"
}

variable "artifacts_prefix" {
  description = "Installation object prefix; IAM is scoped to the dedicated container."
  type        = string
  default     = "dispatch"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9/_-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$", var.artifacts_prefix))
    error_message = "Use letters, digits, slash, underscore or hyphen, starting and ending with a letter or digit."
  }
}

variable "registry_name" {
  description = "Globally unique new ACR name, 5–50 alphanumeric characters."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.registry_name))
    error_message = "Use 5–50 letters or digits."
  }
}

variable "namespace" {
  description = "Kubernetes namespace used when installing the application chart."
  type        = string
  default     = "dispatch"
}

variable "release_name" {
  description = "Helm release name; the chart derives its backend ServiceAccount from this value."
  type        = string
  default     = "dispatch"
  validation {
    condition     = length(var.release_name) <= 53 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "Use 1–53 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
}

variable "tags" {
  description = "Caller resource tags."
  type        = map(string)
  default     = {}
}
