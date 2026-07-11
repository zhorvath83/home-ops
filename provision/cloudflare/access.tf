locals {
  github_meta = jsondecode(data.http.github_ip_ranges.response_body)
}

# Service token for mobile apps (bypasses browser-based auth)
resource "cloudflare_zero_trust_access_service_token" "mobile_apps" {
  account_id = var.CF_ACCOUNT_ID
  name       = "MobileAppsServiceToken"
}

# Store service token credentials in 1Password
resource "null_resource" "store-service-token-secret" {
  provisioner "local-exec" {
    command     = "op item edit cloudflare --vault HomeOps 'CF-Access-Client-Id=${cloudflare_zero_trust_access_service_token.mobile_apps.client_id}' 'CF-Access-Client-Secret=${cloudflare_zero_trust_access_service_token.mobile_apps.client_secret}'"
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module
    quiet       = false
  }
}

# Access groups

## My unrestricted user group - unlimited access for all Apps
resource "cloudflare_zero_trust_access_group" "unrestricted_users" {
  account_id = var.CF_ACCOUNT_ID
  name       = "UnrestrictedUsers"

  include = [
    for email_addr in split(", ", var.CF_ACCESS_UNRESTRICTED_USERS) : {
      email = {
        email = email_addr
      }
    }
  ]
}

## My restricted user group
resource "cloudflare_zero_trust_access_group" "restricted_users" {
  account_id = var.CF_ACCOUNT_ID
  name       = "RestrictedUsers"

  include = [
    for email_addr in split(", ", var.CF_ACCESS_RESTRICTED_USERS) : {
      email = {
        email = email_addr
      }
    }
  ]
}

resource "cloudflare_zero_trust_access_policy" "unrestricted_users_policy" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "UnrestrictedUsersAuth"
  decision       = "allow"

  include =[ {
    group = {
      id = cloudflare_zero_trust_access_group.unrestricted_users.id
    }
  }]
}

resource "cloudflare_zero_trust_access_policy" "restricted_user_policy" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "RestrictedUsersAuth"
  decision       = "allow"

  include =[ {
    group = {
      id = cloudflare_zero_trust_access_group.restricted_users.id
    }
  }]
}

resource "cloudflare_zero_trust_access_policy" "bypass_everyone_policy" {
  account_id     = var.CF_ACCOUNT_ID
  name           = "Bypass"
  decision       = "bypass"

  include =[ {
    everyone = {}
  }]
}

resource "cloudflare_zero_trust_access_policy" "bypass_github_cidr_policy" {
  account_id = var.CF_ACCOUNT_ID
  name       = "CIDRbasedBypass"
  decision   = "bypass"

  include = [
    for ip_range in local.github_meta.hooks : {
      ip = {
        ip = ip_range
      }
    }
  ]
}

resource "cloudflare_zero_trust_access_policy" "service_token_auth" {
  account_id = var.CF_ACCOUNT_ID
  name       = "ServiceTokenAuth"
  decision   = "non_identity"

  include = [{
    service_token = {
      token_id = cloudflare_zero_trust_access_service_token.mobile_apps.id
    }
  }]
}

# # One time pin auth method
# resource "cloudflare_zero_trust_access_identity_provider" "pin_login" {
#   account_id = var.CF_ACCOUNT_ID
#   name       = "Mail me one time password"
#   type       = "onetimepin"
# }

# Google Oauth
resource "cloudflare_zero_trust_access_identity_provider" "google_oauth" {
  account_id = var.CF_ACCOUNT_ID
  name       = "Sign in with Google"
  type       = "google"

  config = {
    client_id     = var.CF_ACCESS_GOOGLE_CL_ID
    client_secret = var.CF_ACCESS_GOOGLE_CL_SECRET
    pkce_enabled  = true
  }
}

# Applications

## Private cloud
## Wildcard fallback for every subdomain without its own Access app.
## The service-token (non_identity) policy is intentionally NOT here: it is
## scoped to the specific apps that need header-based access (docs, recipes),
## so the mobile token can no longer bypass identity on every host.
resource "cloudflare_zero_trust_access_application" "private_cloud" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Private Cloud"
  domain           = "*.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.unrestricted_users_policy.id
      precedence = 1
    }
  ]
}

## Paperless (docs) — Paperless mobile client authenticates via CF Access
## service-token headers, so this host keeps the non_identity policy.
resource "cloudflare_zero_trust_access_application" "paperless" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Paperless"
  domain           = "docs.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.service_token_auth.id
      precedence = 1
    },
    {
      id         = cloudflare_zero_trust_access_policy.unrestricted_users_policy.id
      precedence = 2
    }
  ]
}

## Mealie (recipes) — mobile client authenticates via CF Access service-token
## headers, so this host keeps the non_identity policy.
resource "cloudflare_zero_trust_access_application" "mealie" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Mealie"
  domain           = "recipes.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.service_token_auth.id
      precedence = 1
    },
    {
      id         = cloudflare_zero_trust_access_policy.unrestricted_users_policy.id
      precedence = 2
    }
  ]
}

## Photos
resource "cloudflare_zero_trust_access_application" "private_cloud_photos" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Private Cloud Photos"
  domain           = "fenykepek.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{
    id = cloudflare_zero_trust_access_policy.restricted_user_policy.id
  }]
}

## Private website www exclude from UserAuth
resource "cloudflare_zero_trust_access_application" "private_website" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Private website"
  domain           = "www.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [{
    id = cloudflare_zero_trust_access_policy.bypass_everyone_policy.id
  }]
}

## Flux webhook
## Protected by WAF and ZeroTrust too
resource "cloudflare_zero_trust_access_application" "flux_webhook" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Flux webhook"
  domain           = "flux-webhook.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [{
    id = cloudflare_zero_trust_access_policy.bypass_github_cidr_policy.id
  }]
}

## MTA-STS policy file exclude from UserAuth
resource "cloudflare_zero_trust_access_application" "mta_sts_policy" {
  zone_id          = cloudflare_zone.domain.id
  name             = "MTA-STS policy"
  domain           = "mta-sts.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [{
    id = cloudflare_zero_trust_access_policy.bypass_everyone_policy.id
  }]
}

## Share subdomain - no authentication required
resource "cloudflare_zero_trust_access_application" "share" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Share"
  domain           = "share.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [{
    id = cloudflare_zero_trust_access_policy.bypass_everyone_policy.id
  }]
}

## Exchange rates exclude from UserAuth
resource "cloudflare_zero_trust_access_application" "exchange-rates" {
  zone_id          = cloudflare_zone.domain.id
  name             = "Exchange rates"
  domain           = "arfolyam.${var.CF_DOMAIN_NAME}"
  type             = "self_hosted"

  policies = [{
    id = cloudflare_zero_trust_access_policy.bypass_everyone_policy.id
  }]
}
