provider "google" {
  credentials = file(var.service_account_file_path)
  project     = var.prj_id
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
  region        = var.vm_instances[count.index].region

  depends_on = [ google_compute_network.vpc ]
}

resource "google_compute_subnetwork" "db" {
  count                    = length(var.vm_instances)
  name                     = var.vm_instances[count.index].vpc_db_subnet_name
  ip_cidr_range            = var.vm_instances[count.index].vpc_db_subnet_cidr
  network                  = google_compute_network.vpc[count.index].self_link
  region                   = var.vm_instances[count.index].region
  private_ip_google_access = var.vm_instances[count.index].private_ip_google_access_db_subnet

  depends_on = [ google_compute_network.vpc ]

}

resource "google_compute_route" "webapp_route" {
  count            = length(var.vm_instances)
  name             = "webapp-route-${count.index}"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.vm_instances[count.index].vpc_dest_range
  next_hop_gateway = var.vm_instances[count.index].next_hop_gateway
  priority         = var.vm_instances[count.index].vpc_route_webapp_route_priority

  depends_on = [ google_compute_network.vpc ]

}

resource "google_compute_global_address" "private_ip_address" {
  count         = length(var.vm_instances)
  name          = "private-ip-address-${count.index}"
  purpose       = var.vm_instances[count.index].private_ip_address_purpose
  address_type  = var.vm_instances[count.index].private_ip_address_address_type
  prefix_length = var.vm_instances[count.index].private_ip_address_prefix_length
  network       = google_compute_network.vpc[count.index].self_link
  depends_on = [ google_compute_network.vpc ]

}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = length(var.vm_instances)
  network                 = google_compute_network.vpc[count.index].self_link
  service                 = var.vm_instances[count.index].google_service_nw_connection_service
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[count.index].name]

  depends_on = [google_compute_network.vpc, google_compute_global_address.private_ip_address]
}

resource "google_sql_database_instance" "cloud_sql_instance" {
  count               = length(var.vm_instances)
  name                = "private-sql-instance"
  region              = var.vm_instances[count.index].region
  database_version    = var.vm_instances[count.index].postgres_database_version
  root_password       = var.vm_instances[count.index].postgres_root_password
  deletion_protection = var.vm_instances[count.index].cloud_sql_instance_deletion_protection


  settings {
    tier              = var.vm_instances[count.index].cloud_sql_instance_tier
    availability_type = var.vm_instances[count.index].cloud_sql_instance_availability_type
    disk_type         = var.vm_instances[count.index].cloud_sql_instance_disk_type
    disk_size         = var.vm_instances[count.index].cloud_sql_instance_disk_size
    ip_configuration {
      ipv4_enabled                                  = var.vm_instances[count.index].ipv4_enabled
      private_network                               = google_compute_network.vpc[count.index].self_link
      enable_private_path_for_google_cloud_services = var.vm_instances[count.index].db_enable_private_path
    }
  }

  depends_on = [google_compute_network.vpc, google_service_networking_connection.private_vpc_connection]
}

# Creating Cloud SQL database as per guidelines
resource "google_sql_database" "webapp_db" {
  count    = length(var.vm_instances)
  name     = var.vm_instances[count.index].database_name
  instance = google_sql_database_instance.cloud_sql_instance[count.index].name

  depends_on = [ google_sql_database_instance.cloud_sql_instance ]
}

resource "random_password" "webapp_db_password" {
  count            = length(var.vm_instances)
  length           = var.vm_instances[count.index].password_length
  special          = var.vm_instances[count.index].password_includes_special
  override_special = var.vm_instances[count.index].password_override_special
}

# Cloud SQL database user as per guidelines
resource "google_sql_user" "webapp_user" {
  count    = length(var.vm_instances)
  name     = var.vm_instances[count.index].database_user_name
  instance = google_sql_database_instance.cloud_sql_instance[count.index].name
  password = random_password.webapp_db_password[count.index].result

  depends_on = [ google_sql_database_instance.cloud_sql_instance, random_password.webapp_db_password ]
}

resource "google_compute_firewall" "allow_8080" {
  count   = length(var.vm_instances)
  name    = "allow-8080-${count.index}"
  network = google_compute_network.vpc[count.index].name

  allow {
    protocol = var.vm_instances[count.index].protocol
    ports    = var.vm_instances[count.index].ports
  }

  source_ranges = var.vm_instances[count.index].src_ranges
  target_tags   = var.vm_instances[count.index].tags

  priority = var.vm_instances[count.index].allow_8080_priority

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_firewall" "deny_all" {
  count   = length(var.vm_instances)
  name    = "deny-all-${count.index}"
  network = google_compute_network.vpc[count.index].name

  deny {
    protocol = "all"
  }

  source_ranges = var.vm_instances[count.index].src_ranges
  target_tags   = var.vm_instances[count.index].tags

  priority = var.vm_instances[count.index].deny_all_priority

  depends_on = [google_compute_network.vpc]
}

resource "google_service_account" "service_account" {
  account_id                   = var.service_account_account_id
  display_name                 = var.service_account_display_name
  create_ignore_already_exists = var.service_account_create_ignore_already_exists
}

