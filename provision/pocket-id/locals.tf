locals {
  cluster_settings = yamldecode(file("${path.module}/../../kubernetes/components/common/vars/cluster-settings.yaml")).data
  public_domain    = local.cluster_settings.PUBLIC_DOMAIN

  registry = yamldecode(file("${path.module}/clients.yaml"))

  clients = {
    for name, c in local.registry.clients : name => {
      host = "${c.subdomain}.${local.public_domain}"

      # /oauth2/callback belongs to the Envoy OIDC filter, not to the IdP; native apps carry their own path.
      callback_url = "https://${c.subdomain}.${local.public_domain}${c.gate == "envoy" ? "/oauth2/callback" : c.callback_path}"
      logout_url   = "https://${c.subdomain}.${local.public_domain}/"

      # Default-on: Envoy always sends a code_challenge, and leaving PKCE optional lets a
      # stolen authorization code be redeemed without the verifier. Override per client
      # only for an app that provably cannot send one.
      pkce_enabled = try(c.pkce_enabled, true)

      groups = try(c.groups, [])
    }
  }
}
