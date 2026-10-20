# Existing callers keep every explicitly supplied name. Derived names are only
# defaults for new installations; do not remove overrides when adopting state.
locals {
  resource_group = {
    name     = coalesce(var.resource_group.name, var.name)
    location = coalesce(var.resource_group.location, var.location)
  }
  network_name = coalesce(var.network.name, "${var.name}-vnet")
  cluster = merge(var.cluster, {
    dns_prefix          = coalesce(var.cluster.dns_prefix, var.name)
    node_resource_group = coalesce(var.cluster.node_resource_group, "${local.resource_group.name}-nodes")
  })
  postgres = merge(var.postgres, {
    name                  = coalesce(var.postgres.name, "${var.name}-postgres")
    private_endpoint_name = coalesce(var.postgres.private_endpoint_name, "${var.name}-postgres")
    dns_link_name         = coalesce(var.postgres.dns_link_name, "${var.name}-postgres")
  })
}
