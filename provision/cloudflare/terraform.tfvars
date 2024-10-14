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
  mode = "enforce" # Sending MTA policy application, https://tools.ietf.org/html/rfc8461#section-5
  max_age = 604800 # 1 week
}

mail_dmarc_rua_dest = ["mailto:80dfc704fb@rua.easydmarc.eu", "mailto:35be510b@in.mailhardener.com"]

mail_dmarc_ruf_dest = ["mailto:80dfc704fb@ruf.easydmarc.eu", "mailto:35be510b@in.mailhardener.com"]

mail_tls_rua_dest = ["mailto:35be510b@in.mailhardener.com"]

dns_spf_record_value = "v=spf1 include:spf.messagingengine.com ~all"

dns_dkim_records = {
    dkim_record_1 = {
      name          = "fm1._domainkey"
      value         = "fm1.domain_name_to_replace.dkim.fmhosted.com"
      type          = "CNAME"
    },
    dkim_record_2 = {
      name          = "fm2._domainkey"
      value         = "fm2.domain_name_to_replace.dkim.fmhosted.com"
      type          = "CNAME"
    },
    dkim_record_3 = {
      name          = "fm3._domainkey"
      value         = "fm3.domain_name_to_replace.dkim.fmhosted.com"
      type          = "CNAME"
    }
}

# personal_website_target_url = "personal-website-93q.pages.dev"

bulk_redirect_list = {
    redirect_www = {
      name                  = "Redirect www"
      source_url            = "https://www.domain_name_to_replace"
      target_url            = "https://domain_name_to_replace"
    }
}
