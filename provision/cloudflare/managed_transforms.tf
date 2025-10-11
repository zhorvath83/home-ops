# Managed Transforms
# https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/managed_transforms

resource "cloudflare_managed_transforms" "visitor_headers" {
  zone_id = cloudflare_zone.domain.id
  
  managed_request_headers = [
    {
      id      = "add_visitor_location_headers"
      enabled = true
    }
  ]
  
  managed_response_headers = []
}
