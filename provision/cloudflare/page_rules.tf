# resource "cloudflare_page_rule" "subdomain_bypass_cache" {
#   zone_id = cloudflare_zone.domain.id
#   target  = "*.${var.CF_DOMAIN_NAME}/*"
#   status  = "active"
# 
#   actions {
#     cache_level = "bypass"
#     disable_performance = true
#   }
# }
