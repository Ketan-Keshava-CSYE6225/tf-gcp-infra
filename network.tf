provider "google" {
  credentials = file(var.service_account_file_path)
  project     = var.prj_id
  region      = var.cloud_region


# Loop through the list of VPC configurations and create VPCs
resource "google_compute_network" "vpc" {
  count                   = length(var.vpcs)
  name                    = var.vpcs[count.index].vpc_name
  auto_create_subnetworks = var.vpcs[count.index].auto_create_subnetworks
  routing_mode            = var.vpcs[count.index].vpc_routing_mode
  delete_default_routes_on_create = var.vpcs[count.index].delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp" {
  count         = length(var.vpcs)
  name          = var.vpcs[count.index].vpc_webapp_subnet_name
  ip_cidr_range = var.vpcs[count.index].vpc_webapp_subnet_cidr
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.cloud_region
}

resource "google_compute_subnetwork" "db" {
  count         = length(var.vpcs)
  name          = var.vpcs[count.index].vpc_db_subnet_name
  ip_cidr_range = var.vpcs[count.index].vpc_db_subnet_cidr
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.cloud_region
}

resource "google_compute_route" "webapp_route" {
  count             = length(var.vpcs)
  name              = "webapp-route-${count.index}"
  network           = google_compute_network.vpc[count.index].self_link
  dest_range        = var.vpcs[count.index].vpc_dest_range
  next_hop_gateway   = var.vpcs[count.index].next_hop_gateway
}

# Define a variable to store VPC configurations
variable "vpcs" {
  type = list(object({
    vpc_name                      = string
    vpc_webapp_subnet_name        = string
    vpc_webapp_subnet_cidr        = string
    vpc_db_subnet_name            = string
    vpc_db_subnet_cidr            = string
    vpc_routing_mode              = string
    vpc_dest_range                = string
    auto_create_subnetworks       = bool
    delete_default_routes_on_create = bool
    next_hop_gateway              = string
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