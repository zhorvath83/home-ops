# SSL/TLS Settings
resource "cloudflare_zone_setting" "ssl" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "ssl"
  value = "strict"
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "always_use_https"
  value = "on"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "min_tls_version"
  value = "1.2"
}

resource "cloudflare_zone_setting" "opportunistic_encryption" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "opportunistic_encryption"
  value = "on"
}

resource "cloudflare_zone_setting" "tls_1_3" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "tls_1_3"
  value = "zrt"
}

resource "cloudflare_zone_setting" "automatic_https_rewrites" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "automatic_https_rewrites"
  value = "on"
}


# Firewall Settings
resource "cloudflare_zone_setting" "browser_check" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "browser_check"
  value = "on"
}

resource "cloudflare_zone_setting" "challenge_ttl" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "challenge_ttl"
  value = 1800
}

resource "cloudflare_zone_setting" "privacy_pass" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "privacy_pass"
  value = "on"
}

resource "cloudflare_zone_setting" "security_level" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "security_level"
  value = "high"
}

# Speed/Optimization Settings
resource "cloudflare_zone_setting" "brotli" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "brotli"
  value = "on"
}

resource "cloudflare_zone_setting" "polish" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "polish"
  value = "off"
}

resource "cloudflare_zone_setting" "rocket_loader" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "rocket_loader"
  value = "off"
}

# Caching Settings
resource "cloudflare_zone_setting" "always_online" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "always_online"
  value = "off"
}

resource "cloudflare_zone_setting" "development_mode" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "development_mode"
  value = "off"
}

resource "cloudflare_zone_setting" "browser_cache_ttl" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "browser_cache_ttl"
  value = 0
}

# Network Settings
resource "cloudflare_zone_setting" "http3" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "http3"
  value = "on"
}

resource "cloudflare_zone_setting" "zero_rtt" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "0rtt"  # Fixed: "0rtt" not "zero_rtt"
  value = "on"
}

resource "cloudflare_zone_setting" "ipv6" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "ipv6"
  value = "on"
}

resource "cloudflare_zone_setting" "websockets" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "websockets"
  value = "on"
}

resource "cloudflare_zone_setting" "opportunistic_onion" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "opportunistic_onion"
  value = "on"
}

resource "cloudflare_zone_setting" "pseudo_ipv4" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "pseudo_ipv4"
  value = "off"
}

resource "cloudflare_zone_setting" "ip_geolocation" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "ip_geolocation"
  value = "on"
}

resource "cloudflare_zone_setting" "max_upload" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "max_upload"
  value = 100
}

# Content Protection Settings
resource "cloudflare_zone_setting" "email_obfuscation" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "email_obfuscation"
  value = "on"
}

resource "cloudflare_zone_setting" "server_side_exclude" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "server_side_exclude"
  value = "on"
}

resource "cloudflare_zone_setting" "hotlink_protection" {
  zone_id = cloudflare_zone.domain.id
  setting_id = "hotlink_protection"
  value = "off"
}

# DNSSEC 
resource "cloudflare_zone_dnssec" "enable_dnssec" {
  zone_id = cloudflare_zone.domain.id
}

# Cache bypass ruleset
resource "cloudflare_ruleset" "bypass_cache" {
  zone_id     = cloudflare_zone.domain.id
  name        = "Cache bypass"
  description = "Ruleset to bypass cache"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [{
    action = "set_cache_settings"
    action_parameters = {
      cache = false
      browser_ttl = {
        mode = "bypass_by_default"
      }
    }
    expression  = "(http.host contains \".${var.CF_DOMAIN_NAME}\")"
    description = "Bypass cache globally"
    enabled     = true
  }]
}

# Bot management
resource "cloudflare_bot_management" "fight_bots" {
  zone_id    = cloudflare_zone.domain.id
  fight_mode = true
  enable_js  = true
}

# Security Headers
resource "cloudflare_ruleset" "security_headers" {
  zone_id     = cloudflare_zone.domain.id
  name        = "Security Headers"
  description = "Add comprehensive security headers"
  kind        = "zone"
  phase       = "http_response_headers_transform"

  # Strict CSP to the root domain
  rules = [{
    action = "rewrite"
    action_parameters = {
      headers = {
        "Strict-Transport-Security" = {
          operation = "set"
          value     = "max-age=31536000; includeSubDomains; preload"
        }
        "X-Content-Type-Options" = {
          operation = "set"
          value     = "nosniff"
        }
        "X-Frame-Options" = {
          operation = "set"
          value     = "DENY"
        }
        "X-XSS-Protection" = {
          operation = "set"
          value     = "1; mode=block"
        }
        "Referrer-Policy" = {
          operation = "set"
          value     = "strict-origin-when-cross-origin"
        }
        "Content-Security-Policy" = {
          operation = "set"
          value = "default-src 'self'; script-src 'self' 'unsafe-inline' *.cloudflare.com cdnjs.cloudflare.com static.cloudflareinsights.com; style-src 'self' 'unsafe-inline' fonts.googleapis.com fonts.bunny.net *.cloudflare.com; font-src 'self' fonts.gstatic.com fonts.bunny.net data:; img-src 'self' data: https:; connect-src 'self' *.cloudflare.com static.cloudflareinsights.com; upgrade-insecure-requests"
        }
        "Permissions-Policy" = {
          operation = "set"
          value     = "geolocation=(), microphone=(), camera=(), payment=(), usb=(), bluetooth=()"
        }
      }
    }
    expression  = "(http.host eq \"${var.CF_DOMAIN_NAME}\")"
    description = "Add strict security headers to root domain"
    enabled     = true
  },
  # Loose CSP to subdomains
  {
    action = "rewrite"
    action_parameters = {
      headers = {
        "Strict-Transport-Security" = {
          operation = "set"
          value     = "max-age=31536000; includeSubDomains; preload"
        }
        "X-Content-Type-Options" = {
          operation = "set"
          value     = "nosniff"
        }
        "X-Frame-Options" = {
          operation = "set"
          value     = "SAMEORIGIN"
        }
        "X-XSS-Protection" = {
          operation = "set"
          value     = "1; mode=block"
        }
        "Referrer-Policy" = {
          operation = "set"
          value     = "strict-origin-when-cross-origin"
        }
        "Content-Security-Policy" = {
          operation = "set"
          value = "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'self' *.${var.CF_DOMAIN_NAME}"
        }
        "Permissions-Policy" = {
          operation = "set"
          value     = "geolocation=(), microphone=(), camera=(), payment=(), usb=(), bluetooth=()"
        }
      }
    }
    expression  = "(http.host contains \".${var.CF_DOMAIN_NAME}\" and http.host ne \"${var.CF_DOMAIN_NAME}\")"
    description = "Add relaxed security headers to subdomains"
    enabled     = true
  }]
}
