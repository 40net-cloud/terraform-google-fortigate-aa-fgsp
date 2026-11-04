

/*
resource "google_compute_firewall" "demo" {
  name    = "${var.prefix}-fw-int"
  network = google_compute_network.demo["admin"].self_link

  allow {
    protocol = "tcp"
    ports    = ["22", "443", "8443"]
  }

  source_ranges = ["0.0.0.0/0"]
}
*/

module "fgt" {
  source = "../.."

  subnets = [for net in var.demo_net_names : google_compute_subnetwork.demo[net].name]
  ports = {
    "${var.prefix}-sb-int" : {
      vlan = 10
    }
    "${var.prefix}-sb-admin" : {
      vlan = 20
    }
  }
  prefix                = var.prefix
  region                = var.region
  cluster_size          = 3
  machine_type          = "e2-standard-4"
  flex_tokens           = ["EF95A0EA9CB5BF8BB655", "75D9BCB636D8819083A2", "AD9BDF04A20BF0F4216D"]
  frontends             = ["eip"]
  mgmt_subnet           = google_compute_subnetwork.demo["admin"].name
  mgmt_port_public      = false
  cloudnat_network_tier = "STANDARD"

  image = {
    version = "7.6"
  }

  # remember to add depends_on to delay module's data calls until after the subnets are created, otherwise it will fail with "Error: Error reading Subnetwork: googleapi: Error 404: The resource 'projects/xxx/regions/yyy/subnetworks/zzz' was not found, notFound"
  depends_on = [
    google_compute_subnetwork.demo
  ]
}

output "all" {
  value = module.fgt
}



