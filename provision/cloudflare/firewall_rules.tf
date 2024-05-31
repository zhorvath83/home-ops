resource "cloudflare_list" "github_hooks_cidr_list" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "github_hooks_cidr_list"
  kind        = "ip"
  description = "List of Github hooks IP Addresses"
  dynamic "item" {
    for_each = (jsondecode(data.http.github_ip_ranges.response_body)).hooks
    content {
      value {
        ip = item.value
      }
    }
  }
}

resource "cloudflare_ruleset" "flux_webhook_waf" {
  zone_id     = cloudflare_zone.domain.id
  name        = "WAF for Flux webhook"
  description = "Rules for access Flux webhook"
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  depends_on  = [
    cloudflare_list.github_hooks_cidr_list
  ]

  rules {
    action = "block"
    enabled     = true
    description = "Allow only Github CIDR's at Flux webhook"
    expression  = "(http.host eq \"flux-webhook.${var.CF_DOMAIN_NAME}\" and not ip.src in $github_hooks_cidr_list)"
  }
}
