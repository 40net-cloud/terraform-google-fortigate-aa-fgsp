terraform {
  required_version = ">= 1.1.0"
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    google-beta = {
      source = "hashicorp/google-beta"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
  }
}

#
# Pull default zones and the service account. Both can be overridden in variables if needed.
#
data "google_compute_zones" "zones_in_region" {
  region = local.region
}

data "google_compute_default_service_account" "default" {}

data "google_client_config" "default" {}

#
# Apply defaults if not overriden in variables, sanitize inputs
#
locals {
  service_account = coalesce(var.service_account, data.google_compute_default_service_account.default.email)
  region          = coalesce(var.region, data.google_client_config.default.region)

  #sanitize labels
  labels = { for k, v in var.labels : k => replace(lower(v), " ", "_") }

  # If prefix is defined, add a "-" spacer after it
  prefix = length(var.prefix) > 0 && substr(var.prefix, -1, 1) != "-" ? "${var.prefix}-" : var.prefix

  # Auto-set NIC type to GVNIC if ARM image was selected
  nic_type = var.image.arch == "arm" ? "GVNIC" : var.nic_type

  # Pick explicit or detected zones and save to locals. limit to 2
  zones = var.zones[0] != "" ? var.zones : data.google_compute_zones.zones_in_region.names
}

# 
# Pull information about subnets we will connect to FortiGate instances. Subnets must
# already exist (can be created in parent module).
#
data "google_compute_subnetwork" "connected" {
  for_each = toset(var.subnets)
  name     = each.value
  region   = local.region
}

#
# We'll use shortened region and zone names for some resource names. This is a standard shortening described in
# GCP security foundations.
#
locals {
  region_short = replace(replace(replace(replace(var.region, "europe-", "eu"), "australia", "au"), "northamerica", "na"), "southamerica", "sa")
  zones_short = [
    replace(replace(replace(replace(local.zones[0], "europe-", "eu"), "australia", "au"), "northamerica", "na"), "southamerica", "sa"),
    replace(replace(replace(replace(local.zones[1], "europe-", "eu"), "australia", "au"), "northamerica", "na"), "southamerica", "sa")
  ]
}

#
# Create FortiGate instances with secondary logdisks and configuration.
#
resource "google_compute_disk" "logdisk" {
  count = var.cluster_size

  name = "${local.prefix}disk-logdisk${count.index + 1}-${local.zones_short[count.index]}"
  size = var.logdisk_size
  type = "pd-ssd"
  zone = local.zones[count.index]
}

#
# Prepare bootstrap data
# - part 1 is optional FortiFlex license token
# - part 2 is bootstrap configuration script built from fgt_config.tftpl template
#
data "cloudinit_config" "fgt" {
  count = var.cluster_size

  gzip          = false
  base64_encode = false

  dynamic "part" {
    for_each = try(var.flex_tokens[count.index], "") == "" ? [] : [1]
    content {
      filename     = "license"
      content_type = "text/plain; charset=\"us-ascii\""
      content      = <<-EOF
        LICENSE-TOKEN: ${var.flex_tokens[count.index]}
        EOF
    }
  }

  part {
    filename     = "config"
    content_type = "text/plain; charset=\"us-ascii\""
    content = templatefile("${path.module}/base_config.tftpl", {
      hostname         = "${local.prefix}vm-fgt${count.index + 1}-${local.zones_short[count.index]}"
      healthcheck_port = var.healthcheck_port
      fgt_config       = var.fgt_config
      # all private addresses for given instance. ordered by subnet/nic index0
      prv_ips = { for indx, addr in google_compute_address.prv : split("_", indx)[0] => addr.address if tonumber(split("_", indx)[1]) == count.index }
      ilb_ips = google_compute_address.ilb
      subnets = { for name, subnet in data.google_compute_subnetwork.connected :
        subnet.ip_cidr_range => {
          "gw" : subnet.gateway_address,
          "dev" : "port${index(var.subnets, name) + 1}",
          "name" : subnet.name
        }
      }
      default_gw = data.google_compute_subnetwork.connected[var.subnets[0]].gateway_address
      ha_indx    = count.index
      #ha_peers               = setsubtract( google_compute_address.fgsp_priv[*].address, [google_compute_address.fgsp_priv[count.index].address])
      # each private address on last interface except for matching the instance index
      ha_peers  = [for key, addr in google_compute_address.prv : addr.address if tonumber(split("_", key)[1]) != count.index && tonumber(split("_", key)[0]) == length(var.subnets) - 1]
      frontends = [for eip in var.frontends : eip]
    })
  }
}


