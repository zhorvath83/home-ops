/*
 * Host on Cloudflare Pages
 */

resource "cloudflare_pages_project" "personal-website" {
  name              = "personal-website"
  account_id        = var.CF_ACCOUNT_ID
  production_branch = "main"

  build_config {
    build_command   = "hugo"
    destination_dir = "public"
  }

  source {
    type = "github"
    config {
      owner                         = var.GITHUB_USER_FOR_PAGES
      repo_name                     = "personal-website"
      production_branch             = "main"
      pr_comments_enabled           = true
      deployments_enabled           = true
      production_deployment_enabled = true
      preview_deployment_setting    = "all"
      preview_branch_includes       = ["*"]
      preview_branch_excludes       = ["main"]
    }
  }  
}

resource "cloudflare_pages_domain" "personal-website" {
  account_id    = var.CF_ACCOUNT_ID
  domain        = var.CF_DOMAIN_NAME
  project_name  = cloudflare_pages_project.personal-website.name
}

resource "cloudflare_record" "personal-website" {
  zone_id = cloudflare_zone.domain.id
  name    = var.CF_DOMAIN_NAME
  content   = cloudflare_pages_project.personal-website.subdomain
  type    = "CNAME"
  proxied = true
}
