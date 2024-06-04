#
# Reserve a private address for each subnet * for each instance
#
## Indexed by port name * FGT instance index (port1_0, port1_1, port2_0, port2_1, ...)
# 
resource "google_compute_address" "prv" {
#  for_each = toset([for pair in setproduct(range(length(var.subnets)), range(var.cluster_size)) : join("_", pair)])
  for_each = toset([
    for pair in setproduct(
      keys(data.google_compute_subnetwork.connected), 
      range(var.cluster_size)) 
    : join("_", pair)
  ])

  name         = "${local.prefix}addr-${split("_", each.key)[0]}-fgt${split("_", each.key)[1]+1}-${local.region_short}"
  region       = local.region
  address_type = "INTERNAL"
  subnetwork   = data.google_compute_subnetwork.connected[split("_", each.key)[0]].id
}

#
# Reserve a public IP for each FGT instance (if enabled in var.mgmt_port_public)
#
resource "google_compute_address" "mgmt" {
  for_each = var.mgmt_port_public ? toset([ for indx in range(var.cluster_size) : "fgt${indx+1}"]) : toset([])

  name = "${local.prefix}addr-mgmt-${each.value}-${local.region_short}"
  region = local.region
}

#
# Reserve address for each ILB - in each subnet except for the first (external) and the last one (FGSP)
# (Note: FGSP port is always last and does not need to match local.mgmt_port)
# 
## Indexed by port name (port2, ...)
# 
resource "google_compute_address" "ilb" {
#  for_each = toset([for indx in range(length(var.subnets)) : tostring(indx) if indx > 0 && indx < length(var.subnets) - 1])
  #for_each = toset([ for port in keys(data.google_compute_subnetwork.connected) : port if port != "port1" && port != "port${length(var.subnets)}"])
  for_each = toset(local.ports_internal)

  name         = "${local.prefix}addr-ilb-${each.value}-${local.region_short}"
  region       = local.region
  address_type = "INTERNAL"
  subnetwork   = data.google_compute_subnetwork.connected[each.value].id
}