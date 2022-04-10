resource "random_id" "argo_tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_argo_tunnel" "cf_argo_tunnel" {
  account_id = data.sops_file.cloudflare_secrets.data["cloudflare_account_id"]
  name       = "${data.sops_file.cloudflare_secrets.data["cloudflare_domain"]}-tunnel"
  secret     = random_id.argo_tunnel_secret.b64_std
}

resource "cloudflare_record" "cf_argo_tunnel_cname" {
  name    = "cf-argo-tunnel"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "${cloudflare_argo_tunnel.cf_argo_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}
