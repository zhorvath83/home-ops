terraform {

  cloud {
    organization = "zhorvath83"
    workspaces {
      name = "cloudflare"
    }
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "3.16.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "2.2.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "0.7.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.2.2"
    }
  }
}

data "external" "git_root_path" {
  program = ["bash", "-c", "echo {\\\"result\\\":\\\"$(git rev-parse --show-toplevel)\\\"}"]
}

data "sops_file" "cluster_secrets" {
  source_file = "${data.external.git_root_path.result.result}/cluster/base/cluster-secrets.sops.yaml"
}

provider "cloudflare" {
  email   = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_EMAIL"]
  api_key = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_APIKEY"]
}

data "cloudflare_zones" "domain" {
  filter {
    name = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  }
}
