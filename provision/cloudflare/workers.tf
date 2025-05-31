resource "cloudflare_workers_kv_namespace" "mta_sts" {
  account_id  = var.CF_ACCOUNT_ID
  title       = "mta-sts.${var.CF_DOMAIN_NAME}"
}

resource "cloudflare_workers_kv" "mta_sts" {
  account_id    = var.CF_ACCOUNT_ID
  namespace_id  = cloudflare_workers_kv_namespace.mta_sts.id
  key_name = "policy"
  value         = local.mta_sts_policy
}

resource "cloudflare_workers_script" "mta_sts_policy" {
  account_id  = var.CF_ACCOUNT_ID
  script_name = "mta-sts-${replace(var.CF_DOMAIN_NAME, ".", "-")}"
  content     = file("${path.module}/resources/mta_sts.js")

  bindings = [
    {
      name         = "POLICY_NAMESPACE"
      type         = "kv_namespace"
      namespace_id = cloudflare_workers_kv_namespace.mta_sts.id
    }
  ]
}

resource "cloudflare_workers_route" "mta_sts" {
  zone_id     = cloudflare_zone.domain.id
  pattern     = "mta-sts.${var.CF_DOMAIN_NAME}/*"
  script      = cloudflare_workers_script.mta_sts_policy.id
}

###########################################################################
# Cloudflare Worker for exchange rates

resource "cloudflare_workers_script" "exchange_rates" {
  account_id  = var.CF_ACCOUNT_ID
  script_name = "exchange-rates-${replace(var.CF_DOMAIN_NAME, ".", "-")}"
  content     = file("${path.module}/resources/exchange_rates.js")
}

resource "cloudflare_workers_route" "exchange_rates" {
  zone_id     = cloudflare_zone.domain.id
  pattern     = "arfolyam.${var.CF_DOMAIN_NAME}/*"
  script      = cloudflare_workers_script.exchange_rates.id
}
