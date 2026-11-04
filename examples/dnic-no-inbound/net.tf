#prepare the networks
resource "google_compute_network" "demo" {
  for_each = toset(var.demo_net_names)

  name                    = "${var.prefix}-vpc-${each.value}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "demo" {
  for_each = toset(var.demo_net_names)

  name          = "${var.prefix}-sb-${each.value}"
  region        = var.region
  network       = google_compute_network.demo[each.value].self_link
  ip_cidr_range = var.demo_net_cidrs[each.value]
}
