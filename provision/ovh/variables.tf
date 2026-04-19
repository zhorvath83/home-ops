variable "OVH_ENDPOINT" {
  description = "OVH API endpoint (e.g. ovh-eu)."
  type        = string
}

variable "OVH_APPLICATION_KEY" {
  description = "OVH API application key."
  type        = string
  sensitive   = true
}

variable "OVH_APPLICATION_SECRET" {
  description = "OVH API application secret."
  type        = string
  sensitive   = true
}

variable "OVH_CONSUMER_KEY" {
  description = "OVH API consumer key."
  type        = string
  sensitive   = true
}

variable "OVH_CLOUD_SERVICE_NAME" {
  description = "OVH Public Cloud project ID used as service_name in all resources."
  type        = string
}

variable "S3_BUCKET_NAMES" {
  description = "Comma-and-space-separated list of S3 bucket names to provision."
  type        = string
}

variable "OVH_S3_USER" {
  description = "OVH object store username (description field on the cloud project user)."
  type        = string
}
