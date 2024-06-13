resource "google_compute_firewall" "allow_mgmt" {
  name          = "${local.prefix}fw-mgmt-allow-admin"
  network       = data.google_compute_subnetwork.connected[local.mgmt_port].network
  source_ranges = var.admin_acl
  target_tags   = var.fgt_tags

  allow {
    protocol = "TCP"
    ports = ["22", "80", "443"]
  }
}

resource "google_compute_firewall" "allow_fgsp" {
  name          = "${local.prefix}fw-allow-fgsp"
  network       = data.google_compute_subnetwork.connected[local.fgsp_port].network
  source_tags   = var.fgt_tags
  target_tags   = var.fgt_tags

  allow {
    protocol = "UDP"
    ports = ["708"]
  }
  allow {
    protocol = "TCP"
    ports = ["703", "23"]
  }
}

resource "google_compute_firewall" "allow_health_check" {
  for_each = { for indx,net in data.google_compute_subnetwork.connected : indx=>net if indx != local.mgmt_port }

  name          = "${local.prefix}fw-${trimprefix(each.value.name, local.prefix)}-allow-healthcheck"
  network       = each.value.network
  source_ranges = each.key == "port1" ? local.hc_ranges_elb : local.hc_ranges_ilb
  target_tags   = var.fgt_tags

  allow {
    protocol = "TCP"
    ports = [ var.healthcheck_port ]
  }
}

resource "google_compute_firewall" "allowall_port1" {
  name          = "${local.prefix}fw-${trimprefix(var.subnets[0], local.prefix)}-allowall"
  network       = data.google_compute_subnetwork.connected["port1"].network
  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.fgt_tags

  allow {
    protocol = "all"
  }
}
