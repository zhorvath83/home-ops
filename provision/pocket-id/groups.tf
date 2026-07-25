resource "pocketid_group" "this" {
  for_each = local.registry.groups

  name          = each.key
  friendly_name = each.value.friendly_name
}
