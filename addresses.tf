#
# Reserve a private address for each subnet * for each instance
#
## Indexed by FGT instance and subnet (eg. "fgt1|port2")
# 
resource "google_compute_address" "prv" {
  for_each = { for pair in setproduct(local.fgts, local.subnets_all) : join("|", pair) => {
    fgt = pair[0]
    net = pair[1]
  } }

  name         = "${local.prefix}addr-${each.value.fgt}-${local.root_subnet_names[each.value.net]}-${local.region_short}"
  region       = local.region
  address_type = "INTERNAL"
  subnetwork   = local.connected_subnets[each.value.net].id
  address      = try(var.ports[each.value.net].addresses[tonumber(regex("\\d+$", each.value.fgt)) - 1], null)
}

#
# Reserve a public IP for each FGT instance (if enabled in var.mgmt_port_public)
#
resource "google_compute_address" "mgmt" {
  for_each = var.mgmt_port_public ? toset(local.fgts) : toset([])

  name   = "${local.prefix}addr-${each.value}-mgmt-${local.region_short}"
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
  for_each = toset(local.subnets_internal)

  name         = "${local.prefix}addr-ilb-${local.root_subnet_names[each.value]}-${local.region_short}"
  region       = local.region
  address_type = "INTERNAL"
  subnetwork   = local.connected_subnets[each.value].id
}
