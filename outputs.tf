output fgt_mgmt_eips {
  value = [ for addr in google_compute_address.mgmt: addr.address ]
}

output fgt_password {
  value = google_compute_instance.fgt_vm[0].instance_id
}

output fgt_self_links {
  value = google_compute_instance.fgt_vm[*].self_link
}

output ilb_addresses {
    value = { for port in local.ports_internal: port=>google_compute_address.ilb[port].address }
}