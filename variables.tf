variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Region of the existing Cloud Run services / serverless NEGs."
  default     = "asia-southeast2" # Jakarta
}

variable "domain" {
  type        = string
  description = "Single public domain fronting all 3 micro-frontends."
}

variable "enable_apis" {
  type        = bool
  description = "Enable the required GCP APIs (run, compute) as part of this stack."
  default     = true
}
