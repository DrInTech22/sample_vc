output "vcluster_connect_commands" {
  description = "Commands to connect to the vclusters"
  value = {
    for name, config in var.vclusters : 
    name => "vcluster connect ${name} -n ${config.namespace}"
  }
}

#  Output the Nginx Ingress IP
output "nginx_ingress_ip" {
  description = "Static IP for Nginx Ingress Controller"
  value       = google_compute_address.ingress_ip_address.address
}