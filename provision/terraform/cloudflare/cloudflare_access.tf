# Custom user group
resource "cloudflare_access_group" "my_users" {
  account_id     = data.sops_file.cloudflare_secrets.data["cloudflare_account_id"]
  name           = "MyUsers"

  include {
    email = [
        data.sops_file.cloudflare_secrets.data["cf_access_allowed_email_1"],
        data.sops_file.cloudflare_secrets.data["cf_access_allowed_email_2"]
        ]
  }
}

# One time pin auth method
resource "cloudflare_access_identity_provider" "pin_login" {
  account_id = data.sops_file.cloudflare_secrets.data["cloudflare_account_id"]
  name       = "Mail me one time password"
  type       = "onetimepin"
}

# Oauth
resource "cloudflare_access_identity_provider" "google_oauth" {
  account_id = data.sops_file.cloudflare_secrets.data["cloudflare_account_id"]
  name       = "Sign in with Google account"
  type       = "google"

  config {
    client_id     = data.sops_file.cloudflare_secrets.data["cf_access_google_client_id"]
    client_secret = data.sops_file.cloudflare_secrets.data["cf_access_google_client_secret"]
  }
}

# Private website
resource "cloudflare_access_application" "private_website" {
  zone_id          = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name             = "Private website"
  domain           = "www.${data.sops_file.cloudflare_secrets.data["cloudflare_domain"]}"
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

# Private cloud
resource "cloudflare_access_application" "private_cloud" {
  zone_id          = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name             = "Private Cloud"
  domain           = "*.${data.sops_file.cloudflare_secrets.data["cloudflare_domain"]}"
  type             = "self_hosted"
  session_duration = "168h"
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
