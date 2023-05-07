resource "random_id" "cf-tunnel-rnd-secret" {
  byte_length = 50
}

resource "random_id" "cf-tunnel-rnd-name" {
  byte_length = 2
}

resource "cloudflare_tunnel" "home-ops-tunnel" {
  name       = "home-ops-tunnel-${random_id.cf-tunnel-rnd-name.dec}"
  account_id = var.CF_ACCOUNT_ID
  secret     = random_id.cf-tunnel-rnd-secret.b64_std
}

locals {
  tunnel_credentials_json = jsonencode({
      "AccountTag"   = var.CF_ACCOUNT_ID,
      "TunnelID"     = cloudflare_tunnel.home-ops-tunnel.id
      "TunnelName"   = cloudflare_tunnel.home-ops-tunnel.name,
      "TunnelSecret" = cloudflare_tunnel.home-ops-tunnel.secret
  })
}

resource "null_resource" "store-tunnel-secret" {
  triggers = {
    tunnel_credentials_file = local.tunnel_credentials_json
  }

  provisioner "local-exec" {
    command     = "op item edit cloudflare --vault HomeOps 'tunnel_name=${cloudflare_tunnel.home-ops-tunnel.name}' 'tunnel_id=${cloudflare_tunnel.home-ops-tunnel.id}' 'tunnel_secret=${cloudflare_tunnel.home-ops-tunnel.secret}' 'tunnel_token=${cloudflare_tunnel.home-ops-tunnel.tunnel_token}' 'tunnel_credentials=${self.triggers.tunnel_credentials_file}'"
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module
    quiet       = true
  }
}

resource "cloudflare_record" "tunnel_cname" {
  name    = "tunnel"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = cloudflare_tunnel.home-ops-tunnel.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# resource "cloudflare_tunnel_config" "home-ops-tun-conf" {
#   account_id = var.CF_ACCOUNT_ID
#   tunnel_id  = cloudflare_tunnel.home-ops-tunnel.id
# 
#   config {
#     warp_routing {
#       enabled = false
#     }
#     origin_request {
#       connect_timeout     = "30s"
#       no_tls_verify       = false
#       origin_server_name  = var.CF_DOMAIN_NAME
#     }
#     ingress_rule {
#       hostname  = "*.${var.CF_DOMAIN_NAME}"
#       service   = "https://ingress-nginx-controller.networking.svc.cluster.local"
#     }
#     ingress_rule {
#       service   = "http_status:404"
#     }
#   }
# }

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
