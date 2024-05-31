data "github_ip_ranges" "cidrs" {}

# Access groups

## My unrestricted user group - unlimited access for all Apps
resource "cloudflare_access_group" "unrestricted_users" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "UnrestrictedUsers"

  include {
    email = split(", ", var.CF_ACCESS_UNRESTRICTED_USERS)
  }
}

## My restricted user group
resource "cloudflare_access_group" "restricted_users" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "RestrictedUsers"

  include {
    email = split(", ", var.CF_ACCESS_RESTRICTED_USERS)
  }
}

resource "cloudflare_access_policy" "unrestricted_users_policy" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "UnrestrictedUsersAuth"
  decision       = "allow"

  include {
    group = [cloudflare_access_group.unrestricted_users.id]
  }
}

resource "cloudflare_access_policy" "restricted_user_policy" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "RestrictedUsersAuth"
  decision       = "allow"

  include {
    group = [cloudflare_access_group.restricted_users.id]
  }
}

resource "cloudflare_access_policy" "bypass_everyone_policy" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "Bypass"
  decision       = "bypass"

  include {
    everyone = true
  }
}

resource "cloudflare_access_policy" "bypass_github_cidr_policy" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "CIDRbasedBypass"

  decision       = "bypass"

  include {
    ip = data.github_ip_ranges.cidrs.hooks
  }
}

# # One time pin auth method
# resource "cloudflare_access_identity_provider" "pin_login" {
#   account_id = var.CF_ACCOUNT_ID
#   name       = "Mail me one time password"
#   type       = "onetimepin"
# }

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
  zone_id          = cloudflare_zone.domain.id
  name             = "Private Cloud"
  domain           = "*.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
  session_duration = "720h"

  policies = [
    cloudflare_access_policy.unrestricted_users_policy.id
  ]
}

## Photos
resource "cloudflare_access_application" "private_cloud_photos" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Private Cloud Photos"
  domain           = "fenykepek.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
  session_duration = "720h"

  policies = [
    cloudflare_access_policy.restricted_user_policy.id
  ]
}

## Private website www exclude from UserAuth
resource "cloudflare_access_application" "private_website" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Private website"
  domain           = "www.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [
    cloudflare_access_policy.bypass_everyone_policy.id
  ]
}

## Private R2 downloads exclude from UserAuth
resource "cloudflare_access_application" "private_r2_downloads" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Private R2 downloads"
  domain           = "downloads.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [
    cloudflare_access_policy.bypass_everyone_policy.id
  ]
}

## Flux webhook
## Protected by WAF and ZeroTrust too
resource "cloudflare_access_application" "flux_webhook" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Flux webhook"
  domain           = "flux-webhook.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [
    cloudflare_access_policy.bypass_github_cidr_policy.id
  ]
}

## MTA-STS policy file exclude from UserAuth
resource "cloudflare_access_application" "mta_sts_policy" {
  zone_id          = cloudflare_zone.domain.id
  name             = "MTA-STS policy"
  domain           = "mta-sts.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [
    cloudflare_access_policy.bypass_everyone_policy.id
  ]
}

## Webmail exclude from UserAuth
resource "cloudflare_access_application" "webmail" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Webmail"
  domain           = "mail.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [
    cloudflare_access_policy.bypass_everyone_policy.id
  ]
}
