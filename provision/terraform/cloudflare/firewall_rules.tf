resource "cloudflare_list" "github_hooks_cidr_list" {
  account_id  = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ACCOUNT_ID"]
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

resource "cloudflare_filter" "github_hooks_cidr_list" {
  zone_id     = lookup(data.cloudflare_zones.domain.zones[0], "id")
  description = "Expression to allow Github hooks IP addresses"
  expression  = "(http.host eq \"flux-webhook.${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}\" and not ip.src in $github_hooks_cidr_list)"
  depends_on = [
    cloudflare_list.github_hooks_cidr_list,
  ]
}

resource "cloudflare_firewall_rule" "github_hooks_cidr_list" {
  zone_id     = lookup(data.cloudflare_zones.domain.zones[0], "id")
  description = "Firewall rule to allow only Github hooks IP addresses"
  filter_id   = cloudflare_filter.github_hooks_cidr_list.id
  action      = "block"
}
