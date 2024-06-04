locals {
  network_names = [
    "ext",
    "int",
    "hasync"
  ]

  cidrs = {
    ext = "172.20.0.0/24"
    int = "172.20.1.0/24"
    hasync = "172.20.2.0/24"
  }
}


#prepare the networks
resource google_compute_network "demo" {
  for_each      = toset(local.network_names)

  name          = "fgt-example-vpc-${each.value}"
  auto_create_subnetworks = false
}

resource google_compute_subnetwork "demo" {
  for_each      = toset(local.network_names)

  name          = "fgt-example-sb-${each.value}"
  region        = var.region
  network       = google_compute_network.demo[ each.value ].self_link
  ip_cidr_range = local.cidrs[ each.value ]
}

module "fgt" {
 source = "../.."

 subnets = [ for net in local.network_names : "fgt-example-sb-${net}" ]
 region = var.region
 cluster_size = 3
 machine_type = "e2-standard-4"
 serial_port_enable = true
 flex_tokens = ["EF95A0EA9CB5BF8BB655", "75D9BCB636D8819083A2", "AD9BDF04A20BF0F4216D"]
 frontends = ["eip"]
 fortimanager = {
    ip = "fmg.gcp.40net.cloud"
    serial = "FMVMELTM23000032"
 }

 depends_on = [
    google_compute_subnetwork.demo
 ]
}

output "all" {
    value = module.fgt
}