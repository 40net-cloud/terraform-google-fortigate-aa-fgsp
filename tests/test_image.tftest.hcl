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

run "img_select_by_family_byol" {
  command = plan

  variables {
    image = {
      family = "fortigate-72-byol"
    }
  }

  assert {
    condition     = !strcontains(local.fgt_image.self_link, "ondemand")
    error_message = "PAYG image selected despite BYOL family"
  }

  assert {
    condition     = strcontains(local.fgt_image.self_link, "72")
    error_message = "Image for family fortigate-72-byol should contain '72' substring"
  }
}

run "img_select_by_version" {
  command = plan

  variables {
    image = {
      version = "7.2.6"
    }
  }

  assert {
    condition     = strcontains(local.fgt_image.self_link, "726")
    error_message = "Image selected by firmware version should contain string '726'"
  }
  assert {
    condition     = strcontains(local.fgt_image.self_link, "ondemand")
    error_message = "Image should default to PAYG"
  }
}

run "img_error_license_mismatch" {
  command = plan

  variables {
    flex_tokens = ["DUMMY1", "DUMMY2"]
    image = {
      family = "fortigate-74-payg"
    }
  }

  expect_failures = [
    data.google_compute_image.by_family_name
  ]
}

run "img_auto_byol" {
  command = plan

  variables {
    flex_tokens = ["DUMMY1", "DUMMY2"]
    image = {
      version = "7.4"
    }
  }

  assert {
    condition     = strcontains(local.fgt_image.self_link, "744")
    error_message = "Image selected by firmware version should contain string '744'"
  }
  assert {
    condition     = !strcontains(local.fgt_image.self_link, "ondemand")
    error_message = "Image should switch to BYOL"
  }
}