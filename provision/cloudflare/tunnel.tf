# Generate secret for the tunnel
resource "random_id" "cf-tunnel-secret" {
  byte_length = 60
}

# Create the single tunnel we need
resource "cloudflare_zero_trust_tunnel_cloudflared" "home-ops-tunnel" {
  name       = "home-ops-tunnel"
  account_id = var.CF_ACCOUNT_ID
  secret     = random_id.cf-tunnel-secret.b64_std
}

# Generate tunnel credentials JSON
locals {
  tunnel_credentials_json = jsonencode({
    "AccountTag"   = var.CF_ACCOUNT_ID,
    "TunnelID"     = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.id
    "TunnelName"   = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.name,
    "TunnelSecret" = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.secret
  })
}

# Store tunnel credentials in 1Password
resource "null_resource" "store-tunnel-secret" {
  triggers = {
    tunnel_credentials_file = local.tunnel_credentials_json
  }

  provisioner "local-exec" {
    command     = "op item edit cloudflare --vault HomeOps 'tunnel_name=${cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.name}' 'tunnel_id=${cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.id}' 'tunnel_secret=${cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.secret}' 'tunnel_token=${cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.tunnel_token}' 'tunnel_credentials=${self.triggers.tunnel_credentials_file}'"
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module
    quiet       = false
  }
}

# Create CNAME record for the tunnel
resource "cloudflare_record" "tunnel_cname" {
  name    = "tunnel"
  zone_id = cloudflare_zone.domain.id
  content = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# Tunnel health notification policy
resource "cloudflare_notification_policy" "home-ops-tun-health" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "CF tunnel health notification events"
  description = "Notification policy related to CF tunnel health events."
  enabled     = true
  alert_type  = "tunnel_health_event"

  email_integration {
    id = var.CUSTOM_DOMAIN_EMAIL
  }
}

# Output tunnel information
output "tunnel_info" {
  value = {
    tunnel_id    = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.id
    tunnel_name  = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.name
    tunnel_token = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.tunnel_token
  }
  sensitive = true
}

# Separate non-sensitive outputs
output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.id
  description = "Cloudflare Tunnel ID"
}

output "tunnel_name" {
  value = cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel.name
  description = "Cloudflare Tunnel Name"
}
