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
      version = "6.6.0"
    }
    # renovate: datasource=terraform-provider depName=cloudflare/cloudflare versioning=semver enabled=false
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.5"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.3"
    }
  }
}

provider "cloudflare" {
  email       = var.CF_USERNAME
  api_key     = var.CF_GLOBAL_APIKEY
}

resource "cloudflare_zone" "domain" {
  account_id = var.CF_ACCOUNT_ID
  zone   = var.CF_DOMAIN_NAME
  paused = false
  plan   = "free"
  type   = "full"
}

data "http" "github_ip_ranges" {
  url = "https://api.github.com/meta"
  request_headers = {
    Accept = "application/json"
  }
}
