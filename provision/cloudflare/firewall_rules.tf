resource "cloudflare_list" "github_hooks_cidr_list" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "github_hooks_cidr_list"
  kind        = "ip"
  description = "List of Github hooks IP Addresses"
}

resource "cloudflare_list_item" "github_hooks_items" {
  for_each = toset((jsondecode(data.http.github_ip_ranges.response_body)).hooks)

  account_id = var.CF_ACCOUNT_ID
  list_id    = cloudflare_list.github_hooks_cidr_list.id
  ip         = each.value
  comment    = "GitHub webhook IP"
}

locals {
  # Proxied subdomains exempt from the country block below.
  # Add a host here when a new service must accept non-HU traffic
  # (e.g. a new webhook receiver, or an endpoint fetched by foreign peers).
  country_block_exceptions = toset([
    "flux-webhook.${var.CF_DOMAIN_NAME}", # GitHub webhook sender is non-HU
    "mta-sts.${var.CF_DOMAIN_NAME}",      # foreign MX validators fetch the MTA-STS policy
  ])
  country_block_expression = join(" and ", concat(
    [for host in local.country_block_exceptions : "not http.host eq \"${host}\""],
    ["not ip.geoip.country eq \"HU\""],
  ))
}

resource "cloudflare_ruleset" "zone_waf_rules" {
  zone_id     = cloudflare_zone.domain.id
  name        = "Zone custom WAF rules"
  description = "Custom firewall rules for zone-level request filtering"
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  depends_on = [
    cloudflare_list.github_hooks_cidr_list
  ]

  rules = [
    {
      action      = "block"
      enabled     = true
      description = "Allow only Github CIDR's at Flux webhook"
      expression  = "(http.host eq \"flux-webhook.${var.CF_DOMAIN_NAME}\" and not ip.src in $github_hooks_cidr_list)"
    },
    {
      action      = "block"
      enabled     = true
      description = "Block non-Hungary requests to all subdomains except exempt hosts"
      expression  = "(${local.country_block_expression})"
    }
  ]
}
