variable "project_id" {
  description = "The project ID to deploy resources into"
  type        = string
}

variable "region" {
  description = "The region to deploy the cluster"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "subnet_ip" {
  description = "Primary IP CIDR for the subnet"
  type        = string
}

variable "ip_range_pods_name" {
  description = "The name of the secondary subnet ip range to use for pods"
  type        = string
}

variable "ip_range_pods_cidr" {
  description = "The CIDR for the secondary subnet ip range to use for pods"
  type        = string
}

variable "ip_range_services_name" {
  description = "The name of the secondary subnet range to use for services"
  type        = string
}

variable "ip_range_services_cidr" {
  description = "The CIDR for the secondary subnet range to use for services"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "release_channel" {
  description = "GKE release channel"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the GKE master's private IP"
  type        = string
}

variable "master_authorized_networks" {
  description = "Authorized CIDR blocks for GKE master access"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint"
  type        = bool
}

variable "enable_private_nodes" {
  description = "Enable private nodes"
  type        = bool
}

variable "node_machine_type" {
  description = "Machine type for node pool"
  type        = string
}

variable "node_min_count" {
  description = "Minimum number of nodes in node pool"
  type        = number
}

variable "node_max_count" {
  description = "Maximum number of nodes in node pool"
  type        = number
}

# vcluster
variable "vclusters" {
  description = "Map of vcluster configurations"
  type = map(object({
    namespace = string
    values_file = string
  }))
  default = {}
}

variable "email_address" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
}

variable "dns_domain" {
  description = "The DNS domain to use for ExternalDNS (e.g., example.com)"
  type        = string
}