resource "google_project_iam_binding" "service_account_logging_admin" {
  project = var.prj_id
  role    = var.service_account_logging_admin_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "service_account_monitoring_metric_writer" {
  project = var.prj_id
  role    = var.service_account_monitoring_metric_writer_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
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

  allow_stopping_for_update = var.vm_instances[count.index].vm_instance_allow_stopping_for_update

  service_account {
    email  = google_service_account.service_account.email
    scopes = var.vm_instances[count.index].vm_instance_service_account_block_scope
  }
  tags       = var.vm_instances[count.index].tags
  depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_8080, google_compute_firewall.deny_all, google_sql_database.webapp_db, google_sql_user.webapp_user, google_service_account.service_account, google_project_iam_binding.service_account_logging_admin, google_project_iam_binding.service_account_monitoring_metric_writer]

  metadata = {
    startup-script = <<-EOT
#!/bin/bash
set -e
sudo touch /opt/csye6225/webapp/.env

sudo echo "PORT=${var.env_port}" > /opt/csye6225/webapp/.env
sudo echo "DB_NAME=${var.vm_instances[count.index].database_name}" >> /opt/csye6225/webapp/.env
sudo echo "DB_USERNAME=${var.vm_instances[count.index].database_user_name}" >> /opt/csye6225/webapp/.env
sudo echo "DB_PASSWORD=${random_password.webapp_db_password[count.index].result}" >> /opt/csye6225/webapp/.env
sudo echo "DB_HOST=${google_sql_database_instance.cloud_sql_instance[count.index].ip_address.0.ip_address}" >> /opt/csye6225/webapp/.env
sudo echo "DB_DIALECT=${var.env_db_dialect}" >> /opt/csye6225/webapp/.env
sudo echo "DROP_DB=${var.env_db_drop_db}" >> /opt/csye6225/webapp/.env
sudo echo "TOPIC_VERIFY_EMAIL=${var.env_topic_verify_email}" >> /opt/csye6225/webapp/.env
sudo echo "VERIFY_EMAIL_EXPIRY_MILLISECONDS=${var.env_verify_email_expiry_milliseconds}" >> /opt/csye6225/webapp/.env

sudo systemctl daemon-reload
sudo systemctl restart webapp
sudo systemctl daemon-reload
EOT
  }

}

resource "google_dns_record_set" "dns_record" {
  count        = length(var.vm_instances)
  name         = var.vm_instances[count.index].domain_name
  managed_zone = var.vm_instances[count.index].existing_managed_zone
  ttl          = var.vm_instances[count.index].dns_record_ttl

  type    = var.vm_instances[count.index].dns_record_type
  rrdatas = [google_compute_instance.webapp_instance[count.index].network_interface[0].access_config[0].nat_ip]

  depends_on = [google_compute_instance.webapp_instance]
}


variable "service_account_file_path" {
  description = "Filepath of service-account-key.json"
  type        = string
}

variable "prj_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "vm_instances" {
  description = "List of configurations for multiple VPCs"
  type = list(object({
    region                                  = string
    vpc_name                                = string
    vpc_webapp_subnet_name                  = string
    vpc_webapp_subnet_cidr                  = string
    vpc_db_subnet_name                      = string
    vpc_db_subnet_cidr                      = string
    vpc_routing_mode                        = string
    vpc_dest_range                          = string
    auto_create_subnetworks                 = bool
    delete_default_routes_on_create         = bool
    next_hop_gateway                        = string
    vpc_route_webapp_route_priority         = number
    protocol                                = string
    ports                                   = list(string)
    src_ranges                              = list(string)
    tags                                    = list(string)
    machine_type                            = string
    zone                                    = string
    boot_disk_image_name                    = string
    boot_disk_type                          = string
    boot_disk_size                          = number
    allow_8080_priority                     = string
    deny_all_priority                       = string
    private_ip_google_access_webapp_subnet  = bool
    private_ip_google_access_db_subnet      = bool
    google_service_nw_connection_service    = string
    postgres_database_version               = string
    postgres_root_password                  = string
    cloud_sql_instance_deletion_protection  = bool
    ipv4_enabled                            = bool
    cloud_sql_instance_availability_type    = string
    cloud_sql_instance_disk_type            = string
    cloud_sql_instance_disk_size            = number
    database_name                           = string
    password_length                         = number
    password_includes_special               = bool
    password_override_special               = string
    database_user_name                      = string
    private_ip_address_purpose              = string
    private_ip_address_address_type         = string
    private_ip_address_prefix_length        = number
    cloud_sql_instance_tier                 = string
    db_enable_private_path                  = bool
    domain_name                             = string
    existing_managed_zone                   = string
    dns_record_ttl                          = number
    dns_record_type                         = string
    vm_instance_service_account_block_scope = list(string)
    vm_instance_allow_stopping_for_update   = bool
  }))
  default = []
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

variable "service_account_account_id" {
  description = "Account Id"
  type        = string
}

variable "service_account_display_name" {
  description = "Service Account Display Name"
  type        = string
}

variable "service_account_create_ignore_already_exists" {
  description = "Service Account Create Ignore Already Exists"
  type        = bool
}

variable "service_account_logging_admin_role" {
  description = "Service Account Logging Admin Role"
  type        = string
}

variable "service_account_monitoring_metric_writer_role" {
  description = "Service Account Monitoring Metric Writer Role"
  type        = string
}

variable "env_topic_verify_email" {
  description = "Env Topic Verify Email"
  type        = string
}

variable "env_verify_email_expiry_milliseconds" {
  description = "Env Verify Email Expiry Milliseconds"
  type        = number
}