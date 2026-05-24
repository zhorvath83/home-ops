plugin "cloudflare" {
  enabled = true
}

plugin "ovh" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = false
}
