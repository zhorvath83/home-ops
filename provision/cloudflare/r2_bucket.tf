resource "cloudflare_r2_bucket" "downloads" {
  account_id = var.CF_ACCOUNT_ID
  name       = "downloads"
  location   = "EEUR"
}
