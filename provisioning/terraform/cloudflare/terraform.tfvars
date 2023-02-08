# DO NOT modify if Cloudflare mail routing is enabled!
dns_mx_records = {
    mx_record_1 = {
      host    = "in1-smtp.messagingengine.com"
      priority  = 10
    },
    mx_record_2 = {
      host    = "in2-smtp.messagingengine.com"
      priority  = 20
    }
}

# Served via Cloudflare Workers
mail_mta_sts_params = {
  mode = "testing" # Sending MTA policy application, https://tools.ietf.org/html/rfc8461#section-5
  max_age = 604800 # 1 week
  rua_mail = "35be510b@in.mailhardener.com"
}

dns_spf_record_value = "v=spf1 include:spf.messagingengine.com -all"

dns_dkim_records = {
    dkim_record_1 = {
      name          = "fm1._domainkey"
      value_prefix  = "fm1."
      value_suffix  = ".dkim.fmhosted.com"
      type          = "CNAME"
    },
    dkim_record_2 = {
      name          = "fm2._domainkey"
      value_prefix  = "fm2."
      value_suffix  = ".dkim.fmhosted.com"
      type          = "CNAME"
    },
    dkim_record_3 = {
      name          = "fm3._domainkey"
      value_prefix  = "fm3."
      value_suffix  = ".dkim.fmhosted.com"
      type          = "CNAME"
    }
}

dns_srv_records = {
    srv_record_1 = {
      service   = "_submission"
      proto     = "_tcp"
      priority  = 0
      weight    = 1
      port      = 587
      target    = "smtp.fastmail.com"
    },
    srv_record_2 = {
      service   = "_imap"
      proto     = "_tcp"
      priority  = 0
      weight    = 0
      port      = 0
      target    = "."
    },
    srv_record_3 = {
      service   = "_imaps"
      proto     = "_tcp"
      priority  = 0
      weight    = 1
      port      = 993
      target    = "imap.fastmail.com"
    },
    srv_record_4 = {
      service   = "_pop3"
      proto     = "_tcp"
      priority  = 0
      weight    = 0
      port      = 0
      target    = "."
    },
    srv_record_5 = {
      service   = "_pop3s"
      proto     = "_tcp"
      priority  = 10
      weight    = 1
      port      = 995
      target    = "pop.fastmail.com"
    },
    srv_record_6 = {
      service   = "_jmap"
      proto     = "_tcp"
      priority  = 0
      weight    = 1
      port      = 443
      target    = "api.fastmail.com"
    },
    srv_record_7 = {
      service   = "_carddav"
      proto     = "_tcp"
      priority  = 0
      weight    = 0
      port      = 0
      target    = "."
    },
    srv_record_8 = {
      service   = "_carddavs"
      proto     = "_tcp"
      priority  = 0
      weight    = 1
      port      = 443
      target    = "carddav.fastmail.com"
    },
    srv_record_9 = {
      service   = "_caldav"
      proto     = "_tcp"
      priority  = 0
      weight    = 0
      port      = 0
      target    = "."
    },
    srv_record_10 = {
      service   = "_caldavs"
      proto     = "_tcp"
      priority  = 0
      weight    = 1
      port      = 443
      target    = "caldav.fastmail.com"
    }
}

dns_dmarc_record_value = "v=DMARC1; p=reject; rua=mailto:530aa4aa3c83.a@dmarcinput.com; ruf=mailto:530aa4aa3c83.f@dmarcinput.com; sp=reject; adkim=s; aspf=s; pct=100"

private_website_target_url = "private-website-93q.pages.dev"
