locals {
  mta_sts_policy    = templatefile("${path.module}/templates/mta_sts_policy.tpl", { mode = var.mail_mta_sts_params.mode, mx = var.dns_mx_records, max_age = var.mail_mta_sts_params.max_age })
  mta_sts_policy_id = md5(local.mta_sts_policy)
}

output "mta_sts_policy" {
 value       = local.mta_sts_policy
 description = "MTA-STS policy"
 sensitive   = false
}

resource "cloudflare_record" "cname_root" {
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = var.private_website_target_url
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


resource "cloudflare_record" "mx_record" {
  # count = length(var.dns_mx_records)
  for_each = var.dns_mx_records
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
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
  name    = data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = var.dns_spf_record_value
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# DKIM record
#

resource "cloudflare_record" "txt_record_dkim" {
  name    = var.dns_dkim_record_params.name
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = var.dns_dkim_record_params.value
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
  value   = var.dns_dmarc_record_value
  proxied = false
  type    = "TXT"
  ttl     = 1
}

#
# Mail return path
#

resource "cloudflare_record" "cname_mail_return_path" {
  name    = "pm-bounces"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = var.dns_mail_return_path_target
  proxied = false
  type    = "CNAME"
  ttl     = 1
}

#
# Mail MTA-STS
#

resource "cloudflare_record" "txt_record_smtp_tls" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name    = "_smtp._tls"
  type    = "TXT"
  value   = "v=TLSRPTv1; rua=mailto:${var.mail_mta_sts_params.rua_mail}"
}

resource "cloudflare_record" "txt_record_mta_sts" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name    = "_mta-sts"
  type    = "TXT"
  value   = "v=STSv1; id=${local.mta_sts_policy_id}"
}

resource "cloudflare_record" "a_record_mta_sts" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name    = "mta-sts"
  type    = "A"
  value   = "192.0.2.1"
  proxied = true
}

resource "cloudflare_record" "aaaa_record_mta_sts" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  name    = "mta-sts"
  type    = "AAAA"
  value   = "100::"
  proxied = true
}
