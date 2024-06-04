variable "region" {
    type = string
    default = "us-central1"
}


module "fgtaa" {
    source = "../../"

    region  = var.region
    subnets = ["external", "internal"]
}