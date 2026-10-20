# Complete Azure infrastructure example

This root composes the private AKS/PostgreSQL foundation with an encrypted,
versioned private Blob container, backend-only Workload Identity, ACR with
kubelet pull access and a reserved gateway IP. It uses the local module source,
so it works from a reviewed Git checkout before registry publication.
PostgreSQL is single-instance and this is not an HA application deployment.

## Prepare

Use Terraform or OpenTofu 1.11 or later, below 2.0. Register the Azure resource
providers needed by these resources before running this root:
`Microsoft.Authorization`, `Microsoft.Compute`, `Microsoft.ContainerRegistry`,
`Microsoft.ContainerService`, `Microsoft.DBforPostgreSQL`,
`Microsoft.ManagedIdentity`, `Microsoft.Network`, and `Microsoft.Storage`.
Use your usual secure Azure provider authentication for the specified tenant
and subscription. The provisioning identity needs resource creation and role
assignment authority within the intended scope.

Copy `terraform.tfvars.example` to a private `terraform.tfvars`. Replace the
sample subscription, tenant, public SSH key and globally unique storage/registry
names. Review the chosen region's Kubernetes version, VM/database SKUs, zone
and quota. If needed, override `postgres.name` with a globally available server
name. Review the VNet, subnet, Pod and Service ranges.

Provide `postgres_administrator_password` through a secure ephemeral input
mechanism at both plan and apply. Do not save it in tfvars. Keep
`postgres_password_version` configured; increment it only for intentional
rotation. The module uses AzureRM's write-only field, so the password does not
enter plan or state. Unrelated server updates still require that input.

Configure a protected remote backend in this root before applying. The example
does not select your state account or credentials. Commit its provider lockfile.

```sh
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=foundation.plan
terraform apply foundation.plan
terraform output -json installation
terraform output -json helm_values > cloud-values.json
```

`cloud-values.json` is a non-secret partial Helm values file. Merge it with
your application and platform values; it deliberately omits image digests,
private keys, database credentials, public hostname and activation.

Use `tofu` in place of `terraform` for the same commands. Review the complete
plan before apply. This example creates a fresh installation and is not an
import/adoption procedure.

## Install the application

1. Arrange private operator routing to AKS/PostgreSQL and resolution of their
   private DNS zones, using VPN/peering or an operator host. The foundation
   creates the PostgreSQL Private Link DNS zone/link.
2. Push reviewed backend, launcher and worker images to output `registry` and
   record immutable digests. ACR admin credentials are disabled; kubelet
   identity has `AcrPull`, with no artifact permissions.
3. Fetch and verify Azure PostgreSQL's CA bundle. Use output `postgres.host`
   with `verify-full`. A trusted operator initializes the seven isolated
   databases and retains role-separated application credentials and
   encryption/signing keys outside Terraform and ephemeral Pods.
4. Install the shared Dispatch chart and reusable Kubernetes platform
   gateway/policies from the same reviewed release, initially disabled.
   Default namespace/release `dispatch` produces `dispatch-backend`, matching
   the identity federation. Configure chart artifacts with `kind: azure`,
   output `endpoint`, `container`, `prefix` and
   `credentialsMode: workloadIdentity`.
5. Apply `service_account_annotations` to the backend ServiceAccount and
   `backend_pod_labels` to the backend only. Azure's webhook supplies the
   projected token/environment. Launcher and workers receive neither this
   identity nor cloud metadata access.
6. Configure the gateway Service with output `gateway.address_name` and
   `gateway.resource_group`. The AKS control-plane identity has Network
   Contributor on that IP and only `Microsoft.Network/publicIPAddresses/read`
   on its resource group. The [Azure cloud controller fills its public-IP cache
   by listing the group](https://github.com/kubernetes-sigs/cloud-provider-azure/blob/v1.36.0/pkg/provider/azure_publicip_repo.go#L103),
   even when the Service names one IP. The group grant adds discovery without
   granting network writes or storage access across the group.
   Supply your public application DNS/TLS and backend callback certificates.
   Initialize the stores and verify allowed/denied traffic from real worker
   Pods before activation.

The Blob container is private and shared-key authentication is disabled.
Objects use an authenticated public HTTPS endpoint. The backend role permits
read/write only in this installation's dedicated container, without delete or
credential actions. Blob write includes replacement, so the application must
use conditional creation; versioning and retained backups remain necessary.
IAM is container-scoped rather than prefix-scoped.

## Ownership and maintenance

AzAPI provisions storage through management-plane calls without listing account
keys. It does not fetch objects or secret values. The foundation similarly
avoids fetching AKS admin kubeconfigs. Database credentials, SQL state,
Kubernetes Secrets and object contents remain outside Terraform.

New callers default node OS automatic upgrades to `None`. This requires a
planned OS/Kubernetes patching schedule; it does not prevent all Azure platform
maintenance. Drain the application and positively terminate workers before
planned upgrades. Existing callers with explicit upgrade-channel inputs retain
their chosen values.

Retain database backups, object versions and corresponding keys together and
qualify restore before relying on the deployment. Storage versioning and
deletion protections do not replace that procedure.

Use your own root to compose existing storage, registry or operator access
around the foundation. Do not drop explicit resource-name overrides when
adopting existing state. This example has static CLI/provider validation; a
fresh cloud apply and full application qualification remain required.

Install Helm with the output `installation.release` and `installation.namespace`.
The `release_name` input derives the backend ServiceAccount name used by workload
identity; changing it also requires a deliberately reviewed Helm release migration.
