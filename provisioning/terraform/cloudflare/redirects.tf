# Redirect list
resource "cloudflare_list" "my_redirect_list" {
  account_id  = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ACCOUNT_ID"]
  name        = "my_redirect_list"
  description = "My custom redirect list"
  kind        = "redirect"

  item {
    value {
      redirect {
        source_url            = "https://www.${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}"
        target_url            = "https://${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}"
        status_code           = 301
        include_subdomains    = "enabled"
        subpath_matching      = "enabled"
        preserve_query_string = "enabled"
        preserve_path_suffix  = "enabled"
      }
    }
    comment = "Redirect www"
  }

  item {
    value {
      redirect {
        source_url  = "https://mail.${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}"
        target_url  = "https://app.fastmail.com"
        status_code = 301
      }
    }
    comment = "Redirect webmail"
  }

}

# Redirects based on a List resource
resource "cloudflare_ruleset" "my_bulk_redirects" {
  account_id  = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ACCOUNT_ID"]
  name        = "my_bulk_redirects"
  description = "My custom redirects"
  kind        = "root"
  phase       = "http_request_redirect"

  rules {
    action = "redirect"
    action_parameters {
      from_list {
        name = "my_redirect_list"
        key  = "http.request.full_uri"
      }
    }
    expression  = "http.request.full_uri in $my_redirect_list"
    description = "Apply redirects from my_redirect_list"
    enabled     = true
  }
}
