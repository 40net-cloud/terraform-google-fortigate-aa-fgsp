# Resources building Internal Load Balancers

resource "google_compute_region_backend_service" "ilbs" {
  provider               = google-beta
  for_each = toset(local.ports_internal)

  name                   = "${local.prefix}bes-ilb-${each.value}-${local.region_short}"
  region                 = local.region
  network                = data.google_compute_subnetwork.connected[each.value].network

  dynamic "backend" {
    for_each = google_compute_instance_group.fgt_umigs
    content {
      group = backend.value.self_link
      balancing_mode = "CONNECTION"
    }
  }

  health_checks          = [google_compute_region_health_check.health_check.self_link]
  connection_tracking_policy {
    connection_persistence_on_unhealthy_backends = "NEVER_PERSIST"
  }
}

resource "google_compute_forwarding_rule" "ilbs" {
  for_each = toset(local.ports_internal)
  name                   = "${local.prefix}fwdrule-ilb-${each.value}-${local.region_short}"
  region                 = local.region
  network                = data.google_compute_subnetwork.connected[each.value].network
  subnetwork             = data.google_compute_subnetwork.connected[each.value].id
  ip_address             = google_compute_address.ilb[each.value].address
  all_ports              = true
  load_balancing_scheme  = "INTERNAL"
  backend_service        = google_compute_region_backend_service.ilbs[each.value].self_link
  allow_global_access    = true
}
/*
resource "google_compute_route" "ilbs" {
  for_each = toset(local.ports_internal)
  name                   = "${var.prefix}rt-${each.value}-default-via-fgt"
  dest_range             = "0.0.0.0/0"
  network                = data.google_compute_subnetwork.connected[each.value].network
  next_hop_ilb           = google_compute_forwarding_rule.ilbs[each.value].self_link
  priority               = 100
}
*/
#
# Add routes to all internal networks
# 
# Use product of local.ports_internal (list of internal port names) and var.routes (all routes to add, defaults to [0.0.0.0/0])
# Index by portNumber|routeLabel (eg. port2|default)
resource "google_compute_route" "outbound_routes" {
  for_each = toset([for pair in setproduct(local.ports_internal, keys(var.routes)) : join("|", pair)])

  name         = "${local.prefix}rt-${trimprefix(data.google_compute_subnetwork.connected[split("|", each.key)[0]].name, local.prefix)}-${split("|", each.key)[1]}-via-fgt"
  dest_range   = var.routes[split("|", each.key)[1]]
  network      = data.google_compute_subnetwork.connected[split("|", each.key)[0]].network
  next_hop_ilb = google_compute_forwarding_rule.ilbs[split("|", each.key)[0]].self_link
  priority     = 100
}

