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

      # Envoy Gateway v1.8 sends no code_challenge, so PKCE would break every gated flow.
      pkce_enabled = c.gate != "envoy"

      groups = try(c.groups, [])
    }
  }
}
