resource "cloudflare_email_routing_settings" "mail_routing" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  enabled = false
}

resource "cloudflare_email_routing_address" "mail_rtng_cntct_addr" {
  account_id = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ACCOUNT_ID"]
  email      = data.sops_file.cluster_secrets.data["stringData.SECRET_EMAIL_1"]
}

resource "cloudflare_email_routing_rule" "mail_rtng_rule" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name    = "${data.sops_file.cluster_secrets.data["stringData.SECRET_EMAIL_2"]} rule"
  enabled = false

  matcher {
    type  = "literal"
    field = "to"
    value = data.sops_file.cluster_secrets.data["stringData.SECRET_EMAIL_2"]
  }

  action {
    type  = "forward"
    value = [data.sops_file.cluster_secrets.data["stringData.SECRET_EMAIL_1"]]
  }
}

resource "cloudflare_email_routing_catch_all" "mail_rtng_rule_ctch_all" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name    = "${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]} catch all"
  enabled = false

  matcher {
    type = "all"
  }

  action {
    type  = "forward"
    value = [data.sops_file.cluster_secrets.data["stringData.SECRET_EMAIL_1"]]
  }
}
