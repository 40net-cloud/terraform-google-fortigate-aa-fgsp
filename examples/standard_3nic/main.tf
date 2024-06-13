variable "region" {
    type = string
    default = "us-central1"
}


module "fgtaa" {
    source = "../../"

    zones = ["${var.region}-b", "${var.region}-c"]
    prefix = "fgtaa"
    subnets = ["external", "internal", "hasync"]
    frontends = ["eip1"]
    image = {
        version = "7.4"
    }
    license_files = ["/Users/bam/Documents/secrets/licenses/FG-VM04_82489778/FGVM04TM24003301.lic", "/Users/bam/Documents/secrets/licenses/FG-VM04_82489778/FGVM04TM24003302.lic"]
    oslogin_enable = true
    fortimanager = {
        ip = "fmg.gcp.40net.cloud"
        serial = "FMVMELTM23000032"
    }
}

output "fgtaa" {
  value = module.fgtaa
}