/*
# Transit network
resource "google_compute_region_backend_service" "ilb_trans" {
  provider               = google-beta
  name                   = "${var.prefix}bes-trans-ilb-${local.region_short}"
  region                 = local.region
  network                = data.google_compute_subnetwork.subnets[6].network

  backend {
    group                = google_compute_instance_group.fgt-umigs[0].self_link
  }
  backend {
    group                = google_compute_instance_group.fgt-umigs[1].self_link
  }

  health_checks          = [google_compute_region_health_check.health_check.self_link]
  connection_tracking_policy {
    connection_persistence_on_unhealthy_backends = "NEVER_PERSIST"
  }
}

resource "google_compute_forwarding_rule" "ilb_trans" {
  name                   = "${var.prefix}fwdrule-trans-ilb-${local.region_short}"
  region                 = local.region
  network                = data.google_compute_subnetwork.subnets[6].network
  subnetwork             = data.google_compute_subnetwork.subnets[6].id
  ip_address             = google_compute_address.ilb_trans.address
  all_ports              = true
  load_balancing_scheme  = "INTERNAL"
  backend_service        = google_compute_region_backend_service.ilb_trans.self_link
  allow_global_access    = true
}

resource "google_compute_route" "ilb_trans" {
  name                   = "${var.prefix}rt-transit-default-via-fgt"
  dest_range             = "0.0.0.0/0"
  network                = data.google_compute_subnetwork.subnets[6].network
  next_hop_ilb           = google_compute_forwarding_rule.ilb_trans.self_link
  priority               = 100
}

# dev network
resource "google_compute_region_backend_service" "ilb_dev" {
  provider               = google-beta
  name                   = "${var.prefix}bes-dev-ilb-${local.region_short}"
  region                 = local.region
  network                = data.google_compute_subnetwork.subnets[5].network

  backend {
    group                = google_compute_instance_group.fgt-umigs[0].self_link
  }
  backend {
    group                = google_compute_instance_group.fgt-umigs[1].self_link
  }

  health_checks          = [google_compute_region_health_check.health_check.self_link]
  connection_tracking_policy {
    connection_persistence_on_unhealthy_backends = "NEVER_PERSIST"
  }
}

resource "google_compute_forwarding_rule" "ilb_dev" {
  name                   = "${var.prefix}fwdrule-dev-ilb-${local.region_short}"
  region                 = local.region
  network                = data.google_compute_subnetwork.subnets[5].network
  subnetwork             = data.google_compute_subnetwork.subnets[5].id
  ip_address             = google_compute_address.ilb_dev.address
  all_ports              = true
  load_balancing_scheme  = "INTERNAL"
  backend_service        = google_compute_region_backend_service.ilb_dev.self_link
  allow_global_access    = true
}

resource "google_compute_route" "ilb_dev" {
  for_each = var.cidrs_hq

  name                   = "${var.prefix}rt-dev-to-${each.key}-via-fgt"
  dest_range             = each.value
  network                = data.google_compute_subnetwork.subnets[5].network
  next_hop_ilb           = google_compute_forwarding_rule.ilb_dev.self_link
  priority               = 100
}
resource "google_compute_route" "ilb_dev_default" {
  name                   = "${var.prefix}rt-dev-default-via-fgt"
  dest_range             = "0.0.0.0/0"
  network                = data.google_compute_subnetwork.subnets[5].network
  next_hop_ilb           = google_compute_forwarding_rule.ilb_dev.self_link
  priority               = 100
}

# test network
resource "google_compute_region_backend_service" "ilb_test" {
  provider               = google-beta
  name                   = "${var.prefix}bes-test-ilb-${local.region_short}"
  region                 = local.region
  network                = data.google_compute_subnetwork.subnets[4].network

  backend {
    group                = google_compute_instance_group.fgt-umigs[0].self_link
  }
  backend {
    group                = google_compute_instance_group.fgt-umigs[1].self_link
  }

  health_checks          = [google_compute_region_health_check.health_check.self_link]
  connection_tracking_policy {
    connection_persistence_on_unhealthy_backends = "NEVER_PERSIST"
  }
}

resource "google_compute_forwarding_rule" "ilb_test" {
  name                   = "${var.prefix}fwdrule-test-ilb-${local.region_short}"
  region                 = local.region
  network                = data.google_compute_subnetwork.subnets[4].network
  subnetwork             = data.google_compute_subnetwork.subnets[4].id
  ip_address             = google_compute_address.ilb_test.address
  all_ports              = true
  load_balancing_scheme  = "INTERNAL"
  backend_service        = google_compute_region_backend_service.ilb_test.self_link
  allow_global_access    = true
}

resource "google_compute_route" "ilb_test" {
  for_each = var.cidrs_hq

  name                   = "${var.prefix}rt-test-to-${each.key}-via-fgt"
  dest_range             = each.value
  network                = data.google_compute_subnetwork.subnets[4].network
  next_hop_ilb           = google_compute_forwarding_rule.ilb_test.self_link
  priority               = 100
}
resource "google_compute_route" "ilb_test_default" {
  name                   = "${var.prefix}rt-test-default-via-fgt"
  dest_range             = "0.0.0.0/0"
  network                = data.google_compute_subnetwork.subnets[4].network
  next_hop_ilb           = google_compute_forwarding_rule.ilb_test.self_link
  priority               = 100
}
*/