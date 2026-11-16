resource "pocketid_client" "this" {
  for_each = local.clients

  name                 = each.value.friendly_name
  client_id            = each.key
  callback_urls        = concat([each.value.callback_url], each.value.extra_callback_urls)
  logout_callback_urls = [each.value.logout_url]

  is_public    = each.value.is_public
  pkce_enabled = each.value.pkce_enabled

  allowed_user_groups = [for g in each.value.groups : pocketid_group.this[g].id]

  lifecycle {
    # Pocket ID itself denies everyone when a client is group-restricted with no groups.
    # This provider does not expose that flag though — it derives it as "list is non-empty",
    # so an empty list reaches the API as "not restricted" and lets every account in.
    precondition {
      condition     = length(each.value.groups) > 0
      error_message = "Pocket ID client '${each.key}' has no allowed group; that would let every account in."
    }
    # Without a secret, PKCE is the only thing binding the code to the client that asked for it.
    precondition {
      condition     = !each.value.is_public || each.value.pkce_enabled
      error_message = "Pocket ID client '${each.key}' is public but has PKCE disabled."
    }
  }
}
