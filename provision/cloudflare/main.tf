terraform {

  required_version = "~> 1.0"

  cloud {
    organization = "zhorvath83"
    workspaces {
      name = "cloudflare"
    }
  }

  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.10.2"
    }

    # renovate:disablePlugin terraform cloudflare/cloudflare
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.16.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }

    external = {
      source  = "hashicorp/external"
      version = "2.3.5"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

provider "cloudflare" {
  email       = var.CF_USERNAME
  api_key     = var.CF_GLOBAL_APIKEY
}

resource "cloudflare_zone" "domain" {
  account = {
      id = var.CF_ACCOUNT_ID
    }
  name = var.CF_DOMAIN_NAME
  type   = "full"
}

data "http" "github_ip_ranges" {
  url = "https://api.github.com/meta"
  request_headers = {
    Accept = "application/json"
  }
}
