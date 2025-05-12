# main.tf

data "google_client_config" "default" {}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }

  required_version = ">= 1.3.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  }
}

provider "kubectl" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  load_config_file       = false
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "11.0.0"

  project_id   = var.project_id
  network_name = var.network_name
  routing_mode = "REGIONAL"

  subnets = [
    {
      subnet_name           = var.subnet_name
      subnet_ip             = var.subnet_ip
      subnet_region         = var.region
      subnet_private_access = true
      subnet_flow_logs      = false
      description           = "Primary subnet"
    }
  ]

  secondary_ranges = {
    "${var.subnet_name}" = [
      {
        range_name    = var.ip_range_pods_name
        ip_cidr_range = var.ip_range_pods_cidr
      },
      {
        range_name    = var.ip_range_services_name
        ip_cidr_range = var.ip_range_services_cidr
      }
    ]
  }
}


resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  region  = var.region
  network = module.vpc.network_name
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}


resource "google_compute_address" "ingress_ip_address" {
  name   = "nginx-controller"
  region = var.region
}

# module "nginx-controller" {
#   source     = "terraform-iaac/nginx-controller/helm"
#   version    = "2.3.0"  
#   depends_on = [module.gke]
#   ip_address = google_compute_address.ingress_ip_address.address
# }

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "kube-system"
  create_namespace = true
  version    = "4.7.1"  # Use the latest stable version

  set {
    name  = "controller.service.loadBalancerIP"
    value = google_compute_address.ingress_ip_address.address
  }

  # Enable SSL passthrough
  set {
    name  = "controller.extraArgs.enable-ssl-passthrough"
    value = ""  # Empty string enables the flag
  }
  
  # Additional common configurations
  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }
  
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }
  
  depends_on = [module.gke]
}


module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster"
  project_id         = var.project_id
  name               = var.cluster_name
  region             = var.region
  network            = module.vpc.network_name
  subnetwork         = module.vpc.subnets_names[0]
  ip_range_pods      = var.ip_range_pods_name
  ip_range_services  = var.ip_range_services_name
  release_channel    = var.release_channel
  deletion_protection = false
  master_ipv4_cidr_block = var.master_ipv4_cidr_block
  master_authorized_networks = var.master_authorized_networks
  enable_private_endpoint = var.enable_private_endpoint
  enable_private_nodes    = var.enable_private_nodes

  node_pools = [
    {
      name               = "default-node-pool"
      machine_type       = var.node_machine_type
      min_count          = var.node_min_count
      max_count          = var.node_max_count
      local_ssd_count    = 0
      disk_size_gb       = 100
      disk_type          = "pd-standard"
      image_type         = "COS_CONTAINERD"
      auto-scaling       = true
      auto_repair        = true
      auto_upgrade       = true
      preemptible        = false
      initial_node_count = 1
    }
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# ExternalDNS and cert-manager setup


# First, create the necessary IAM service account for ExternalDNS to access Cloud DNS
resource "google_service_account" "external_dns" {
  account_id   = "external-dns"
  display_name = "ExternalDNS Service Account"
  project      = var.project_id
}

# Grant the DNS Admin role to the service account
resource "google_project_iam_member" "external_dns" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

# Create a single Kubernetes service account for ExternalDNS with the annotations
resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "kube-system"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.external_dns.email
    }
  }
  depends_on = [module.gke]
}

# Use the correct IAM binding for workload identity
resource "google_service_account_iam_binding" "external_dns_iam" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[kube-system/external-dns]"
  ]
  depends_on = [kubernetes_service_account.external_dns]
}

# Install cert-manager using Helm
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.13.2"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.gke]
}

# Install ExternalDNS using Helm with updated configuration
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = "6.28.6"

  set {
    name  = "provider"
    value = "google"
  }

  set {
    name  = "google.project"
    value = var.project_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }
  
  # Important: Make sure ExternalDNS knows to use Workload Identity
  set {
    name  = "google.serviceAccountEmail"
    value = google_service_account.external_dns.email
  }
  
  # Enable workload identity explicitly
  set {
    name  = "podSecurityContext.fsGroup"
    value = "65534"  # Recommended for the bitnami chart
  }
  
  set {
    name  = "podSecurityContext.runAsUser"
    value = "65534"  # Recommended for the bitnami chart
  }
  
  set {
    name  = "logLevel"
    value = "debug"  # Temporary to get more detailed logs
  }

  set {
    name  = "domainFilters[0]"
    value = var.dns_domain  # Only manage records for this domain
  }

  depends_on = [
    kubernetes_service_account.external_dns,
    google_service_account_iam_binding.external_dns_iam
  ]
}

# Create ClusterIssuer for Let's Encrypt
resource "kubectl_manifest" "cluster_issuer" {
  yaml_body = <<-YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${var.email_address}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
  YAML

  depends_on = [helm_release.cert_manager]
}



# resource "helm_release" "vcluster" {
#   for_each = var.vclusters
  
#   name             = each.key
#   namespace        = each.value.namespace
#   create_namespace = true
#   repository       = "https://charts.loft.sh"
#   chart            = "vcluster"
  
#   values = [
#     file(each.value.values_file)
#   ]
  
#   depends_on = [
#     module.gke
#   ]
# }