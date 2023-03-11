locals {
  # mta_sts_policy.tpl contains !!!CRLF-separated!!! key/value pairs.
  # MTA-STS validator: https://esmtp.email/tools/mta-sts/
  mta_sts_policy    = templatefile("${path.module}/templates/mta_sts_policy.tpl", { mode = var.mail_mta_sts_params.mode, mx = var.dns_mx_records, max_age = var.mail_mta_sts_params.max_age })
  mta_sts_policy_id = md5(local.mta_sts_policy)
}

locals {
  domain_name = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  cf_zone_id  = lookup(data.cloudflare_zones.domain.zones[0], "id")
}

output "mta_sts_policy" {
 value       = local.mta_sts_policy
 description = "MTA-STS policy"
 sensitive   = false
}

resource "cloudflare_record" "cname_root" {
  name    = local.domain_name
  zone_id = local.cf_zone_id
  value   = var.private_website_target_url
  proxied = true
  type    = "CNAME"
  ttl     = 1
}

# Redirected to root via CF bulk redirects
resource "cloudflare_record" "cname_www" {
  name    = "www"
  zone_id = local.cf_zone_id
  value   = "192.0.2.1"
  proxied = true
  type    = "A"
  ttl     = 1
}

#
# Mx records
#
resource "cloudflare_record" "mx_record" {
  # count = length(var.dns_mx_records)
  for_each = var.dns_mx_records
  name    = local.domain_name
  zone_id = local.cf_zone_id
  # value   = var.dns_mx_records[count.index].server
  value   = each.value.host
  proxied = false
  type    = "MX"
  ttl     = 1
  priority = each.value.priority
}

#
# SPF record
#
resource "cloudflare_record" "txt_record_spf" {
  name    = local.domain_name
  zone_id = local.cf_zone_id
  value   = var.dns_spf_record_value
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# DKIM record
#
resource "cloudflare_record" "dkim_record" {
  for_each  = var.dns_dkim_records
  name      = each.value.name
  zone_id   = local.cf_zone_id
  value     = replace(each.value.value, "domain_name_to_replace", "${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}")
  proxied   = false
  type      = each.value.type
  ttl       = 1
}

#
# Webmail A records
#
# Redirected via CF bulk redirects
resource "cloudflare_record" "a_record_webmail" {
  name    = "mail"
  zone_id = local.cf_zone_id
  value   = "192.0.2.1"
  proxied = true
  type    = "A"
  ttl     = 1
}

#
# DNS SRV autodiscovery records
# https://www.fastmail.help/hc/en-us/articles/360060591153#dnslist

resource "cloudflare_record" "srv_records" {
  for_each  = var.dns_srv_records
  zone_id = local.cf_zone_id
  name    = format("%s.%s.%s", each.value.service, each.value.proto, local.domain_name)
  type    = "SRV"
  ttl     = "1"
  data {
    name     = local.domain_name
    service  = each.value.service
    proto    = each.value.proto
    priority = each.value.priority
    weight   = each.value.weight
    port     = each.value.port
    target   = each.value.target
  }
}

#
# DMARC record
#

resource "cloudflare_record" "txt_record_dmarc" {
  name    = "_dmarc"
  zone_id = local.cf_zone_id
  value   = "v=DMARC1; p=reject; rua=${join(",", var.mail_dmarc_rua_dest)}; ruf=${join(",", var.mail_dmarc_ruf_dest)}; sp=reject; adkim=s; aspf=s; pct=100"
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# Mail MTA-STS
#

resource "cloudflare_record" "txt_record_smtp_tls" {
  zone_id = local.cf_zone_id
  name    = "_smtp._tls"
  type    = "TXT"
  value   = "v=TLSRPTv1; rua=${join(",", var.mail_tls_rua_dest)}"
}

resource "cloudflare_record" "txt_record_mta_sts" {
  zone_id = local.cf_zone_id
  name    = "_mta-sts"
  type    = "TXT"
  value   = "v=STSv1; id=${local.mta_sts_policy_id}"
}

resource "cloudflare_record" "a_record_mta_sts" {
  zone_id = local.cf_zone_id
  name    = "mta-sts"
  type    = "A"
  value   = "192.0.2.1"
  proxied = true
}

resource "cloudflare_record" "aaaa_record_mta_sts" {
  zone_id = local.cf_zone_id
  name    = "mta-sts"
  type    = "AAAA"
  value   = "100::"
  proxied = true
}
