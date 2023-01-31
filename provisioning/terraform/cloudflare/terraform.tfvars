# DO NOT modify if Cloudflare mail routing is enabled!
dns_mx_records = {
    mx_record_1 = {
      host    = "route1.mx.cloudflare.net"
      priority  = 19
    },
    mx_record_2 = {
      host    = "route2.mx.cloudflare.net"
      priority  = 78
    },
    mx_record_3 = {
      host    = "route3.mx.cloudflare.net"
      priority  = 96
    }
}

# Served via Cloudflare Workers
mail_mta_sts_params = {
  mode = "testing" # Sending MTA policy application, https://tools.ietf.org/html/rfc8461#section-5
  max_age = 604800 # 1 week
  rua_mail = "35be510b@in.mailhardener.com"
}

dns_spf_record_value = "v=spf1 include:_spf.mx.cloudflare.net -all"

dns_dkim_record_params = {
  name = "20221216235325pm._domainkey"
  value = "k=rsa;p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCLdSPNvh5DlPT4jCbXPQbohbZ9Nc+dzRXh7P7ldBxjL4TEQ9tatnsvFupI36gSrJ/2az4cLvwR72gvQMMbCwt11sVUpjEWeVnpDFquH/yvI6uedDsQpUQdS6BorMdVgNQSczCtQ0goQT2Wu6cZXFzHEG9RR8LTPfcHLcc3ImDUCwIDAQAB"
}

dns_dmarc_record_value = "v=DMARC1; p=reject; rua=mailto:530aa4aa3c83.a@dmarcinput.com; ruf=mailto:530aa4aa3c83.f@dmarcinput.com; sp=reject; adkim=s; aspf=s; pct=100"

dns_mail_return_path_target = "pm.mtasv.net"

private_website_target_url = "private-website-93q.pages.dev"
