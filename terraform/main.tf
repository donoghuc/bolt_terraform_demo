
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.40.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

data "google_compute_subnetwork" "subnet" {
  name    = var.subnet
  region  = var.region
  project = var.subnet_project
}

locals {
  network = data.google_compute_subnetwork.subnet.network
  metadata = {
    "ssh-keys" = "${var.user}:${file(var.ssh_key)}"
  }
}

resource "google_compute_instance" "terraform_instance" {
  name         = "terraform-instance-${count.index}"
  count        = var.num_instances
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  metadata = local.metadata

  network_interface {
    network            = local.network
    subnetwork         = var.subnet
    subnetwork_project = var.subnet_project
  }
}
