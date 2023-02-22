# Redirect list
resource "cloudflare_list" "my_redirect_list" {
  account_id  = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ACCOUNT_ID"]
  name        = "my_redirect_list"
  description = "My custom redirect list"
  kind        = "redirect"

  dynamic "item" {
    for_each = var.bulk_redirect_list

    content {
      comment = item.value.name

      value {
        redirect {
          source_url = replace(item.value.source_url, "domain_name_to_replace", "${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}")
          target_url = replace(item.value.target_url, "domain_name_to_replace", "${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}")
          status_code = lookup(item.value, "status_code", 301)
          include_subdomains    = lookup(item.value, "include_subdomains", "disabled")
          subpath_matching      = lookup(item.value, "subpath_matching", "disabled")
          preserve_path_suffix  = lookup(item.value, "preserve_path_suffix", "disabled")
          preserve_query_string = lookup(item.value, "preserve_query_string", "disabled")
        }
      }
    }
  }
}

# CF Bulk redirects based on a List resource
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
