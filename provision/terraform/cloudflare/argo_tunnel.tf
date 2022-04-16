resource "cloudflare_argo_tunnel" "cf_argo_tunnel" {
  account_id = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ACCOUNT_ID"]
  name       = "${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}-tunnel"
  secret     = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ARGO_TUNNEL_SECRET"]
}

resource "cloudflare_record" "cf_argo_tunnel_cname" {
  name    = "cf-argo-tunnel"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "${cloudflare_argo_tunnel.cf_argo_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

output "cf_argo_tunnel_id" {
 value       = cloudflare_argo_tunnel.cf_argo_tunnel.id
 description = "Cloudflare Argo Tunnel ID.  Paste it to cluster-settings."
}
