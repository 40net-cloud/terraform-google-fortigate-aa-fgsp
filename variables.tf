
variable "prefix" {
  type        = string
  default     = "fgt"
  description = "This prefix will be added to all created resources"
}

variable "cluster_size" {
  type        = number
  default     = 2
  description = "How many FortiGates to deploy."
}

# Deployment targets
variable "region" {
  type        = string
  description = "Region to deploy all resources in. Must match var.zones if defined. \nDefaults to provider config."
  default     = ""
}

variable "zones" {
  type        = list(string)
  description = "Names of zones to deploy FortiGate instances to matching the region variable. \nDefaults to zones in given region."
  default     = null
  validation {
    condition     = var.zones == null ? true : length(var.zones) < 4
    error_message = "This module cannot deploy to more than 3 zones"
  }
  validation {
    condition     = var.zones == null ? true : length(distinct([for zone in var.zones : join("-", slice(split("-", zone), 0, 2))])) == 1
    error_message = "All zones must be in the same region"
  }
}

variable "subnets" {
  //TODO: refactor to more flexible structure
  type        = list(string)
  description = "Names of three existing subnets to be connected to FortiGate VMs (external, internal, FGSP sync)"
  validation {
    condition = alltrue([
      for s in var.subnets : try(
        # 1. Full self link
        regex(
          "^https://www.googleapis.com/compute/v1/projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$",
          s
        ),

        # 2. Relative form
        regex(
          "^projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$",
          s
        ),

        # 3. Simple name (RFC1035 style, <=63 chars)
        regex(
          "^[a-z]([-a-z0-9]*[a-z0-9])?$",
          s
        ),

        false
      ) != false
    ])

    error_message = <<EOT
Each subnet must be one of:
- projects/PROJECT/regions/REGION/subnetworks/NAME
- https://www.googleapis.com/compute/v1/projects/PROJECT/regions/REGION/subnetworks/NAME
- A valid subnet name (^[a-z]([-a-z0-9]*[a-z0-9])?$) up to 63 characters
EOT
  }
}

variable "machine_type" {
  type        = string
  default     = "e2-standard-4"
  description = "GCE machine type to use for VMs. Minimum 4 vCPUs are needed for 4 NICs"
}

variable "service_account" {
  type        = string
  default     = ""
  description = "E-mail of service account to be assigned to FortiGate VMs. Defaults to Default Compute Engine Account"
}

variable "frontends" {
  type        = list(any)
  default     = []
  description = "List of public IP names to be linked or created as ELB frontend."
  validation {
    condition     = length(var.frontends) < 33
    error_message = "You can define up to 32 External IP addresses in this module."
  }
}

variable "frontends_obj" {
  type = list(object({
    name    = string
    address = string
  }))
  default     = []
  description = "List of pre-existing IP addresses to be linked as ELB frontends. Use this variable instead of 'frontends' if addresses are created in the same root module as the FortiGates."
}

variable "admin_acl" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDRs allowed to connect to FortiGate management interfaces. Defaults to 0.0.0.0/0"
}
/*
variable api_acl {
  type        = list(string)
  default     = []
  description = "List of CIDRs allowed to connect to FortiGate API (must not be 0.0.0.0/0). Defaults to empty list."
}
*/
variable "healthcheck_port" {
  type        = number
  default     = 8008
  description = "Port used for LB health checks"
}

variable "fgt_config" {
  type        = string
  description = "(optional) Additional configuration script to be added to bootstrap"
  default     = ""
}

variable "logdisk_size" {
  type        = number
  description = "Size of the attached logdisk in GB"
  default     = 30
}

variable "logdisk_type" {
  type        = string
  default     = "pd-ssd"
  description = "Type of disk to use for FortiGate VMs. Check machine type compatibility."
}

variable "api_token_secret_name" {
  type        = string
  description = "Name of Secret Manager secret to be created and used for storing FortiGate API token. If left to empty string the secret will not be created and token will be available in outputs only."
  default     = ""
}


variable "license_files" {
  type        = list(string)
  default     = []
  description = "List of license (.lic) files to be applied for BYOL instances."
}

variable "flex_tokens" {
  type        = list(string)
  description = "(optional) List of FlexVM tokens to apply to FGTs"
  default     = []
}

