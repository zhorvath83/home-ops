# Create the single tunnel we need
resource "cloudflare_zero_trust_tunnel_cloudflared" "home-ops-tunnel" {
  name       = var.CF_TUNNEL_NAME
  account_id = var.CF_ACCOUNT_ID
  tunnel_secret = var.CF_TUNNEL_SECRET
}

# Store tunnel credentials in 1Password
resource "null_resource" "store-tunnel-secret" {
  provisioner "local-exec" {
    command     = "op item edit cloudflare --vault HomeOps 'tunnel_name=${var.CF_TUNNEL_NAME}' 'tunnel_id=${cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.id}' 'tunnel_secret=${var.CF_TUNNEL_SECRET}'"
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module
    quiet       = false
  }
}

# Create CNAME record for the tunnel
resource "cloudflare_dns_record" "tunnel_cname" {
  name    = "external"
  zone_id = cloudflare_zone.domain.id
  content = "${cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# Output tunnel information
output "tunnel_info" {
  value = {
    tunnel_id    = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.id
    tunnel_name  = var.CF_TUNNEL_NAME
  }
}
