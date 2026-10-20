# Dispatch Azure foundation

This module provisions a dedicated Azure resource group, VNet, private AKS
cluster, scoped platform identities and private PostgreSQL Flexible Server for
Dispatch. It follows the foundation boundary of
[the AWS Kubernetes module](https://github.com/dispatchlabs-ai/terraform-aws-dispatch/tree/experiment/kubernetes):
cloud infrastructure is provisioned before the platform and application.

AKS uses Azure CNI Overlay with managed Cilium, private API/DNS, OIDC and workload
identity. Node count, Kubernetes patch and node-image maintenance policy are
explicit inputs. PostgreSQL 17 uses Private Link and the inherited logging
settings required by conversation workers.

## Ownership

| Owner | Resources |
| --- | --- |
| This module | Resource group, VNet/subnets, AKS and its system node pool, control-plane/kubelet identities and platform grants, private PostgreSQL, database parameters, Private Link and private DNS |
| Calling configuration | Azure account/provider configuration, state backend, registry and pull grants, Blob storage and backend identity, operator access, escrow metadata, public gateway address |
| Platform/application installation | Controllers, Helm releases, Kubernetes policies and Secrets, TLS, database initialization and application admission |

AKS owns the generated node resource group, VM scale sets, node NICs/disks, API
private endpoint/DNS and system resources. The database private endpoint owns
its generated NIC and DNS record. Database contents, artifact objects and secret
versions belong to their respective operators.

The module has no backend configuration, embedded provider configuration,
Kubernetes/Helm provider or dependency on a particular caller repository.

## Requirements and consumption

Use Terraform or OpenTofu **1.11 or later, below 2.0**. Both support the ephemeral
inputs and write-only arguments used for the database password.
See [Terraform's write-only contract](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only)
and [OpenTofu's 1.11 feature documentation](https://opentofu.org/docs/v1.11/intro/whats-new/).

The module requires AzureRM `~> 5.10` and AzAPI `~> 2.13`. Pin provider versions and
commit the dependency lockfile in the calling configuration. Configure the
intended subscription/tenant there and register the required Azure resource
providers before provisioning if automatic registration is disabled.

The module and example caller initialize and validate with Terraform 1.11.0 and
1.14.5, and OpenTofu 1.11.0 and 1.13.1. These checks do not exercise fresh cloud
provisioning.

Use this module from a root configuration with its own authentication and
protected state backend. Replace `COMMIT_OR_TAG` with an immutable release
reference. Supply the structured `network`, `cluster` and `postgres` inputs
according to [variables.tf](variables.tf).

```hcl
terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.10" }
    azapi   = { source = "Azure/azapi", version = "~> 2.13" }
  }
}

variable "subscription_id" { type = string }
variable "tenant_id" { type = string }
variable "location" { type = string }
variable "network" {}
variable "cluster" {}
variable "postgres" {}
variable "postgres_password_version" { type = number }
variable "postgres_administrator_password" {
  type      = string
  sensitive = true
  ephemeral = true
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

module "dispatch" {
  source = "git::https://github.com/dispatchlabs-ai/terraform-azure-dispatch.git?ref=COMMIT_OR_TAG"

  name           = "dispatch-prod"
  resource_group = { name = "dispatch-prod", location = var.location }
  location       = var.location
  network        = var.network
  cluster        = var.cluster
  postgres       = var.postgres

  postgres_administrator_password = var.postgres_administrator_password
  postgres_password_version       = var.postgres_password_version
  tags                            = { application = "dispatch" }
}
```

Run `terraform init`, `terraform validate` and `terraform plan` from that root.
The equivalent `tofu` commands use the same module configuration. Review the
complete plan before applying it. Supply the ephemeral password securely during
both planning and application; it is not carried inside a saved plan.

The chosen region must support the requested AKS version, node SKU and PostgreSQL
SKU. Size quota for the system pool, operator resources and upgrade surge.
Operator access to the private API and database must be arranged separately.

## Inputs and outputs

Required inputs are `name`, `resource_group`, `location`, `network`, `cluster`
and `postgres`. `tags` defaults to an empty map.

`network.subnets` must contain `nodes`, `operator` and `private-endpoints`.
Choose non-overlapping VNet, subnet, Pod and Service ranges. The resource group's
metadata location and the resource deployment region are separate inputs.

`cluster` selects a fixed system pool with an explicit Kubernetes patch, VM/OS
settings, maximum Pods, surge allowance and node-image maintenance policy.
`postgres` selects PostgreSQL 17, storage/capacity, zone and 7–35 days of backups.
Premium storage IOPS are service-derived rather than separately configured.
The optional `retained_postgres_firewall_rules` map manages named firewall rules;
public database access stays disabled, so these rules do not enable connectivity.

| Output | Contents |
| --- | --- |
| `resource_group` | Resource group ID, name and metadata location |
| `cluster` | AKS ID, name, private FQDN and OIDC issuer |
| `identities` | Control-plane and kubelet principal IDs |
| `subnet_ids` | Subnet IDs keyed by name |
| `postgres` | PostgreSQL ID, hostname and port |

Outputs contain no database password or Kubernetes credential. AKS uses an
explicit AzAPI ARM resource and a metadata-only GET so managing the foundation
does not request administrator kubeconfigs.

## Database credentials

Creating a server requires `postgres_administrator_password` and an explicit
`postgres_password_version`, such as `1`. Keep the version configured and supply
the password as an ephemeral input on subsequent runs. Increment the version
only when intentionally rotating the password. Changing the password value
alone does not request rotation.

Both inputs default to null for an unchanged existing server. AzureRM also
requires the password for server updates unrelated to credentials, so supply the
current password and its version before making any server change. Introducing or
changing the version explicitly writes the supplied password.

The password is sensitive and ephemeral at the module boundary and reaches only
AzureRM's write-only argument. A narrowly scoped `nonsensitive` removes the UI
sensitivity mark at that argument while preserving ephemerality and omission
from plan/state. The module never exposes the value through outputs.

Store the administrator credential securely outside Terraform. Application
database roles, scoped URLs and installation keys are created and retained by
the separate application initialization workflow.

## Operations

The private API's generated link descriptor and the node pool's writable
start/stop state have external lifecycle owners. The module excludes only
`body.properties.privateLinkResources` and
`body.properties.agentPoolProfiles[0].powerState` from change reconciliation:
AKS owns the descriptor, and the operator controls deliberate pool stops.
Networking, capacity, versions, identity and security settings remain managed.

Qualify network policy with actual standalone worker Pods before application
activation. Planned node/cluster maintenance first requires application drain
and positive worker termination. Account for automatic node-image maintenance,
temporary capacity and regional quotas in the installation's maintenance plan.
Private connectivity and a fixed node pool do not establish high availability;
this module provisions a single-instance PostgreSQL server.

Retain database snapshots, artifact versions and matching encrypted
keys/credential versions together, and verify restoration separately.
`prevent_destroy` guards the resource group, cluster and database during
ordinary plans; it does not replace a backup and recovery procedure.
