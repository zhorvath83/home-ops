terraform {

  required_version = "~> 1.0"

  cloud {
    organization = "zhorvath83"
    workspaces {
      name = "pocket-id"
    }
  }

  required_providers {
    pocketid = {
      source  = "trozz/pocketid"
      version = "2.3.0"
    }
  }
}

# LAN-only on purpose: the public route 403s any request carrying X-API-KEY, so the
# admin API is reachable through envoy-internal (split DNS) alone.
provider "pocketid" {
  base_url  = "https://idm.${local.public_domain}"
  api_token = var.POCKETID_API_TOKEN
}
