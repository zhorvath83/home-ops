resource "random_id" "cf-tunnel-rnd-secret" {
  byte_length = 51
}

resource "random_id" "cf-tunnel-rnd-name" {
  byte_length = 2
}

resource "cloudflare_tunnel" "home-ops-tun" {
  name       = "home-ops-tun-${random_id.cf-tunnel-rnd-name.dec}"
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
  value   = cloudflare_tunnel.home-ops-tun.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}


