# Dispatch Azure foundation

This module owns a dedicated Azure resource group, VNet, private AKS cluster,
scoped control-plane/kubelet identities, and private PostgreSQL Flexible Server.
It follows the Kubernetes foundation boundary of `terraform-aws-dispatch`.
The caller owns registry pull grants, native Blob storage and backend identity,
operator access, escrow metadata, and the public gateway address. A separate
platform/application installation owns Helm, Kubernetes policies and Secrets.

AKS uses Azure CNI Overlay with managed Cilium, private API/DNS, OIDC and workload
identity. It retains a fixed node count and explicit Kubernetes patch. PostgreSQL
uses Private Link, verified TLS and the inherited safe logging settings required
by conversation workers. The module does not initialize SQL databases or roles,
create application credentials, install Helm releases, or open admission.

## Inputs and outputs

Supply `name`, `resource_group`, `location`, `network`, `cluster`, `postgres` and
optional `tags`. `network.subnets` must include `nodes`, `operator` and
`private-endpoints`. The resource group's metadata location is explicit because
existing installations may use a different region for their deployed resources.
Choose non-overlapping VNet, subnet, Pod and Service ranges and review regional
quota before provisioning or changing capacity. No high-availability claim is
implied by these inputs.

Outputs expose the resource group identity, private cluster hostname/OIDC issuer,
platform principals, subnet IDs and PostgreSQL hostname. They contain no database
password, Kubernetes administrator credential or storage key.

Use Terraform >=1.14 with AzureRM 5.10 and AzAPI 2.13. The caller pins exact provider
versions and commits its lockfile; this reusable module carries compatible version
constraints. Configure explicit subscription and tenant IDs in the caller and
disable implicit provider registration during adoption.

## Existing installation adoption

Declare the exact retained values and import each installation-owned resource
into a protected state backend. Review a full refreshed plan until it proposes
zero create/update/delete/replace operations. Do not apply changes to make the
running resources resemble defaults, add blanket `ignore_changes`, or import
service-generated children into a second owner.

For an existing PostgreSQL server, leave `postgres_administrator_password` and
`postgres_password_version` null. Azure does not return the existing password;
the imported credential remains untouched. A fresh server requires an ephemeral
`postgres_administrator_password` and an explicit `postgres_password_version`.
The resource passes them through AzureRM's write-only fields. Changing the version
is an explicit credential-rotation operation, separate from ordinary planning.
The password stays sensitive and ephemeral at the module boundary. At the single
write-only sink, `nonsensitive` removes only the sensitivity mark; it preserves
the ephemeral mark and write-only omission from plan/state. This avoids
Terraform 1.14 treating a newly sensitive imported null as a server update.
See the [write-only contract](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only).
No secret value is exposed through a local, output or state field.

`retained_postgres_firewall_rules` represents any existing rules adopted with a
server. Public access remains disabled. The retained October 2026 caller has one
inactive operator rule from initial capability inspection; removing it would be
a separate infrastructure change.

The AKS resource uses an explicit ARM body through AzAPI because AzureRM exports
administrator kubeconfigs into computed state. A separate metadata-only GET projects
only its private FQDN and OIDC issuer. The caller uses the same metadata-only
approach for Blob accounts/containers to avoid account-key reads. See the current
[AKS provider contract](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster),
[AzAPI resource contract](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource), and
[PostgreSQL write-only credential contract](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server).

The only lifecycle exclusions are `body.properties.privateLinkResources` and
`body.properties.agentPoolProfiles[0].powerState`. AKS owns the API private-link
descriptor; the operator owns pool start/stop actions. ARM permits the latter
to be written, but Terraform must not restart an intentionally stopped pool.
These are explicit ownership boundaries, not claims that both ARM fields are
read-only.
Networking, capacity, versions, identity and security settings are still compared
normally. PostgreSQL Premium_LRS reports its derived 120 IOPS; the provider only
accepts desired IOPS for its other storage mode, so this derived field is observed
in the adoption receipt instead of assigned.

## Ownership and operations

AKS owns its generated node resource group, node pools represented inside the
cluster, VM scale sets, node NICs/disks, API private endpoint/DNS, system identities
and role grants, and Kubernetes-managed load balancers. The database private
endpoint owns its generated NIC and DNS A record. Neither group is imported as
independent resources here. The caller's operator VM owns its OS disk. Database
contents, object contents/versions, secret versions and Kubernetes objects stay
with their existing operators/controllers.

Network policy qualification must use actual standalone worker Pods on the
current nodes before application activation. Planned node/cluster maintenance
must first drain the application and positively observe worker termination.
Automatic node-image maintenance, temporary capacity and quotas require an
explicit installation-specific maintenance plan; source adoption does not
qualify future upgrades, uncertain-node recovery, HA or backup restoration.

Retain and restore database snapshots, object versions and matching encrypted
keys/credential versions together. The module's prevent-destroy guards protect
the resource group, cluster and database during ordinary plans; they do not
replace a reviewed backup and recovery procedure.
