resource "cloudflare_workers_kv_namespace" "mta_sts" {
  account_id  = var.CF_ACCOUNT_ID
  title       = "mta-sts.${var.CF_DOMAIN_NAME}"
}

resource "cloudflare_workers_kv" "mta_sts" {
  account_id    = var.CF_ACCOUNT_ID
  namespace_id  = cloudflare_workers_kv_namespace.mta_sts.id
  key           = "policy"
  value         = local.mta_sts_policy
}

resource "cloudflare_worker_script" "mta_sts_policy" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "mta-sts-${replace(var.CF_DOMAIN_NAME, ".", "-")}"
  content     = file("${path.module}/resources/mta_sts.js")
  kv_namespace_binding {
    name         = "POLICY_NAMESPACE"
    namespace_id = cloudflare_workers_kv_namespace.mta_sts.id
  }
}

resource "cloudflare_worker_route" "mta_sts" {
  zone_id     = lookup(data.cloudflare_zones.domain.zones[0], "id")
  pattern     = "mta-sts.${var.CF_DOMAIN_NAME}/*"
  script_name = cloudflare_worker_script.mta_sts_policy.name
}
