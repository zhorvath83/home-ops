resource "ovh_cloud_project_user" "object_store_user" {
  service_name = var.OVH_CLOUD_SERVICE_NAME
  description  = var.OVH_S3_USER
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user_s3_credential" "object_store_user" {
  service_name = ovh_cloud_project_user.object_store_user.service_name
  user_id      = ovh_cloud_project_user.object_store_user.id
}

output "s3_user_id" {
  value     = ovh_cloud_project_user.object_store_user.id
  sensitive = false
}

output "s3_username" {
  value     = ovh_cloud_project_user.object_store_user.username
  sensitive = true
}

output "s3_user_description" {
  value     = ovh_cloud_project_user.object_store_user.description
  sensitive = false
}

output "s3_access_key" {
  value     = ovh_cloud_project_user_s3_credential.object_store_user.access_key_id
  sensitive = true
}

output "s3_secret_key" {
  value     = ovh_cloud_project_user_s3_credential.object_store_user.secret_access_key
  sensitive = true
}
