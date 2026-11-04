terraform {
  required_version = ">= 1.1.0"
  required_providers {
    google = {
      source = "hashicorp/google"
      # 7.19 required for vlans
      version = ">= 7.19.0"
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
  # if service account is not passed explicitly in variable, pick the default Compute Engine account
  service_account = coalesce(var.service_account, data.google_compute_default_service_account.default.email)

  # derive region from zones if provided, otherwise use the region from variable, as last resort use default region from provider
  region = coalesce(try(join("-", slice(split("-", var.zones[0]), 0, 2)), null), var.region, data.google_client_config.default.region)

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

  # Calculate port1 for management or copy from vars. Used for FGT configuration bootstrap, ACL, and public IPs. 
  mgmt_subnet = var.mgmt_subnet != null ? var.mgmt_subnet : data.google_compute_subnetwork.connected[0].name

  # Calculate FGSP port (last one) if set to "auto", otherwise use variable. Null means no dedicated port => FGSP over port1.
  dedicated_fgsp_subnet = var.fgsp_subnet != "auto" ? var.fgsp_subnet : data.google_compute_subnetwork.connected[length(var.subnets) - 1].name
  fgsp_subnet           = coalesce(local.dedicated_fgsp_subnet, data.google_compute_subnetwork.connected[0].name)

  #
  # Create common lists
  #
  hc_ranges_ilb = ["35.191.0.0/16", "130.211.0.0/22"]
  hc_ranges_elb = ["35.191.0.0/16", "209.85.152.0/22", "209.85.204.0/22"]

  # List of all subnet names (cleaned-up version of var.subnets with self-links converted to names). Used for looping and lookups.
  subnets_all = data.google_compute_subnetwork.connected[*].name
  # Map of subnet name to subnet object for easier lookups
  connected_subnets = { for subnet in data.google_compute_subnetwork.connected : subnet.name => subnet }
  # List of all subnet names without prefix and regionshort suffixes, used for cleaner resource names
  root_subnet_names = { for subnet in data.google_compute_subnetwork.connected :
    subnet.name => trimsuffix(trimprefix(subnet.name, local.prefix), "-${local.region_short}")
  }
  # List of traffic subnet names with ELBs (if marked in var.ports as public, falls back to first subnet if not specified).
  subnets_public = setunion(
    [for net in local.subnets_all : net if coalesce(try(var.ports[net].public, false), false)],
    try(var.ports[0].public, null) == null ? [local.subnets_all[0]] : []
  )
  # List of traffic subnet names for ILBs (all - public - fgsp - mgmt)
  subnets_internal = setsubtract(local.subnets_all, setunion(local.subnets_public, [local.dedicated_fgsp_subnet, local.mgmt_subnet]))
  # List of all FortiGate names based on cluster size, used for looping and naming
  fgts = [for indx in range(var.cluster_size) : "fgt${indx + 1}"]
}

output "subnets_public" {
  value = local.subnets_public
}
output "subnets_internal" {
  value = local.subnets_internal
}
output "subnet_fgsp" {
  value = local.dedicated_fgsp_subnet
}
output "subnet_mgmt" {
  value = local.mgmt_subnet
}

## locals to produce names of ports for each subnet
# Accepts parent NICs in both Forti and Google formats
locals {
  snic_nets = [for net in local.subnets_all : net if !can(var.ports[net].vlan)]

  # map of standard NIC names
  snics = { for indx in range(length(local.snic_nets)) : local.snic_nets[indx] => "port${indx + 1}" }

  # map of dynamic NIC names
  dnics = { for net in local.subnets_all : net => can(regex("^port\\d+$", var.ports[net].vlan_parent)) ?
    "${var.ports[net].vlan_parent}.${var.ports[net].vlan}" :
    "port${tonumber(regex("\\d+$", var.ports[net].vlan_parent) + 1)}.${var.ports[net].vlan}"
  if can(var.ports[net].vlan) }

  # map of all NIC names in Forti format (port1, port2, port3.10, ...)
  nic_names = merge(local.snics, local.dnics)

  # map of dynamic NIC names in GCP format (nic0.10, nic1.20, ...)
  dnics_gcp = { for net, port in local.dnics : net => "nic${tonumber(regex("\\d+$", port)) - 1}" }

}


# 
# Pull information about subnets we will connect to FortiGate instances. Subnets must
# already exist (can be created in parent module).
# NOTE: do not change this as it's the basis for all networking in the module.
# Ordered list
#
data "google_compute_subnetwork" "connected" {
  count = length(var.subnets)

  self_link = try(
    # Case 1: already full URL
    regex(
      "^https://www.googleapis.com/compute/v1/projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$",
      var.subnets[count.index]
    ),

    # Case 2: short form → convert to full URL
    "https://www.googleapis.com/compute/v1/${regex(
      "^projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$",
      var.subnets[count.index]
    )}",
    # If neither matches
    null
  )
  name   = var.subnets[count.index]
  region = local.region
}

