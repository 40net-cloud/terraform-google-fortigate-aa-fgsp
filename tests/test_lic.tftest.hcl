variables {
  subnets = [
    "external",
    "internal",
    "hasync"
  ]
  region = "us-central1"
  frontends = [
    "eip1"
  ]
}

/*
run "lic_bootstrap_flex" {
  command = apply

  variables {
    image = {
      family = "fortigate-72-byol"
    }
    flex_tokens = [
        "DUMMY1",
        "DUMMY2"
    ]
  }

  assert {
    condition     = strcontains(data.cloudinit_config.fgt[0].rendered, "LICENSE-TOKEN: DUMMY1")
    error_message = "Flex token not found in fgt-vm[0]"
  }
  assert {
    condition     = strcontains(google_compute_instance.fgt-vm[1].metadata.user-data, "LICENSE-TOKEN: DUMMY2")
    error_message = "Flex token not found in fgt-vm[1]"
  }
}*/