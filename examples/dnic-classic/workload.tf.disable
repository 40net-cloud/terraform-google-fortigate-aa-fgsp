resource "google_compute_instance" "cli2" {
  name = "${var.prefix}-lx"
  zone = "${var.region}-b"

  machine_type = "e2-micro"
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.demo["int"].id
  }
  tags = ["ssh", "cli2"]
}
