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
  private_ip_google_access = var.vm_instances[count.index].private_ip_google_access_webapp_subnet
}

resource "google_compute_subnetwork" "db" {
  count         = length(var.vm_instances)
  name          = var.vm_instances[count.index].vpc_db_subnet_name
  ip_cidr_range = var.vm_instances[count.index].vpc_db_subnet_cidr
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.cloud_region
  private_ip_google_access = var.vm_instances[count.index].private_ip_google_access_db_subnet
}

resource "google_compute_route" "webapp_route" {
  count            = length(var.vm_instances)
  name             = "webapp-route-${count.index}"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.vm_instances[count.index].vpc_dest_range
  next_hop_gateway = var.vm_instances[count.index].next_hop_gateway
}

resource "google_compute_global_address" "private_ip_address" {
  count         = length(var.vm_instances)
  name          = "private-ip-address-${count.index}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.vpc[count.index].self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = length(var.vm_instances)
  network                 = google_compute_network.vpc[count.index].self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[count.index].name]
  depends_on              = [google_compute_network.vpc]
  deletion_policy         = "ABANDON"
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "cloud_sql_instance" {

  count            = length(var.vm_instances)
  name             = "private-sql-instance-${random_id.db_name_suffix.hex}"
  region           = var.cloud_region
  database_version = var.vm_instances[count.index].postgres_database_version
  deletion_protection = var.vm_instances[count.index].cloud_sql_instance_deletion_protection

  depends_on = [google_service_networking_connection.private_vpc_connection, google_compute_network.vpc]

  settings {
    tier              = "db-f1-micro"
    availability_type = var.vm_instances[count.index].cloud_sql_instance_availability_type
    disk_type         = var.vm_instances[count.index].cloud_sql_instance_disk_type
    disk_size         = var.vm_instances[count.index].cloud_sql_instance_disk_size
    ip_configuration {
      ipv4_enabled                                  = var.vm_instances[count.index].ipv4_enabled
      private_network                               = google_compute_network.vpc[count.index].self_link
      enable_private_path_for_google_cloud_services = true
    }
  }
}

# Creating Cloud SQL database as per guidelines
resource "google_sql_database" "webapp_db" {
  count    = length(var.vm_instances)
  name     = "webapp-db-${count.index}"
  instance = google_sql_database_instance.cloud_sql_instance[count.index].name
}

# Cloud SQL database user as per guidelines
resource "google_sql_user" "webapp_user" {
  count    = length(var.vm_instances)
  name     = "webapp-user-${count.index}"
  instance = google_sql_database_instance.cloud_sql_instance[count.index].name
  password = random_password.webapp_db_password.result
}

# Generating random password for the user
resource "random_password" "webapp_db_password" {
  length  = 10
  special = true
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

  priority = var.vm_instances[count.index].allow_8080_priority
}

resource "google_compute_firewall" "deny_all" {
  count   = length(var.vm_instances)
  name    = "deny-all-${count.index}"
  network = google_compute_network.vpc[count.index].name

  deny {
    protocol = "all"
    ports    = []
  }

  source_ranges = var.vm_instances[count.index].src_ranges
  target_tags   = var.vm_instances[count.index].tags

  priority = var.vm_instances[count.index].deny_all_priority
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
  depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_ssh_from_iap, google_compute_firewall.deny_all]

  metadata = {
    startup-script = <<-EOT
#!/bin/bash
set -e
sudo touch /opt/csye6225/webapp/.env

sudo echo "PORT=${var.env_port}" > /opt/csye6225/webapp/.env
sudo echo "DB_NAME=${var.vm_instances[count.index].database_name}" >> /opt/csye6225/webapp/.env
sudo echo "DB_USERNAME=${var.vm_instances[count.index].database_user_name}" >> /opt/csye6225/webapp/.env
sudo echo "DB_PASSWORD=${random_password.webapp_db_password.result}" >> /opt/csye6225/webapp/.env
sudo echo "DB_HOST=${google_sql_database_instance.cloud_sql_instance[count.index].ip_address.0.ip_address}" >> /opt/csye6225/webapp/.env
sudo echo "DB_DIALECT=${var.env_db_dialect}" >> /opt/csye6225/webapp/.env
sudo echo "DROP_DB=${var.env_db_drop_db}" >> /opt/csye6225/webapp/.env

sudo systemctl restart webapp

sudo systemctl daemon-reload
EOT
  }

}

# Define a variable to store VPC configurations
variable "vm_instances" {
  type = list(object({
    vpc_name                               = string
    vpc_webapp_subnet_name                 = string
    vpc_webapp_subnet_cidr                 = string
    vpc_db_subnet_name                     = string
    vpc_db_subnet_cidr                     = string
    vpc_routing_mode                       = string
    vpc_dest_range                         = string
    auto_create_subnetworks                = bool
    delete_default_routes_on_create        = bool
    next_hop_gateway                       = string
    boot_disk_image_name                   = string
    boot_disk_type                         = string
    boot_disk_size                         = number
    ports                                  = list(string)
    src_ranges                             = list(string)
    protocol                               = string
    machine_type                           = string
    zone                                   = string
    tags                                   = list(string)
    allow_8080_priority                    = number
    deny_all_priority                      = number
    private_ip_google_access_webapp_subnet = bool
    private_ip_google_access_db_subnet     = bool
    postgres_database_version              = string
    cloud_sql_instance_deletion_protection = bool
    ipv4_enabled                           = bool
    cloud_sql_instance_availability_type   = string
    cloud_sql_instance_disk_type           = string
    cloud_sql_instance_disk_size           = number
    database_name                          = string
    database_user_name                     = string
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

variable "env_port" {
  description = "ENV port"
  type        = string
}

variable "env_db_dialect" {
  description = "ENV DB dialect"
  type        = string
}

variable "env_db_drop_db" {
  description = "ENV Drop DB"
  type        = bool
}