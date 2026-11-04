resource "google_compute_firewall" "allow_mgmt" {
  name          = "${local.prefix}fw-mgmt-allow-admin"
  network       = local.connected_subnets[local.mgmt_subnet].network
  source_ranges = var.admin_acl
  target_tags   = var.fgt_tags

  allow {
    protocol = "TCP"
    ports    = ["22", "443"]
  }
}

resource "google_compute_firewall" "allow_fgsp" {
  name        = "${local.prefix}fw-allow-fgsp"
  network     = local.connected_subnets[local.fgsp_subnet].network
  source_tags = var.fgt_tags
  target_tags = var.fgt_tags

  allow {
    protocol = "UDP"
    ports    = ["708"]
  }
  allow {
    protocol = "TCP"
    ports    = ["703", "23"]
  }
}

resource "google_compute_firewall" "allow_health_check" {
  for_each = { for name, net in local.connected_subnets : name => net if name != local.mgmt_subnet }

  name          = "${local.prefix}fw-${local.root_subnet_names[each.key]}-allow-healthcheck"
  network       = each.value.network
  source_ranges = contains(local.subnets_public, each.key) ? local.hc_ranges_elb : local.hc_ranges_ilb
  target_tags   = var.fgt_tags

  allow {
    protocol = "TCP"
    ports    = [var.healthcheck_port]
  }
}

resource "google_compute_firewall" "allowall_port1" {
  name          = "${local.prefix}fw-${local.root_subnet_names[var.subnets[0]]}-allowall"
  network       = local.connected_subnets[var.subnets[0]].network
  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.fgt_tags

  allow {
    protocol = "all"
  }
}
