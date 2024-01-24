output fgt_mgmt_eips {
  value = google_compute_address.mgmt_pub[*].address
}

output fgt_password {
  value = google_compute_instance.fgt-vm[0].instance_id
}

output fgt_self_links {
  value = google_compute_instance.fgt-vm[*].self_link
}

output api_key {
  value = random_string.api_key.result
}

output elb_bes {
    value = google_compute_region_backend_service.elb_bes.self_link
}

output prod_ips {
  value = google_compute_address.prod_priv[*].address
}

output comm_ips {
  value = google_compute_address.comm_priv[*].address
}

output test_ips {
  value = google_compute_address.test_priv[*].address
}

output dev_ips {
  value = google_compute_address.dev_priv[*].address
}
