variable "project_id" {
  description = "GCP project ID the lakehouse is deployed into"
  type        = string
}

variable "region" {
  description = "Primary GCP region for storage and compute resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod) — used as a resource naming suffix"
  type        = string
  default     = "dev"
}

variable "lake_domains" {
  description = "List of business domains, each gets its own Dataplex Lake and dataset set"
  type        = list(string)
  default     = ["customer", "operations"]
}

variable "data_owner_group" {
  description = "Google Group email that owns/administers the lakehouse datasets"
  type        = string
  default     = "data-platform-team@example.com"
}

variable "analytics_reader_group" {
  description = "Google Group email granted read access to Gold-layer datasets only"
  type        = string
  default     = "analytics-readers@example.com"
}
