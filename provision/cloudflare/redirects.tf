resource "cloudflare_ruleset" "redirect-www-to-non-www" {
  zone_id     = cloudflare_zone.domain.id
  name        = "redirects"
  description = "Redirects ruleset"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules {
    action = "redirect"
    action_parameters {
      from_value {
        status_code = 301
        target_url {
          expression = "concat(\"https://\", \"${var.CF_DOMAIN_NAME}\", http.request.uri.path)"
        }
        preserve_query_string = true
      }
    }
    expression  = "(starts_with(http.host, \"www.\"))"
    description = "Redirect www to non-www"
    enabled     = true
  }
}
