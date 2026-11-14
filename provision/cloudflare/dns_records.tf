locals {
  domain_name = var.CF_DOMAIN_NAME
  cf_zone_id  = cloudflare_zone.domain.id
}

#
# Personal website (statichost.eu)
#
resource "cloudflare_dns_record" "a_record_root" {
  zone_id = local.cf_zone_id
  name    = local.domain_name
  type    = "A"
  content = "95.217.26.94"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "aaaa_record_root" {
  zone_id = local.cf_zone_id
  name    = local.domain_name
  type    = "AAAA"
  content = "2a01:4f9:c01f:8002::"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "www" {
  name    = "www"
  zone_id = local.cf_zone_id
  content = local.domain_name
  proxied = false
  type    = "CNAME"
  ttl     = 1
}

#
# Mx records
#
resource "cloudflare_dns_record" "mx_record" {
  # count = length(var.dns_mx_records)
  for_each = var.dns_mx_records
  name    = local.domain_name
  zone_id = local.cf_zone_id
  # content = var.dns_mx_records[count.index].server
  content = each.value.host
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = each.value.priority
}

#
# SPF record
#
resource "cloudflare_dns_record" "txt_record_spf" {
  name    = local.domain_name
  zone_id = local.cf_zone_id
  content = var.dns_spf_record_value
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# DKIM record
#
resource "cloudflare_dns_record" "dkim_record" {
  for_each  = var.dns_dkim_records
  name      = each.value.name
  zone_id   = local.cf_zone_id
  content   = replace(each.value.value, "domain_name_to_replace", var.CF_DOMAIN_NAME)
  proxied   = false
  type      = each.value.type
  ttl       = 1
}

#
# DMARC record
#

resource "cloudflare_dns_record" "txt_record_dmarc" {
  name    = "_dmarc"
  zone_id = local.cf_zone_id
  content = "v=DMARC1; p=reject; rua=${join(",", var.mail_dmarc_rua_dest)}; ruf=${join(",", var.mail_dmarc_ruf_dest)}; sp=reject; adkim=s; aspf=s; pct=100"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# SMTP2GO BEGIN
#
resource "cloudflare_dns_record" "txt_record_dmarc_msg" {
  name    = "_dmarc.msg"
  zone_id = local.cf_zone_id
  content = "v=DMARC1; p=reject; rua=${join(",", var.mail_dmarc_rua_dest)}; ruf=${join(",", var.mail_dmarc_ruf_dest)}; adkim=s; aspf=r; pct=100"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

resource "cloudflare_dns_record" "smtp2go_return" {
  zone_id = local.cf_zone_id
  name    = "em775735.msg"
  type    = "CNAME"
  content = "return.smtp2go.net"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "smtp2go_dkim" {
  zone_id = local.cf_zone_id
  name    = "s775735._domainkey.msg"
  type    = "CNAME"
  content = "dkim.smtp2go.net"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "smtp2go_tracking" {
  zone_id = local.cf_zone_id
  name    = "link.msg"
  type    = "CNAME"
  content = "track.smtp2go.net"
  proxied = false
  ttl     = 1
}

#
# SMTP2GO END
#
