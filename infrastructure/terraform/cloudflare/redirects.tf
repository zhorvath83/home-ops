# Redirect list
resource "cloudflare_list" "my_redirect_list" {
  account_id  = var.CF_ACCOUNT_ID
  name        = "my_redirect_list"
  description = "My custom redirect list"
  kind        = "redirect"

  dynamic "item" {
    for_each = var.bulk_redirect_list

    content {
      value {
        redirect {
          source_url            = replace(item.value.source_url, "domain_name_to_replace", var.CF_DOMAIN_NAME)
          target_url            = replace(item.value.target_url, "domain_name_to_replace", var.CF_DOMAIN_NAME)
          status_code           = lookup(item.value, "status_code", 301)
          include_subdomains    = lookup(item.value, "include_subdomains", "enabled")
          subpath_matching      = lookup(item.value, "subpath_matching", "enabled")
          preserve_path_suffix  = lookup(item.value, "preserve_path_suffix", "enabled")
          preserve_query_string = lookup(item.value, "preserve_query_string", "enabled")
        }
      }
      comment = item.value.name
    }
  }
}

# CF Bulk redirects based on a List resource
resource "cloudflare_ruleset" "my_bulk_redirects" {
  account_id  = var.CF_ACCOUNT_ID
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
