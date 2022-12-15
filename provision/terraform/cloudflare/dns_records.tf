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
  value   = "mx.zoho.eu"
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = 10
}

resource "cloudflare_record" "mx_record_2" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "mx2.zoho.eu"
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = 20
}

resource "cloudflare_record" "mx_record_3" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "mx3.zoho.eu"
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = 50
}

#
# SPF record
#

resource "cloudflare_record" "txt_record_spf" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "v=spf1 include:zoho.eu ~all"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# DKIM record
#

resource "cloudflare_record" "txt_record_dkim" {
  name    = "zmail._domainkey"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCg59RywF6hZDuGEeXBDECSH7o8FJY5HNItGbT1Wy2AGCjrfR0GV1GR67PKe5+Qx5Eb2tI7Fs9Ti3RH5xPEz8Q4J5muhhUbjl2qveH4EREv+J5fcKRG85+wxWHBK6O1QU8XXIdcT1nfiUvozaZkTXm5rZ6p3BXWu+xVWBvoKem9uQIDAQAB"
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
  value   = "v=DMARC1; p=reject; rua=mailto:530aa4aa3c83.a@dmarcinput.com; ruf=mailto:530aa4aa3c83.a@dmarcinput.com; sp=reject; adkim=s; aspf=s; pct=100"
  proxied = false
  type    = "TXT"
  ttl     = 1
}
