resource "cloudflare_zone_settings_override" "cloudflare_settings" {
  zone_id = cloudflare_zone.domain.id
  settings {
    # /ssl-tls
    ssl = "strict"
    # /ssl-tls/edge-certificates
    always_use_https         = "on"
    min_tls_version          = "1.2"
    opportunistic_encryption = "on"
    tls_1_3                  = "zrt"
    automatic_https_rewrites = "on"
    universal_ssl            = "on"
    # /firewall/settings
    browser_check  = "on"
    challenge_ttl  = 1800
    privacy_pass   = "on"
    security_level = "high"
    # /speed/optimization
    brotli = "on"
    polish = "off"
    minify {
      css  = "off"
      js   = "off"
      html = "off"
    }
    rocket_loader = "off"
    # /caching/configuration
    always_online    = "off"
    development_mode = "off"
    # Respect Existing Headers
    browser_cache_ttl = "0"
    # /network
    http3               = "on"
    zero_rtt            = "on"
    ipv6                = "on"
    websockets          = "on"
    opportunistic_onion = "on"
    pseudo_ipv4         = "off"
    ip_geolocation      = "on"
    max_upload          = "100"
    # /content-protection
    email_obfuscation   = "on"
    server_side_exclude = "on"
    hotlink_protection  = "off"
    # /workers
    security_header {
      enabled            = true
      preload            = true
      max_age            = 15552000 # 6 months
      include_subdomains = true
      nosniff            = true
    }
  }
}

# Enable DNSSEC
resource "cloudflare_zone_dnssec" "enable_dnssec" {
  zone_id = cloudflare_zone.domain.id
}

# Bypass the cache
resource "cloudflare_ruleset" "bypass_cache" {
  zone_id = cloudflare_zone.domain.id
  name        = "Cache bypass"
  description = "Ruleset to bypass cache"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    action = "set_cache_settings"
    action_parameters {
      cache = false
      browser_ttl {
        mode = "bypass"
      }
    }
    expression  = "(http.host eq \"*.${var.CF_DOMAIN_NAME}\")"
    description = "Bypass cache"
    enabled     = true
  }
}

# Bot management
resource "cloudflare_bot_management" "fight_bots" {
  zone_id = cloudflare_zone.domain.id
  fight_mode = true
  enable_js  = true
}
