provider "google" {
  credentials = file(var.service_account_file_path)
  project     = var.prj_id
  region      = var.cloud_region
}

# Loop through the list of VPC configurations and create VPCs
resource "google_compute_network" "vpc" {
  count                           = length(var.vm_instances)
  name                            = var.vm_instances[count.index].vpc_name
  auto_create_subnetworks         = var.vm_instances[count.index].auto_create_subnetworks
  routing_mode                    = var.vm_instances[count.index].vpc_routing_mode
  delete_default_routes_on_create = var.vm_instances[count.index].delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp" {
  count         = length(var.vm_instances)
  name          = var.vm_instances[count.index].vpc_webapp_subnet_name
  ip_cidr_range = var.vm_instances[count.index].vpc_webapp_subnet_cidr
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.cloud_region
}

resource "google_compute_subnetwork" "db" {
  count         = length(var.vm_instances)
  name          = var.vm_instances[count.index].vpc_db_subnet_name
  ip_cidr_range = var.vm_instances[count.index].vpc_db_subnet_cidr
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.cloud_region
}

resource "google_compute_route" "webapp_route" {
  count            = length(var.vm_instances)
  name             = "webapp-route-${count.index}"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.vm_instances[count.index].vpc_dest_range
  next_hop_gateway = var.vm_instances[count.index].next_hop_gateway
}

resource "google_compute_firewall" "allow_ssh_from_iap" {
  count   = length(var.vm_instances)
  name    = "allow-ssh-from-iap-${count.index}"
  network = google_compute_network.vpc[count.index].name

  allow {
    protocol = var.vm_instances[count.index].protocol
    ports    = var.vm_instances[count.index].ports
  }

  source_ranges = var.vm_instances[count.index].src_ranges
  target_tags   = var.vm_instances[count.index].tags
}

resource "google_compute_instance" "webapp_instance" {
  count        = length(var.vm_instances)
  name         = "webapp-instance-${count.index}"
  machine_type = var.vm_instances[count.index].machine_type
  zone         = var.vm_instances[count.index].zone

  boot_disk {
    initialize_params {
      image = var.vm_instances[count.index].boot_disk_image_name
      type  = var.vm_instances[count.index].boot_disk_type
      size  = var.vm_instances[count.index].boot_disk_size
    }
  }

  network_interface {
    network    = google_compute_network.vpc[count.index].self_link
    subnetwork = google_compute_subnetwork.webapp[count.index].self_link
    access_config {

    }

  }


  tags       = var.vm_instances[count.index].tags
  depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_ssh_from_iap]

}

# Define a variable to store VPC configurations
variable "vm_instances" {
  type = list(object({
    vpc_name                        = string
    vpc_webapp_subnet_name          = string
    vpc_webapp_subnet_cidr          = string
    vpc_db_subnet_name              = string
    vpc_db_subnet_cidr              = string
    vpc_routing_mode                = string
    vpc_dest_range                  = string
    auto_create_subnetworks         = bool
    delete_default_routes_on_create = bool
    next_hop_gateway                = string
    boot_disk_image_name            = string
    boot_disk_type                  = string
    boot_disk_size                  = number
    ports                           = list(string)
    src_ranges                      = list(string)
    protocol                        = string
    machine_type                    = string
    zone                            = string
    tags                            = list(string)
  }))
}

variable "service_account_file_path" {
  description = "Filepath of service-account-key.json"
  type        = string
}

variable "prj_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "cloud_region" {
  description = "The GCP cloud_region to create resources in"
  type        = string
}
