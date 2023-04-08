resource "random_id" "cf-tunnel-rnd-secret" {
  byte_length = 50
}

resource "random_id" "cf-tunnel-rnd-name" {
  byte_length = 2
}

resource "cloudflare_tunnel" "home-ops-tunnel" {
  name       = "home-ops-tunnel"
  account_id = var.CF_ACCOUNT_ID
  secret     = random_id.cf-tunnel-rnd-secret.b64_std

  provisioner "local-exec" {
    command     = "op item edit cloudflare --vault HomeOps 'tunnel_id=${self.id}' 'tunnel_secret=${self.secret}' 'tunnel_token=${self.tunnel_token}'"
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module
    quiet       = true
  }
}

resource "cloudflare_record" "cf_tunnel_cname" {
  name    = "cf-tunnel"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = cloudflare_tunnel.home-ops-tunnel.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_tunnel_config" "home-ops-tun-conf" {
  account_id = var.CF_ACCOUNT_ID
  tunnel_id  = cloudflare_tunnel.home-ops-tunnel.id

  config {
    warp_routing {
      enabled = false
    }
    origin_request {
      connect_timeout     = "30s"
      no_tls_verify       = false
      origin_server_name  = var.CF_DOMAIN_NAME
    }
    ingress_rule {
      hostname  = "*.${var.CF_DOMAIN_NAME}"
      service   = "https://ingress-nginx-controller.networking.svc.cluster.local"
    }
    ingress_rule {
      service   = "http_status:404"
    }
  }
}
