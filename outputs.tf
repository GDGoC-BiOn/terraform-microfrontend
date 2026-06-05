output "load_balancer_ip" {
  description = "Point the domain's DNS A record at this IP."
  value       = google_compute_global_address.default.address
}

output "domain_url" {
  description = "Public URL once DNS + managed cert are ready."
  value       = "https://${var.domain}/"
}

output "ssl_cert_name" {
  description = "Check status with: gcloud compute ssl-certificates describe <name> --global --format='value(managed.status)'"
  value       = google_compute_managed_ssl_certificate.default.name
}
