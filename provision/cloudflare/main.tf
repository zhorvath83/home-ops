terraform {

  cloud {
    organization = "zhorvath83"
    workspaces {
      name = "cloudflare"
    }
  }

  required_providers {
    github = {
      source  = "integrations/github"
      version = "5.27.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.8.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
    }
  }
}

provider "cloudflare" {
  email       = var.CF_USERNAME
  api_key     = var.CF_GLOBAL_APIKEY
}

data "cloudflare_zones" "domain" {
  filter {
    name = var.CF_DOMAIN_NAME
  }
}

data "http" "github_ip_ranges" {
  url = "https://api.github.com/meta"
  request_headers = {
    Accept = "application/json"
  }
}
