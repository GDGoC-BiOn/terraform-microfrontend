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

output "otel_collector_url" {
  description = "OTLP/HTTP ingest base URL the fe-shell RUM SDK posts to (VITE_OTEL_URL)."
  value       = "https://${var.domain}/otel"
}

output "otel_collector_sa" {
  description = "Runtime SA the collector deploys as (otel-collector/cloudbuild.yaml _RUNTIME_SA)."
  value       = google_service_account.otel_collector.email
}
