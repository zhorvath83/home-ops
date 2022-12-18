resource "cloudflare_record" "cname_root" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "private-website-93q.pages.dev"
  proxied = true
  type    = "CNAME"
  ttl     = 1
}

resource "cloudflare_record" "cname_www" {
  name    = "www"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  proxied = true
  type    = "CNAME"
  ttl     = 1
}

#
# Mx records
#

resource "cloudflare_record" "mx_record_1" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "route1.mx.cloudflare.net"
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = 19
}

resource "cloudflare_record" "mx_record_2" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "route2.mx.cloudflare.net"
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = 78
}

resource "cloudflare_record" "mx_record_3" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "route3.mx.cloudflare.net"
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = 96
}

#
# SPF record
#

resource "cloudflare_record" "txt_record_spf" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "v=spf1 include:_spf.mx.cloudflare.net ~all"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# DKIM record
#

resource "cloudflare_record" "txt_record_dkim" {
  name    = "20221216235325pm._domainkey"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "k=rsa;p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCLdSPNvh5DlPT4jCbXPQbohbZ9Nc+dzRXh7P7ldBxjL4TEQ9tatnsvFupI36gSrJ/2az4cLvwR72gvQMMbCwt11sVUpjEWeVnpDFquH/yvI6uedDsQpUQdS6BorMdVgNQSczCtQ0goQT2Wu6cZXFzHEG9RR8LTPfcHLcc3ImDUCwIDAQAB"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# DMARC record
#

resource "cloudflare_record" "txt_record_dmarc" {
  name    = "_dmarc"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "v=DMARC1; p=reject; sp=reject; rua=mailto:530aa4aa3c83.a@dmarcinput.com; ruf=mailto:530aa4aa3c83.a@dmarcinput.com"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_record" "cname_mail_return_path" {
  name    = "pm_bounces"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "pm.mtasv.net"
  proxied = false
  type    = "CNAME"
  ttl     = 1
}