variable "image" {
  type = object({
    project = optional(string, "fortigcp-project-001")
    name    = optional(string, "")
    family  = optional(string, "fortigate-74-payg")
    version = optional(string, "")
    arch    = optional(string, "x64")
    lic     = optional(string, "payg")
  })
  description = "Indicate FortiOS image you want to deploy by specifying one of the following: image family name (as image.family); firmware version, architecture and licensing (as image.version, image.arch and image.lic); image name (as image.name) optionally with image project name for custom images (as image.project)."
  default = {
    version = "7.2.8"
  }
  validation {
    condition     = contains(["arm", "x64"], var.image.arch)
    error_message = "image.arch must be either 'arm' or 'x64' (default: 'x64')"
  }
  validation {
    condition     = contains(["payg", "byol"], var.image.lic)
    error_message = "image.lic can be either 'payg' or 'byol' (default: 'payg'). For FortiFlex use 'byol'"
  }
  validation {
    condition     = anytrue([length(split(".", var.image.version)) == 3, length(split(".", var.image.version)) == 2, var.image.version == ""])
    error_message = "image.version can be either null, contain FortiOS version in 3-digit format (eg. \"7.4.1\"), or major version in 2-digit format (eg. \"7.4\")"
  }
}

variable "serial_port_enable" {
  type        = bool
  default     = false
  description = "Set to true to enable access to VM serial console"
}

variable "oslogin_enable" {
  type        = bool
  default     = null
  nullable    = true
  description = "Used to enable or disalbe OS Login on the instance level."
}

variable "labels" {
  type        = map(string)
  description = "Map of labels to be applied to the VMs, disks, and forwarding rules"
  default     = {}
}

variable "fgt_tags" {
  type        = list(string)
  default     = ["fgt"]
  description = "List of network tags assigned to FortiGate instance and to be open to all traffic."
}

variable "nic_type" {
  type        = string
  description = "Type of NIC to use for FortiGates. Allowed values are GVNIC or VIRTIO_NET"
  default     = "GVNIC"
  validation {
    condition     = contains(["GVNIC", "VIRTIO_NET"], var.nic_type)
    error_message = "Unsupported value of nic_type variable. Allowed values are GVNIC or VIRTIO_NET."
  }
}
/*
variable "public_nics" {
  type        = list(string)
  nullable = true
  default     = null
  description = "List of FortiGate ports with attached External IPs."
}
*/

variable "fortimanager" {
  type = object({
    ip     = optional(string, null)
    serial = optional(string, null)
  })
  default     = {}
  description = <<EOT
    fortimanager = {
      ip: "IP address of FQDN of the FortiManager to connect to"
      serial: "Serial number of the FortiManager"
    }
  EOT
}

/*
variable "fgsp_port" {
  type        = string
  nullable    = true
  default     = "auto"
  description = "Enforce a custom port for FGSP sync instead of the last one. Provide value as FortiGate port name (eg. \"port3\")"
  validation {
    condition     = var.fgsp_port != "port1"
    error_message = "var.fgsp_port variable cannot be set to port1. To use port1 for both FGSP sync and production traffic set var.fgsp_port to null."
  }
}

variable "mgmt_port" {
  type        = string
  nullable    = true
  default     = null
  description = "Enforce a custom management port instead of the last one. Provide value as FortiGate port name (eg. \"port3\")"
}
*/

variable "fgsp_subnet" {
  type        = string
  nullable    = true
  default     = null
  description = "Name of the subnet to be used for FGSP synchronization. If left to null, the last subnet in var.subnets list will be used."
}

variable "mgmt_subnet" {
  type        = string
  nullable    = true
  default     = null
  description = "Name of the subnet to be used for management. If left to null, the last subnet in var.subnets list will be used."
}

variable "mgmt_port_public" {
  type        = bool
  default     = true
  description = "Should the management port have an external IP address attached. If set to false, management will be possible only using private networking."
}

variable "routes" {
  type        = map(string)
  description = "name=>cidr map of routes to be introduced in internal network"
  default = {
    "default" : "0.0.0.0/0"
  }
}

/*
variable "ports_external" {
  type        = list(string)
  description = "List of ports treated as external. By default [port1]"
  default     = ["port1"]
}
*/

variable "ports" {
  type = map(object({
    vlan        = optional(number, null)
    vlan_parent = optional(string, "port1")
    addresses   = optional(list(string), null)
    public      = optional(bool, null)
  }))
  default     = {}
  description = "(optional) Map of additional properties of ports defined in var.subnets. Key must match subnet **name**, not all subnets need to be here"
}

variable "cloudnat_network_tier" {
  type        = string
  default     = null
  nullable    = true
  description = "Network tier to be used for Cloud NAT. If not set, current project-level default tier is used"
  validation {
    condition     = var.cloudnat_network_tier == null || contains(["PREMIUM", "STANDARD"], coalesce(var.cloudnat_network_tier, "dummy"))
    error_message = "cloudnat_network_tier variable can be either null, PREMIUM, or STANDARD"
  }
}

variable "enable_secure_boot" {
  type        = bool
  default     = true
  nullable    = true
  description = "Set to true to enable Secure Boot on the FortiGate instances. Note that enabling Secure Boot may limit the choice of available machine types and images."
}