#
# Find image either based on version+arch+lic ...
#
module "fgtimage" {
  count = var.image.version == "" ? 0 : 1

  source = "./modules/fgt-get-image"
  ver    = var.image.version
  arch   = var.image.arch
  lic    = "${try(var.license_files[0], "")}${try(var.flex_tokens[0], "")}" != "" ? "byol" : var.image.lic
}
# ... or based on family/name
data "google_compute_image" "by_family_name" {
  count = var.image.version == "" ? 1 : 0

  project = var.image.project
  family  = var.image.name == "" ? var.image.family : null
  name    = var.image.name != "" ? var.image.name : null

  lifecycle {
    postcondition {
      condition     = !(("${try(var.license_files[0], "")}${try(var.flex_tokens[0], "")}" != "") && strcontains(self.name, "ondemand"))
      error_message = "You provided a FortiGate BYOL (or Flex) license, but you're attempting to deploy a PAYG image. This would result in a double license fee. \nUpdate module's 'image' parameter to fix this error.\n\nCurrent var.image value: \n  {%{for k, v in var.image}%{if tostring(v) != ""}\n    ${k}=${v}%{endif}%{endfor}\n  }"
    }
  }
}
# ... and pick one
locals {
  fgt_image = var.image.version == "" ? data.google_compute_image.by_family_name[0] : module.fgtimage[0].image
}

#
# Deploy VMs
#
resource "google_compute_instance" "fgt-vm" {
  count = var.cluster_size

  zone           = local.zones[count.index % length(local.zones)]
  name           = "${local.prefix}vmfgt${count.index + 1}-${local.zones_short[count.index]}"
  machine_type   = var.machine_type
  can_ip_forward = true
  tags           = var.fgt_tags

  boot_disk {
    initialize_params {
      image = local.fgt_image.self_link
      labels = var.labels
    }
  }
  attached_disk {
    source = google_compute_disk.logdisk[count.index].name
  }
  service_account {
    email  = local.service_account
    scopes = ["cloud-platform"]
  }
  metadata = {
    user-data          = data.cloudinit_config.fgt[count.index].rendered
    license            = fileexists(try(var.license_files[count.index], "null")) ? file(var.license_files[count.index]) : null
    serial-port-enable = var.serial_port_enable
  }

  dynamic "network_interface" {
    for_each = var.subnets

    content {
      subnetwork = network_interface.value
      nic_type   = local.nic_type
      network_ip = google_compute_address.prv["${network_interface.key}_${count.index}"].address
      dynamic "access_config" {
        for_each = contains(var.public_mgmt_nics, "port${network_interface.key + 1}") ? [1] : []
        content {
          nat_ip = google_compute_address.pub["port${network_interface.key + 1}-${count.index}"].address
        }
      }
    }
  }
} //fgt-vm

#
# Common Load Balancer resources
#
resource "google_compute_region_health_check" "health_check" {
  name               = "${local.prefix}healthcheck-http${var.healthcheck_port}-${local.region_short}"
  region             = local.region
  timeout_sec        = 2
  check_interval_sec = 2

  http_health_check {
    port = var.healthcheck_port
  }
}

resource "google_compute_instance_group" "fgt-umigs" {
  count = 2

  name = "${local.prefix}umig${count.index}-${local.region_short}"
  zone = local.zones[count.index]
  instances = matchkeys(
    google_compute_instance.fgt-vm[*].self_link,
    google_compute_instance.fgt-vm[*].zone,
  [local.zones[count.index]])
}

