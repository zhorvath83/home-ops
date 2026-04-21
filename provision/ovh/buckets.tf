locals {
  region       = "DE"
  bucket_names = toset([for b in split(", ", var.S3_BUCKET_NAMES) : trimspace(b)])
}

resource "ovh_cloud_project_storage" "backup" {
  for_each     = local.bucket_names
  service_name = var.OVH_CLOUD_SERVICE_NAME
  region_name  = local.region
  name         = each.key
}

output "s3_endpoint" {
  value = "s3.${lower(local.region)}.io.cloud.ovh.net"
}
