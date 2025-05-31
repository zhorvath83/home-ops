resource "cloudflare_r2_bucket" "downloads" {
  account_id = var.CF_ACCOUNT_ID
  name       = "downloads"
  location   = "EEUR"
}

# R2 Custom Domain resource
resource "cloudflare_r2_custom_domain" "r2_downloads_custom_domain" {
  account_id  = var.CF_ACCOUNT_ID
  bucket_name = cloudflare_r2_bucket.downloads.name
  domain      = "downloads.${var.CF_DOMAIN_NAME}"
  zone_id     = local.cf_zone_id
  enabled     = true
  min_tls     = "1.2"
}
