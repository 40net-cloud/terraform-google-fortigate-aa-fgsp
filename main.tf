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
  region          = coalesce(var.region, join("-", slice(split("-", var.zones[0]), 0, 2)), data.google_client_config.default.region)

  #sanitize labels
  labels = { for k, v in var.labels : k => replace(lower(v), " ", "_") }

  # If prefix is defined, add a "-" spacer after it
  prefix = length(var.prefix) > 0 && substr(var.prefix, -1, 1) != "-" ? "${var.prefix}-" : var.prefix

  # Auto-set NIC type to GVNIC if ARM image was selected
  nic_type = var.image.arch == "arm" ? "GVNIC" : var.nic_type

  # Pick explicit or detected zones and save to locals. Limit auto-zones to 3
  zones = var.zones != null ? var.zones : slice(data.google_compute_zones.zones_in_region.names, 0, 3)

  # List of used UMIG zones optionally padded by some unsed to make it always 3. See umigs resource at the end of this file for details
  zones3 = slice(concat(local.zones, compact([for i in data.google_compute_zones.zones_in_region.names : contains(local.zones, i) ? null : i])), 0, 3)

  # Calculate last port for management or copy from vars. Used for FGT configuration bootstrap, ACL, and public IPs. 
  mgmt_port = var.mgmt_port != null ? var.mgmt_port : "port${length(var.subnets)}"

  # Calculate FGSP port (last one)
  fgsp_port = var.fgsp_port != null ? var.fgsp_port : "port${length(var.subnets)}"

  #
  # Create common lists
  #
  hc_ranges_ilb = ["35.191.0.0/16", "130.211.0.0/22"]
  hc_ranges_elb = ["35.191.0.0/16", "209.85.152.0/22", "209.85.204.0/22"]
  ports_all = [ for indx in range(length(var.subnets)) : "port${indx+1}"]
  //ports_internal = slice( local.ports_all, 1, length(var.subnets)-1 )
  ports_internal = setsubtract( local.ports_all, setunion(var.ports_external, [local.mgmt_port]))
  fgts = [ for indx in range(var.cluster_size) : "fgt${indx+1}" ]
}


# 
# Pull information about subnets we will connect to FortiGate instances. Subnets must
# already exist (can be created in parent module).
# Index by port name
#
data "google_compute_subnetwork" "connected" {
  for_each = toset([for indx in range(length(var.subnets)) : "port${indx + 1}"]) #toset(var.subnets)
  name     = var.subnets[substr(each.value, 4, 1)-1]
  region   = local.region
}

#
# We'll use shortened region and zone names for some resource names. This is a standard shortening described in
# GCP security foundations.
#
locals {
  region_short = replace(replace(replace(replace(replace(replace(replace(replace(replace(local.region, "-south", "s"), "-east", "e"), "-central", "c"), "-north", "n"), "-west", "w"), "europe", "eu"), "australia", "au"), "northamerica", "na"), "southamerica", "sa")
  zones_short = [ for zone in local.zones3 :
    "${local.region_short}${substr(zone, length(local.region) + 1, 1)}"
  ]
}

#
# Create FortiGate instances with secondary logdisks and configuration.
#
resource "google_compute_disk" "logdisk" {
  count = var.cluster_size

  name = "${local.prefix}disk-logdisk${count.index + 1}-${local.zones_short[count.index%length(local.zones)]}"
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
      hostname         = "${local.prefix}fgt${count.index + 1}-${local.zones_short[count.index%length(local.zones)]}"
      healthcheck_port = var.healthcheck_port
      fgt_config       = "" #var.fgt_config
      # all private addresses for given instance. ordered by subnet/nic index0
      prv_ips = { for indx, addr in google_compute_address.prv : split("_", indx)[0] => addr.address if tonumber(split("_", indx)[1]) == count.index }
      ilb_ips = google_compute_address.ilb
      ## reverse indexing in case we wanted more subnets per port in future
      subnets = { for port, subnet in data.google_compute_subnetwork.connected :
        subnet.ip_cidr_range => {
          "dev" : port,
          "name" : subnet.name
        }
      }
      gateways = { for port, subnet in data.google_compute_subnetwork.connected : port=>subnet.gateway_address }
      ha_indx    = count.index
      # each private address on last interface except for matching the instance index
      ha_peers  = [for key, addr in google_compute_address.prv : addr.address if tonumber(split("_", key)[1]) != count.index && split("_", key)[0] == local.fgsp_port]
      frontends = [for eip in var.frontends : try(local.eip_all[eip], local.eip_all[eip.name])]
      mgmt_port = local.mgmt_port
      mgmt_port_public = var.mgmt_port_public
      fortimanager = var.fortimanager
      fgt_config = var.fgt_config
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
resource "google_compute_instance" "fgt_vm" {
  count = var.cluster_size

  zone           = local.zones[count.index % length(local.zones)]
  name           = "${local.prefix}vm-${local.fgts[count.index]}-${local.zones_short[count.index%length(local.zones)]}"
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
    oslogin-enable = var.oslogin_enable
  }

  dynamic "network_interface" {
    for_each = data.google_compute_subnetwork.connected

    content {
      subnetwork = network_interface.value.name
      nic_type   = local.nic_type
      network_ip = google_compute_address.prv["${network_interface.key}_${count.index}"].address
      dynamic "access_config" {
        for_each = var.mgmt_port_public && local.mgmt_port == network_interface.key ? [1] : []
        content {
          nat_ip = google_compute_address.mgmt[local.fgts[count.index]].address
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

resource "google_compute_instance_group" "fgt_umigs" {
  # note that the number of UMIGs must be known before applying (before reading zone list if no variable is given)
  # so, the number of UMIGs cannot be dynamic. We limit auto-detected zones and var length to 3, so let's stick to 3.
  # If deployed to 2 zones only, we still create a dummy 3rd UMIG. To avoid inambiguity it should be located in an unused zone - 
  # that's were we take an unused zone from those available in the region.
  count = 3

  name = "${local.prefix}umig-${local.zones_short[count.index]}"

  zone = local.zones3[count.index]
  instances = matchkeys(
    google_compute_instance.fgt_vm[*].self_link,
    google_compute_instance.fgt_vm[*].zone,
  [local.zones3[count.index]])
}