#
# We'll use shortened region and zone names for some resource names. This is a standard shortening described in
# GCP security foundations.
#
locals {
  region_short = replace(replace(replace(replace(replace(replace(replace(replace(replace(local.region, "-south", "s"), "-east", "e"), "-central", "c"), "-north", "n"), "-west", "w"), "europe", "eu"), "australia", "au"), "northamerica", "na"), "southamerica", "sa")
  zones_short = [for zone in local.zones3 :
    "${local.region_short}${substr(zone, length(local.region) + 1, 1)}"
  ]
}

#
# Create FortiGate instances with secondary logdisks and configuration.
#
resource "google_compute_disk" "logdisk" {
  count = var.logdisk_size > 0 ? var.cluster_size : 0

  name   = "${local.prefix}disk-logdisk${count.index + 1}-${local.zones_short[count.index % length(local.zones)]}"
  size   = var.logdisk_size
  type   = var.logdisk_type
  zone   = local.zones[count.index]
  labels = var.labels
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
    content = templatefile("${path.module}/base_config_dnic.tftpl", {
      hostname         = "${local.prefix}${local.fgts[count.index]}-${local.zones_short[count.index % length(local.zones)]}"
      healthcheck_port = var.healthcheck_port
      # all private addresses for given instance. ordered by subnet/nic index0
      prv_ips = { for indx, addr in google_compute_address.prv : split("|", indx)[1] => addr.address
        if tonumber(regex("\\d+$", split("|", indx)[0])) - 1 == count.index
      }
      snics = { for net, port in local.snics : port => {
        subnet  = net
        address = google_compute_address.prv["fgt${count.index + 1}|${net}"].address
      } }
      dnics = { for net, port in local.dnics : port => {
        subnet      = net
        address     = google_compute_address.prv["fgt${count.index + 1}|${net}"].address
        vlan        = var.ports[net].vlan
        vlan_parent = var.ports[net].vlan_parent
      } }

      ilb_ips = { for indx, addr in google_compute_address.ilb : local.nic_names[indx] => addr.address }
      ## reverse indexing in case we wanted more subnets per port in future
      subnets = { for subnet in data.google_compute_subnetwork.connected :
        subnet.ip_cidr_range => {
          "dev" : local.nic_names[subnet.name],
          "name" : subnet.name
        }
      }
      gateways = { for net, port in local.nic_names : port => local.connected_subnets[net].gateway_address }
      ha_indx  = count.index
      # each private address on last interface except for matching the instance index
      ha_peers = [for key, addr in google_compute_address.prv :
        addr.address if tonumber(regex("\\d+$", split("|", key)[0])) - 1 != count.index && split("|", key)[1] == local.fgsp_subnet
      ]
      frontends        = concat([for eip in var.frontends : try(local.eip_all[eip], local.eip_all[eip.name])], [for eipobj in var.frontends_obj : eipobj.address])
      mgmt_port        = local.nic_names[local.mgmt_subnet]
      mgmt_port_public = var.mgmt_port_public
      admin_acl        = var.admin_acl
      fortimanager     = var.fortimanager
      fgt_config       = var.fgt_config
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
  name           = "${local.prefix}vm-${local.fgts[count.index]}-${local.zones_short[count.index % length(local.zones)]}"
  machine_type   = var.machine_type
  can_ip_forward = true
  tags           = var.fgt_tags

  boot_disk {
    initialize_params {
      image  = local.fgt_image.self_link
      labels = var.labels
    }
  }
  dynamic "attached_disk" {
    for_each = var.logdisk_size > 0 ? [1] : []
    content {
      source = google_compute_disk.logdisk[count.index].name
    }
  }
  service_account {
    email  = local.service_account
    scopes = ["cloud-platform"]
  }
  shielded_instance_config {
    enable_secure_boot = var.enable_secure_boot
  }

  metadata = {
    user-data          = data.cloudinit_config.fgt[count.index].rendered
    license            = fileexists(try(var.license_files[count.index], "null")) ? file(var.license_files[count.index]) : null
    serial-port-enable = var.serial_port_enable
    oslogin-enable     = var.oslogin_enable
  }

  dynamic "network_interface" {
    for_each = data.google_compute_subnetwork.connected
    iterator = subnet

    content {
      subnetwork = subnet.value.self_link
      nic_type   = try(var.ports[subnet.value.name].vlan, null) == null ? local.nic_type : null
      network_ip = google_compute_address.prv["fgt${count.index + 1}|${subnet.value.name}"].address
      vlan       = try(var.ports[subnet.value.name].vlan, null)
      dynamic "access_config" {
        for_each = var.mgmt_port_public && local.mgmt_subnet == subnet.value.name ? [1] : []
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
