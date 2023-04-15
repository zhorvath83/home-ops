data "github_ip_ranges" "cidrs" {}

# Access groups

## My custom user group
resource "cloudflare_access_group" "my_users" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "MyUsers"

  include {
    email = split(", ", var.CF_ACCESS_AUTHORIZED_EMAILS)
  }
}

# One time pin auth method
resource "cloudflare_access_identity_provider" "pin_login" {
  account_id = var.CF_ACCOUNT_ID
  name       = "Mail me one time password"
  type       = "onetimepin"
}

# Google Oauth
resource "cloudflare_access_identity_provider" "google_oauth" {
  account_id = var.CF_ACCOUNT_ID
  name       = "Sign in with Google account"
  type       = "google"

  config {
    client_id     = var.CF_ACCESS_GOOGLE_CL_ID
    client_secret = var.CF_ACCESS_GOOGLE_CL_SECRET
  }
}

# Applications

## Private cloud
resource "cloudflare_access_application" "private_cloud" {
  zone_id          = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name             = "Private Cloud"
  domain           = "*.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
  session_duration = "720h"
}

resource "cloudflare_access_policy" "private_cloud_user_auth_policy" {
  application_id = cloudflare_access_application.private_cloud.id
  zone_id        = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name           = "UserAuth"
  precedence     = "1"
  decision       = "allow"

  include {
    group = [cloudflare_access_group.my_users.id]
  }
}

## Private website www exclude from UserAuth
resource "cloudflare_access_application" "private_website" {
  zone_id          = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name             = "Private website"
  domain           = "www.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
}

resource "cloudflare_access_policy" "private_website_bypass_policy" {
  application_id = cloudflare_access_application.private_website.id
  zone_id        = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name           = "Bypass"
  precedence     = "1"
  decision       = "bypass"

  include {
    everyone = true
  }
}

## Private R2 downloads exclude from UserAuth
resource "cloudflare_access_application" "private_r2_downloads" {
  zone_id          = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name             = "Private R2 downloads"
  domain           = "downloads.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
}

resource "cloudflare_access_policy" "private_r2_downloads_bypass_policy" {
  application_id = cloudflare_access_application.private_r2_downloads.id
  zone_id        = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name           = "Bypass"
  precedence     = "1"
  decision       = "bypass"

  include {
    everyone = true
  }
}

## Flux webhook
## Protected by WAF and ZeroTrust too
resource "cloudflare_access_application" "flux_webhook" {
  zone_id          = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name             = "Flux webhook"
  domain           = "flux-webhook.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
}

resource "cloudflare_access_policy" "flux_webhook_bypass_policy" {
  application_id = cloudflare_access_application.flux_webhook.id
  zone_id        = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name           = "CIDRbasedBypass"
  precedence     = "1"
  decision       = "bypass"

  include {
    ip = data.github_ip_ranges.cidrs.hooks
  }
}

## MTA-STS policy file exclude from UserAuth
resource "cloudflare_access_application" "mta_sts_policy" {
  zone_id          = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name             = "MTA-STS policy"
  domain           = "mta-sts.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
}

resource "cloudflare_access_policy" "mta_sts_policy_bypass_policy" {
  application_id = cloudflare_access_application.mta_sts_policy.id
  zone_id        = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name           = "Bypass"
  precedence     = "1"
  decision       = "bypass"

  include {
    everyone = true
  }
}

## Webmail exclude from UserAuth
resource "cloudflare_access_application" "webmail" {
  zone_id          = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name             = "Webmail"
  domain           = "mail.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
}

resource "cloudflare_access_policy" "webmail_bypass_policy" {
  application_id = cloudflare_access_application.webmail.id
  zone_id        = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name           = "Bypass"
  precedence     = "1"
  decision       = "bypass"

  include {
    everyone = true
  }
}
