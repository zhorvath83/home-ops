terraform {

  required_version = "~> 1.0"

  cloud {
    organization = "zhorvath83"
    workspaces {
      name = "ovh"
    }
  }

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "2.13.1"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

provider "ovh" {
  endpoint           = var.OVH_ENDPOINT
  application_key    = var.OVH_APPLICATION_KEY
  application_secret = var.OVH_APPLICATION_SECRET
  consumer_key       = var.OVH_CONSUMER_KEY
}
