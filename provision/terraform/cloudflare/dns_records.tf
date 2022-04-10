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

resource "cloudflare_record" "mx_cloudflare_1" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "route1.mx.cloudflare.net"
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = 19
}

resource "cloudflare_record" "mx_cloudflare_2" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "route2.mx.cloudflare.net"
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = 78
}

resource "cloudflare_record" "mx_cloudflare_3" {
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

resource "cloudflare_record" "txt_mailjet_spf" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "v=spf1 include:_spf.mx.cloudflare.net include:spf.mailjet.com ~all"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# DKIM record
#

resource "cloudflare_record" "txt_mailjet_dkim" {
  name    = "mailjet._domainkey"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC1BJw7Se7ThsNr7viitwLgZowXqql4AwfXf1hZ8FiMa+6KbrMHCXxngw3Qp5OUQ24/Etg9XJ7kfEfx4CpONTg+m/fdBnbFlWa+BZFZQdnC8cNZj7ETd9GDm04pKo/Ph3zXRe0TyEpp+tCBmi5sY60o+r3rg5BXk5X8r4/11iOa/QIDAQAB"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# DMARC record
#

resource "cloudflare_record" "txt_dmarc" {
  name    = "_dmarc"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "v=DMARC1; p=reject; rua=mailto:horvathzoltan-d@dmarc.report-uri.com; fo=1"
  proxied = false
  type    = "TXT"
  ttl     = 1
}
