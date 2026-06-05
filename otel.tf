# ---------------------------------------------------------------------------
# OpenTelemetry Collector — Cloud Run service that bridges browser RUM (OTLP/HTTP
# from fe-shell) to Cloud Trace + Cloud Monitoring.
#
# The Cloud Run service itself is built + deployed by Cloud Build
# (otel-collector/cloudbuild.yaml), like the front-ends. Terraform owns its
# identity, IAM, and the LB wiring that exposes it same-origin at /otel/*.
# ---------------------------------------------------------------------------

# Dedicated runtime identity for the collector (deployed AS this SA — see
# otel-collector/cloudbuild.yaml). Least privilege: it can only write telemetry.
resource "google_service_account" "otel_collector" {
  account_id   = "otel-collector"
  display_name = "OpenTelemetry Collector (Cloud Run)"
}

resource "google_project_iam_member" "otel_trace" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.otel_collector.email}"
}

resource "google_project_iam_member" "otel_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.otel_collector.email}"
}

data "google_project" "current" {}

# Cloud Build (running as the Compute Engine default SA) deploys the collector
# AS the otel-collector SA, so it needs actAs on it.
resource "google_service_account_iam_member" "otel_cloudbuild_actas" {
  service_account_id = google_service_account.otel_collector.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

# Public invoker so the external LB can reach the collector, matching the
# front-ends' binding in main.tf.
resource "google_cloud_run_v2_service_iam_member" "otel_public" {
  name     = "otel-collector"
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_compute_region_network_endpoint_group" "otel_neg" {
  name                  = "otel-collector-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = "otel-collector"
  }

  depends_on = [google_project_service.apis]
}

resource "google_compute_backend_service" "otel_bes" {
  name                  = "otel-collector-bes"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.otel_neg.id
  }
}
