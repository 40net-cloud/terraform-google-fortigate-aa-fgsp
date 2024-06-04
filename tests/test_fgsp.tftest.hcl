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

run "fgsp_port_explicit" {
  command = plan

  variables {
    fgsp_port = "port2"
  }

  assert {
    condition     = local.fgsp_port == "port2"
    error_message = "Dedicated FGSP port from variable not passed to local"
  }
  assert {
    condition     = local.dedicated_fgsp_port == "port2"
    error_message = "incorrect dedicated_fgsp_port"
  }
  assert {
    condition     = !contains(local.ports_internal, "port2")
    error_message = "Dedicated FGSP port found in local.ports_internal list"
  }
  assert {
    condition = keys(google_compute_forwarding_rule.ilbs) == ["port3"]
    error_message = "ILB forwarding rules count not matching desired list of internal ports [port3]"
  }
}

run "fgsp_port_auto_default" {
  command = plan

  variables {
  }

  assert {
    condition     = local.fgsp_port == "port3"
    error_message = "Dedicated FGSP port not calculated properly into to local"
  }
  assert {
    condition     = local.dedicated_fgsp_port == "port3"
    error_message = "Incorrect dedicated_fgsp_port"
  }
  assert {
    condition     = !contains(local.ports_internal, "port3")
    error_message = "Dedicated FGSP port found in local.ports_internal list"
  }
  assert {
    condition = keys(google_compute_forwarding_rule.ilbs) == ["port2"]
    error_message = "ILB forwarding rules count not matching desired list internal of ports [port2]"
  }
}

run "fgsp_port_null" {
  command = plan

  variables {
    fgsp_port = null
  }

  assert {
    condition     = local.fgsp_port == "port1"
    error_message = "Dedicated FGSP port not calculated properly into to local"
  }
  assert {
    condition     = local.dedicated_fgsp_port == null
    error_message = "dedicated_fgsp_port set to not null"
  }
  assert {
    condition     = contains(local.ports_internal, "port3") && contains(local.ports_internal, "port2")
    error_message = "Missing port in local.ports_internal list"
  }
  assert {
    condition = keys(google_compute_forwarding_rule.ilbs) == ["port2", "port3"]
    error_message = "ILB forwarding rules count not matching desired internal ports [port2,port3]"
  }
}