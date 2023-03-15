resource "cloudflare_page_rule" "subdomain_bypass_cache" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  target  = "*.${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}/*"
  status  = "active"

  actions {
    cache_level = "bypass"
  }
}
