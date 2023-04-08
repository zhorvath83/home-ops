resource "cloudflare_page_rule" "subdomain_bypass_cache" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  target  = "*.${var.CF_DOMAIN_NAME}/*"
  status  = "active"

  actions {
    cache_level = "bypass"
  }
}
