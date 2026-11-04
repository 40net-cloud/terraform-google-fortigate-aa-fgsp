variable "region" {
  type    = string
  default = "europe-central2"
}

variable "prefix" {
  type    = string
  default = "bm-aa"
}

variable "demo_net_names" {
  type    = list(string)
  default = ["ext", "int", "admin"]
}

variable "demo_net_cidrs" {
  type = map(string)
  default = {
    ext   = "172.20.0.0/24"
    int   = "172.20.1.0/24"
    admin = "172.20.2.0/24"
  }
}
