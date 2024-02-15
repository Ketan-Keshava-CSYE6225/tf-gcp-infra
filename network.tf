provider "google" {
  credentials = file(var.service_account_file_path)
  project     = var.prj_id
  region      = var.cloud_region
}

resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = var.auto_create_subnetworks
  routing_mode = var.vpc_routing_mode
  delete_default_routes_on_create = var.delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp" {
  name          = var.vpc_webapp_subnet_name
  ip_cidr_range = var.vpc_webapp_subnet_cidr
  network       = google_compute_network.vpc.self_link
  region        = var.cloud_region
}

resource "google_compute_subnetwork" "db" {
  name          = var.vpc_db_subnet_name
  ip_cidr_range = var.vpc_db_subnet_cidr
  network       = google_compute_network.vpc.self_link
  region        = var.cloud_region
}

resource "google_compute_route" "webapp_route" {
  name              = "webapp-route"
  network           = google_compute_network.vpc.self_link
  dest_range        = var.vpc_dest_range
  next_hop_gateway   = var.next_hop_gateway
}

variable "service_account_file_path" {
  description = "Filepath of service-account-key.json"
  type        = string
}

variable "vpc_dest_range" {
  description = "Destination IP range for the route"
  type        = string
}

variable "next_hop_gateway" {
  description = "Next hop gateway for the route"
  type        = string
}

variable "auto_create_subnetworks" {
  description = "Whether to auto-create subnetworks in the VPC"
  type        = bool
}

variable "vpc_routing_mode" {
  description = "Routing mode for the VPC"
  type        = string
}

variable "delete_default_routes_on_create" {
  description = "Whether to delete default routes on VPC creation"
  type        = bool
}

variable "vpc_db_subnet_name" {
  description = "Name of the db subnet to be created"
  type        = string
}

variable "vpc_db_subnet_cidr" {
  description = "CIDR range for the db subnet"
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

variable "vpc_name" {
  description = "Name of the VPC to be created"
  type        = string
}

variable "vpc_webapp_subnet_name" {
  description = "Name of the webapp subnet to be created"
  type        = string
}

variable "vpc_webapp_subnet_cidr" {
  description = "CIDR range for the webapp subnet"
  type        = string
}