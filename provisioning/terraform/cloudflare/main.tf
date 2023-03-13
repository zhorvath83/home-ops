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
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.1.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.2.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "0.7.2"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.2.3"
    }
  }
}

data "external" "git_root_path" {
  program = ["bash", "-c", "echo {\\\"result\\\":\\\"$(git rev-parse --show-toplevel)\\\"}"]
}

data "sops_file" "cluster_secrets" {
  source_file = "${data.external.git_root_path.result.result}/cluster/config/cluster-secrets.sops.yaml"
}

provider "cloudflare" {
  email       = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_EMAIL"]
  api_key     = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_APIKEY"]
}

data "cloudflare_zones" "domain" {
  filter {
    name = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  }
}

data "http" "github_ip_ranges" {
  url = "https://api.github.com/meta"
  request_headers = {
    Accept = "application/json"
  }
}
