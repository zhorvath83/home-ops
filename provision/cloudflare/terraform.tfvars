dns_mx_records = {
    mx_record_1 = {
      host    = "mx.zoho.eu"
      priority  = 10
    },
    mx_record_2 = {
      host    = "mx2.zoho.eu"
      priority  = 20
    },
    mx_record_3 = {
      host    = "mx3.zoho.eu"
      priority  = 50
    }
}

# Served via Cloudflare Workers
mail_mta_sts_params = {
  mode = "enforce" # Sending MTA policy application, https://tools.ietf.org/html/rfc8461#section-5
  max_age = 604800 # 1 week
}

mail_dmarc_rua_dest = ["mailto:530aa4aa3c83.a@dmarcinput.com", "mailto:35be510b@in.mailhardener.com"]

mail_dmarc_ruf_dest = ["mailto:530aa4aa3c83.f@dmarcinput.com", "mailto:35be510b@in.mailhardener.com"]

mail_tls_rua_dest = ["mailto:35be510b@in.mailhardener.com"]

dns_spf_record_value = "v=spf1 include:zohomail.eu ~all"

dns_dkim_records = {
    dkim_record_zmail = {
      name          = "zmail._domainkey"
      value         = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqAU8lPzdcbs0Xr3cgdTJetWIxARz7vn6FYIWt2Jx09TN8/fplvEF/fhz/Ze5dI6g+6npFnpiviaZSWrPqw0vq1aFfYW4PJEXT+hpGvXKcalAwVnCiHAa+xKuV0asaaYtcDPu/bHd0zUKAxr/cBSGaNdPxoyMeQCGJQmUu9phQ+6aDGGRqZpYHX3w8/EN1lQ/29ra1ee35r9S1fOcyHW3l6OxQZem4xMIlOCA26IIxXWG3ZbGtTgIZZYl+pMR2UaXVBRXEOFfRAPpwnRRjryXLtl2cDqRhtj41+QsRo/9Ce7QKS8kAfzBZbKoI8SbN22E4BB4NAvfvKUbL9hrtGKHAwIDAQAB"
      type          = "TXT"
    },
    dkim_record_zcal = {
      name          = "zcal._domainkey"
      value         = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAx0xGA0RcG3mjHAIRbiZ9zXrRTUa3FdSwzjF7Hp4vzhhCOkzJOhuAthgoSRP3hS4Tnk4PrVlJRcfEzhATPNRHcYL1AMnj1+9jkILncJZzq0vv1oMtVI5ySmkXcU1QTM0GFGKa6u4F05ehI10X9Wc3PDV1flm68lBqGq5K8VfVOGjJ8Jd42cr0JJ7N/NcbbGZtEhW6EEsX7+E+e8BC3LfFUVulGxn6Gh5pqOdcU5vRHRjJD+UPfZWK6rAMvwfXPdEY1thqrD0tJdtdvg5fJJ+GHcbld2VAnxeujeGZHsW/4l7GEoGa+x3t7DMjHyv6WGfZr6eZuaChW4qii4ID1v0bJwIDAQAB"
      type          = "TXT"
    }
}
