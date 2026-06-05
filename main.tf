locals {
  services = toset(["fe-shell", "fe-catalog", "fe-cart"])

  # Only what the load balancer needs. Cloud Run + Artifact Registry are owned by
  # Cloud Build (see each repo's cloudbuild.yaml), not Terraform.
  required_apis = [
    "run.googleapis.com",
    "compute.googleapis.com",
    "cloudbuild.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = var.enable_apis ? toset(local.required_apis) : toset([])
  service            = each.value
  disable_on_destroy = false
}

# The Cloud Run services already exist (built + deployed by Cloud Build).
# Terraform fronts them with the LB and grants the public invoker binding the
# external LB needs to reach them.
resource "google_cloud_run_v2_service_iam_member" "public" {
  for_each = local.services

  name     = each.value
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_compute_region_network_endpoint_group" "neg" {
  for_each = local.services

  name                  = "${each.value}-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = each.value
  }

  depends_on = [google_project_service.apis]
}

resource "google_compute_backend_service" "bes" {
  for_each = local.services

  name                  = "${each.value}-bes"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.neg[each.value].id
  }
}

# ---------------------------------------------------------------------------
# Global External HTTPS Load Balancer — single domain, path-based routing
#   /            -> fe-shell   (default)
#   /fe-catalog/ -> fe-catalog
#   /fe-cart/    -> fe-cart
# Same origin for all three => no CORS needed.
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "default" {
  name = "mfe-ip"
}

resource "google_compute_url_map" "default" {
  name            = "mfe-urlmap"
  default_service = google_compute_backend_service.bes["fe-shell"].id

  host_rule {
    hosts        = [var.domain]
    path_matcher = "mfe"
  }

  path_matcher {
    name            = "mfe"
    default_service = google_compute_backend_service.bes["fe-shell"].id

    path_rule {
      paths   = ["/fe-catalog", "/fe-catalog/*"]
      service = google_compute_backend_service.bes["fe-catalog"].id
    }

    path_rule {
      paths   = ["/fe-cart", "/fe-cart/*"]
      service = google_compute_backend_service.bes["fe-cart"].id
    }
  }
}

resource "google_compute_managed_ssl_certificate" "default" {
  # Name tracks the domain so a domain change provisions a NEW cert and swaps it
  # in before destroying the old one (managed certs can't be deleted while a
  # proxy still references them).
  name = "mfe-cert-${substr(sha1(var.domain), 0, 8)}"

  managed {
    domains = [var.domain]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_target_https_proxy" "default" {
  name             = "mfe-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "mfe-https-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.default.id
  port_range            = "443"
  target                = google_compute_target_https_proxy.default.id
}

# HTTP :80 -> HTTPS redirect
resource "google_compute_url_map" "https_redirect" {
  name = "mfe-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  name    = "mfe-http-proxy"
  url_map = google_compute_url_map.https_redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "mfe-http-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.default.id
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect.id
}

# ---------------------------------------------------------------------------
# Cloud Build GitHub trigger — push to main on GDGoC-BiOn/fe-shell
# Prerequisite: connect the repo once via Cloud Console →
#   Cloud Build > Repositories > Connect Repository (GitHub App).
# ---------------------------------------------------------------------------
resource "google_cloudbuild_trigger" "fe_shell" {
  project     = var.project_id
  name        = "fe-shell-deploy"
  description = "Build and deploy fe-shell on push to main"

  github {
    owner = "GDGoC-BiOn"
    name  = "fe-shell"
    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  depends_on = [google_project_service.apis]
}
