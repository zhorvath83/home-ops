resource "pocketid_client" "this" {
  for_each = local.clients

  name                 = each.key
  client_id            = each.key
  callback_urls        = [each.value.callback_url]
  logout_callback_urls = [each.value.logout_url]

  is_public    = false
  pkce_enabled = each.value.pkce_enabled

  allowed_user_groups = [for g in each.value.groups : pocketid_group.this[g].id]

  lifecycle {
    # The provider derives Pocket ID's is_group_restricted flag from this list, and an
    # empty list turns the flag off — which lets every account authorize. Fail-open by
    # default, so an empty list must never reach the API.
    precondition {
      condition     = length(each.value.groups) > 0
      error_message = "Pocket ID client '${each.key}' has no allowed group; that would let every account in."
    }
  }
}
