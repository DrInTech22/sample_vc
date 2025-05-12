# Network
project_id                    = "yamifystaging"
region                        = "us-central1"
network_name                  = "gke-vpc"
subnet_name                   = "gke-subnet"
subnet_ip                     = "10.10.0.0/16"

# Secondary ranges
ip_range_pods_name      = "ip-range-pods"
ip_range_pods_cidr      = "10.20.0.0/16"
ip_range_services_name  = "ip-range-services"
ip_range_services_cidr  = "10.30.0.0/20"

cluster_name                  = "private-gke-cluster"
release_channel               = "REGULAR"
master_ipv4_cidr_block        = "172.16.0.0/28"

master_authorized_networks = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "all"
  }
]

enable_private_endpoint = false
enable_private_nodes    = true

node_machine_type = "e2-medium"
node_min_count    = 1
node_max_count    = 3

email_address = "samuelokesanya12@gmail.com"
dns_domain    = "aiscaler.ai"


# VCluster
vclusters = {
  "team-a-vcluster" = {
    namespace   = "team-a"
    values_file = "team-a.yaml"
  }#,
  # "team-b-vcluster" = {
  #   namespace   = "team-b"
  #   values_file = "team-b-values.yaml"
  # },
  # "team-c-vcluster" = {
  #   namespace   = "team-c"
  #   values_file = "team-c-values.yaml"
  # }
}