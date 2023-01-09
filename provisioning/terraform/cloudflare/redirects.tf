# Redirect list
resource "cloudflare_list" "my_redirect_list" {
  account_id  = data.sops_file.cluster_secrets.data["stringData.SECRET_CF_ACCOUNT_ID"]
  name        = "my_redirect_list"
  description = "My custom redirect list"
  kind        = "redirect"

  item {
    value {
      redirect {
        source_url = "https://www.${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}"
        target_url = "https://${data.sops_file.cluster_secrets.data["stringData.SECRET_DOMAIN"]}"
      }
    }
    comment = "Redirect www"
  }

}
