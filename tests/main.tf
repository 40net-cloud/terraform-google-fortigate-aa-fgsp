module "fgt_aa_fgsp" {
    source = "./.."

    prefix = var.prefix
    cluster_size = var.cluster_size
    region = var.region
    zones = var.zones
    subnets = var.subnets
    machine_type = var.machine_type
    service_account = var.service_account
    frontends = var.frontends
    admin_acl = var.admin_acl
    healthcheck_port = var.healthcheck_port
    fgt_config = var.fgt_config
    logdisk_size = var.logdisk_size
    license_files = var.license_files
    flex_tokens = var.flex_tokens
    image = var.image
    serial_port_enable = var.serial_port_enable
    labels = var.labels
    fgt_tags = var.fgt_tags
    nic_type = var.nic_type
    public_mgmt_nics = var.public_mgmt_nics
}

output module {
    value = module.fgt_aa_fgsp
}