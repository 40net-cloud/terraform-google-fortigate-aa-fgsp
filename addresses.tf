#
# Reserve a private address for each subnet * for each instance
#
resource "google_compute_address" "prv" {
  for_each = toset([for pair in setproduct(range(length(var.subnets)), range(var.cluster_size)) : join("_", pair)])

  name         = "${local.prefix}addrprv-port${split("_", each.key)[0] + 1}-${split("_", each.key)[1]}"
  region       = local.region
  address_type = "INTERNAL"
  subnetwork   = data.google_compute_subnetwork.connected[var.subnets[split("_", each.key)[0]]].id
}

#
# Reserve a public IP for each public management NIC
#
resource "google_compute_address" "pub" {
  for_each = toset([for pair in setproduct(var.public_mgmt_nics, range(var.cluster_size)) : join("-", pair)])

  name   = "${local.prefix}addrpub-${each.key}"
  region = local.region
}

#
# Reserve address for each ILB - in each subnet except for the first (external) and the last one (FGSP)
# 
resource "google_compute_address" "ilb" {
  for_each = toset([for indx in range(length(var.subnets)) : tostring(indx) if indx > 0 && indx < length(var.subnets) - 1])

  name         = "${local.prefix}addr-port${each.key + 1}-ilb"
  region       = local.region
  address_type = "INTERNAL"
  subnetwork   = data.google_compute_subnetwork.connected[var.subnets[each.key]].id
}