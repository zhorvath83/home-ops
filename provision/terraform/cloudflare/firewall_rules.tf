data "http" "github_ips" {
  url = "https://api.github.com/meta"
  request_headers = {
    Accept = "application/json"
  }
}

resource "cloudflare_ip_list" "github_hooks" {
  account_id  = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ACCOUNT_ID"]
  name        = "github_hooks"
  kind        = "ip"
  description = "List of Github hooks IP Addresses"
  dynamic "item" {
    for_each = (jsondecode(data.http.github_ips.body)).hooks
    content {
      value = item.value
    }
  }
}

resource "cloudflare_filter" "github_hooks" {
  zone_id     = lookup(data.cloudflare_zones.domain.zones[0], "id")
  description = "Expression to allow Github hooks IP addresses"
  expression  = "(http.host eq \"flux-webhook.${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}\" and not ip.src in $github_hooks)"
  depends_on = [
    cloudflare_ip_list.github_hooks,
  ]
}

resource "cloudflare_firewall_rule" "github_hooks" {
  zone_id     = lookup(data.cloudflare_zones.domain.zones[0], "id")
  description = "Firewall rule to allow only Github hooks IP addresses"
  filter_id   = cloudflare_filter.github_hooks.id
  action      = "block"
}
