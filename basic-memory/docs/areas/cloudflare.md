---
title: cloudflare
type: area_reference
permalink: home-ops/docs/areas/cloudflare
area: cloudflare
status: current
confidence: high
verified_at: '2026-05-22'
summary: Cloudflare resources for the public domain (DNS zone, Zero Trust Access apps,
  Cloudflared tunnel, Workers + KV for MTA-STS, R2 bucket, WAF rules, zone settings,
  notifications) are managed by Terraform in `provision/cloudflare/`. State lives
  in Terraform Cloud (org `zhorvath83`, workspace `cloudflare`). Secrets and the tunnel/service-token
  credentials flow through 1Password via `op run` and `op item edit`. Operational
  entry points are `just cloudflare init|plan|apply|unlock`.
verified_against:
- provision/cloudflare/main.tf
- provision/cloudflare/variables.tf
- provision/cloudflare/terraform.tfvars
- provision/cloudflare/dns_records.tf
- provision/cloudflare/tunnel.tf
- provision/cloudflare/access.tf
- provision/cloudflare/firewall_rules.tf
- provision/cloudflare/zone_settings.tf
- provision/cloudflare/managed_transforms.tf
- provision/cloudflare/notification.tf
- provision/cloudflare/workers.tf
- provision/cloudflare/r2_bucket.tf
- provision/cloudflare/mod.just
- provision/cloudflare/CLAUDE.md
- provision/CLAUDE.md
- kubernetes/apps/networking/cloudflare-tunnel/app/
- .claude/skills/cloudflare-terraform/SKILL.md
drift_risk: Cloudflare provider has a `renovate:disablePlugin terraform cloudflare/cloudflare`
  inline annotation pinning version 5.19.1 — provider major bumps (4.x → 5.x already
  happened, see `.terraform/providers` cache) tend to break schemas; bumping requires
  a careful manual plan. The tunnel and Access service-token `null_resource` blocks
  write back into 1Password via `op item edit` as a post-create side effect — the
  state is not the source of truth for those secrets; rotating either requires manual
  re-coordination. Several DNS A/AAAA records use the documentation IPs `192.0.2.1`
  / `100::` as placeholders for Workers/Tunnel-fronted hostnames — never relied on
  for routing, only as proxied carriers.
tags:
- area-reference
- cloudflare
- provision
- terraform
---

# cloudflare — current state

## Metadata (observation-form, schema validation)
- [area] cloudflare
- [status] current
- [confidence] high
- [verified_at] 2026-05-19

## Summary
All Cloudflare-side resources for the public domain are declared as Terraform under `provision/cloudflare/`. The configuration covers one zone (the Terraform variable `CF_DOMAIN_NAME`, set to the same value as the cluster `${PUBLIC_DOMAIN}`), one Cloudflared tunnel (`CF_TUNNEL_NAME`), Zero Trust Access apps with Google OAuth + service token, a Workers script serving MTA-STS policy with Workers KV backing, R2 bucket for downloads with custom domain, mail-stack DNS (MX/SPF/DKIM/DMARC/MTA-STS/TLSRPT/SMTP2GO), Cloudflare-managed transforms, WAF rules for the Flux webhook (GitHub CIDR allowlist), zone hardening (SSL strict, TLS 1.2 floor, TLS 1.3 + 0-RTT, HTTP/3, DNSSEC, Bot Management), and Pushover-email-gateway notification policies.

Terraform state is held in **Terraform Cloud** (organization `zhorvath83`, workspace `cloudflare`). All Cloudflare credentials and Pushover gateway email come in as `TF_VAR_*` environment variables, injected from 1Password through `op run --no-masking --env-file=./.env -- terraform ...`. The four operational entry points are `just cloudflare init|plan|apply|unlock`.

A single Kubernetes consumer of the tunnel lives at `kubernetes/apps/networking/cloudflare-tunnel/`; it does not provision Cloudflare resources, it only runs the `cloudflared` daemon and consumes the tunnel credentials from 1Password via ExternalSecret. Tunnel creation/ID/secret remain Terraform-owned here.

## Components
- [component] Terraform Cloud workspace — org `zhorvath83`, workspace `cloudflare`, `required_version = "~> 1.0"` (provision/cloudflare/main.tf:1-44)
- [component] Cloudflare provider — `cloudflare/cloudflare` pinned at `5.19.1` with `# renovate:disablePlugin terraform cloudflare/cloudflare` inline directive (provision/cloudflare/main.tf:18-22)
- [component] Other providers — `integrations/github` 6.12.1, `hashicorp/http` 3.6.0, `hashicorp/external` 2.4.0, `hashicorp/random` 3.9.0, `hashicorp/null` 3.3.0 (provision/cloudflare/main.tf:13-43)
- [component] Cloudflare zone — `cloudflare_zone.domain` with `type = "full"`, name from `CF_DOMAIN_NAME` (mirrors cluster `${PUBLIC_DOMAIN}`), account from `CF_ACCOUNT_ID` (provision/cloudflare/main.tf:51-57)
- [component] Cloudflared tunnel — `cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel` with name `CF_TUNNEL_NAME` and secret `CF_TUNNEL_SECRET`, post-create `null_resource` writes `tunnel_name`/`tunnel_id`/`tunnel_secret` back into 1Password item `cloudflare` in vault `HomeOps` (provision/cloudflare/tunnel.tf:1-16)
- [component] Tunnel DNS CNAME — `external.${PUBLIC_DOMAIN}` → `<tunnel-id>.cfargotunnel.com` proxied (provision/cloudflare/tunnel.tf:18-26)
- [component] Zero Trust Access apps — `Private Cloud` (`*.${PUBLIC_DOMAIN}`, service-token + unrestricted-users policies, 720h session), `Private Cloud Photos` (`fenykepek.${PUBLIC_DOMAIN}`, restricted-users policy), `Private website` (`www.${PUBLIC_DOMAIN}`, bypass), `Private R2 downloads` (`downloads.${PUBLIC_DOMAIN}`, bypass), `Flux webhook` (`flux-webhook.${PUBLIC_DOMAIN}`, GitHub-CIDR bypass), `MTA-STS policy` (bypass), `Exchange rates` (`arfolyam.${PUBLIC_DOMAIN}`, bypass) (provision/cloudflare/access.tf:131-225)
- [component] Access groups + identity — `UnrestrictedUsers` and `RestrictedUsers` email-include groups, Google OAuth IdP with PKCE, mobile-app service token written back to 1Password as `CF-Access-Client-Id`/`CF-Access-Client-Secret` (provision/cloudflare/access.tf:5-49, :119-129)
- [component] MTA-STS Workers stack — `cloudflare_workers_kv_namespace.mta_sts` + `cloudflare_workers_kv.mta_sts` (key `policy`) + `cloudflare_workers_script.mta_sts_policy` (script source at `resources/mta_sts.js`, binding `POLICY_NAMESPACE`) + `cloudflare_workers_route` on `mta-sts.${PUBLIC_DOMAIN}/*` (provision/cloudflare/workers.tf:1-31)
- [component] R2 downloads bucket — `cloudflare_r2_bucket.downloads` location `EEUR` with custom domain `downloads.${PUBLIC_DOMAIN}`, min TLS 1.2 (provision/cloudflare/r2_bucket.tf:1-15)
- [component] Mail DNS records — MX (3 Zoho hosts with priorities 10/20/50), SPF, DKIM (zmail+zcal selectors), DMARC (p=reject, strict aspf/adkim), TLSRPT, MTA-STS TXT id record + proxied A/AAAA target on `mta-sts.${PUBLIC_DOMAIN}` (provision/cloudflare/dns_records.tf, provision/cloudflare/terraform.tfvars)
- [component] SMTP2GO mail subdomain — `msg` DKIM/return/tracking CNAMEs + `_dmarc.msg` policy (provision/cloudflare/dns_records.tf:159-193)
- [component] WAF for Flux webhook — `cloudflare_list.github_hooks_cidr_list` populated from `https://api.github.com/meta` `hooks` ranges + `cloudflare_ruleset.flux_webhook_waf` blocking everything but those CIDRs on `flux-webhook.${PUBLIC_DOMAIN}` (provision/cloudflare/firewall_rules.tf:1-33)
- [component] Zone settings — SSL strict, TLS 1.2 floor, TLS 1.3 + 0-RTT, HTTP/3, IPv6, WebSockets, opportunistic onion, DNSSEC active, security level high, browser/cache TTL = 0, Polish/Rocket Loader off, Brotli on, Bot Management with `fight_mode` + JS challenge, global cache-bypass ruleset (provision/cloudflare/zone_settings.tf)
- [component] Managed transforms — `add_visitor_location_headers` managed request header (provision/cloudflare/managed_transforms.tf:4-15)
- [component] Notification policies — Tunnel Health, Tunnel Update, HTTP DDoS (`dos_attack_l7`), Trust-and-Safety abuse report; all email-mechanism, delivered to the `PUSHOVER_CLOUDFLARE_EMAIL` gateway (provision/cloudflare/notification.tf)
- [component] Just recipes — `just cloudflare init|plan|apply|unlock` all wrap `op run --no-masking --env-file=./.env -- terraform ...` (provision/cloudflare/mod.just)
- [component] GitHub IP source — `data "http" "github_ip_ranges"` fetches `https://api.github.com/meta` once per plan; reused by `access.tf` (GitHub-CIDR bypass policy) and `firewall_rules.tf` (WAF list) (provision/cloudflare/main.tf:59-64)

## Claims (verified against repo)
- [claim] "Terraform state lives in Terraform Cloud, org `zhorvath83`, workspace `cloudflare`" (evidence: repo, ref: provision/cloudflare/main.tf:5-10, verified: 2026-05-19)
- [claim] "Cloudflare provider is pinned at version 5.19.1 with an inline `# renovate:disablePlugin terraform cloudflare/cloudflare` directive — Renovate is intentionally not bumping this provider automatically" (evidence: repo, ref: provision/cloudflare/main.tf:18-22, verified: 2026-05-19)
- [claim] "Cloudflare provider authentication uses Global API Key (`var.CF_GLOBAL_APIKEY`) + account email (`var.CF_USERNAME`), not an API Token" (evidence: repo, ref: provision/cloudflare/main.tf:46-49 + variables.tf:131-139, verified: 2026-05-19)
- [claim] "The Cloudflared tunnel resource writes its `tunnel_id`/`tunnel_name`/`tunnel_secret` back into 1Password item `cloudflare` (vault `HomeOps`) via a local-exec `op item edit` after creation — the kubernetes-side consumer fetches those from 1Password via ExternalSecret" (evidence: repo, ref: provision/cloudflare/tunnel.tf:9-16 + kubernetes/apps/networking/cloudflare-tunnel/app/externalsecret.yaml, verified: 2026-05-19)
- [claim] "Access mobile-app service token (`MobileAppsServiceToken`) is written back into the same 1Password `cloudflare` item as `CF-Access-Client-Id` + `CF-Access-Client-Secret` via a local-exec `op item edit` after creation" (evidence: repo, ref: provision/cloudflare/access.tf:5-19, verified: 2026-05-19)
- [claim] "Flux webhook is double-protected: a Zero Trust Access app with the `CIDRbasedBypass` policy AND a zone-level WAF ruleset that blocks everything not in `github_hooks_cidr_list` on `flux-webhook.${PUBLIC_DOMAIN}`" (evidence: repo, ref: provision/cloudflare/access.tf:191-201 + firewall_rules.tf:17-33, verified: 2026-05-19)
- [claim] "MTA-STS policy is rendered from `templates/mta_sts_policy.tpl` using the same `var.dns_mx_records` map driving the MX records, with policy id `md5(rendered_policy)` exported via the `_mta-sts` TXT record — the policy file itself is served by a Cloudflare Worker bound to `mta-sts.${PUBLIC_DOMAIN}/*`" (evidence: repo, ref: provision/cloudflare/dns_records.tf:1-7,109-115 + workers.tf:13-31, verified: 2026-05-19)
- [claim] "DMARC policy is `p=reject` with strict aspf+adkim and 100% application; aggregate + forensic reports go to a Mailhardener mailbox (`mailto:35be510b@in.mailhardener.com`)" (evidence: repo, ref: provision/cloudflare/dns_records.tf:88-95 + terraform.tfvars:24-28, verified: 2026-05-19)
- [claim] "Zone settings enforce strict SSL, TLS 1.2 floor, TLS 1.3 + 0-RTT, HTTP/3, IPv6, DNSSEC active, security level high, Bot Management `fight_mode` with JS challenge, and a zone-wide cache-bypass ruleset for any `*.${PUBLIC_DOMAIN}` request" (evidence: repo, ref: provision/cloudflare/zone_settings.tf:2-203, verified: 2026-05-19)
- [claim] "Notification policies route Tunnel Health, Tunnel Update, HTTP DDoS, and Abuse Report events to the Pushover email gateway via `PUSHOVER_CLOUDFLARE_EMAIL`" (evidence: repo, ref: provision/cloudflare/notification.tf:6-63, verified: 2026-05-19)
- [claim] "GitHub hook IP ranges are pulled live from `https://api.github.com/meta` on every plan; both the Access bypass policy and the WAF ruleset list depend on that single `data "http" "github_ip_ranges"` source" (evidence: repo, ref: provision/cloudflare/main.tf:59-64 + access.tf:85-97 + firewall_rules.tf:1-15, verified: 2026-05-19)
- [claim] "R2 bucket `downloads` is in location `EEUR` and exposed via `downloads.${PUBLIC_DOMAIN}` custom domain with min TLS 1.2; the matching Access app uses bypass-everyone (no auth)" (evidence: repo, ref: provision/cloudflare/r2_bucket.tf:1-15 + access.tf:178-188, verified: 2026-05-19)
- [claim] "All four Just recipes (`init`, `plan`, `apply`, `unlock`) wrap a single Terraform subcommand inside `op run --no-masking --env-file=./.env -- terraform ...` — there is no raw-terraform path documented" (evidence: repo, ref: provision/cloudflare/mod.just:1-34, verified: 2026-05-19)
- [claim] "The Kubernetes cloudflare-tunnel workload (kubernetes/apps/networking/cloudflare-tunnel/) consumes tunnel credentials only — it does not create or mutate Cloudflare resources; the source of truth for tunnel name/ID/secret remains this Terraform stack" (evidence: repo, ref: kubernetes/apps/networking/cloudflare-tunnel/app/externalsecret.yaml + provision/cloudflare/tunnel.tf, verified: 2026-05-19)

## Drift Risk
- [drift] Cloudflare provider version is pinned at 5.19.1 with a Renovate disable annotation — major-version bumps must be done manually. The provider cache under `.terraform/providers/` contains many older versions (4.26.0 → 5.18.0) showing past upgrades were done by hand.
- [drift] The two `null_resource` blocks (tunnel + service token) write secrets back to 1Password via `op item edit` as a one-shot `local-exec` after create. Terraform does not track the 1Password side — if the 1Password item is renamed, deleted, or its fields differ, the Kubernetes consumers silently break. There is no automated reconciliation.
- [drift] Mail-stack DNS uses Zoho as the primary mailbox provider plus SMTP2GO for the `.msg` subdomain. Provider switches require coordinated edits to MX/SPF/DKIM/DMARC plus the MTA-STS Worker template.
- [drift] `192.0.2.1` (TEST-NET-1) and `100::` (IPv6 discard prefix) are used as content for proxied A/AAAA records (`mta-sts`, `arfolyam`) — these are correct as carriers for Workers/Tunnel-fronted hostnames, but a careless cleanup could mistakenly "fix" them.
- [drift] Access uses Cloudflare's **Global API Key** (`CF_GLOBAL_APIKEY`) for the Terraform provider rather than a scoped API Token. Wider blast radius if compromised — flagged as a hardening follow-up rather than current blocker.

## Open Questions / Gaps
- [gap] No verification was run against the live Cloudflare API or Terraform Cloud workspace in this pass — claims are repo-evidence only. `just cloudflare plan` from a credentialed shell is the live-state validation path.
- [gap] The relationship between this stack and the in-cluster cloudflare-tunnel deployment was traced only at the contract level (1Password item shape). Detailed cluster wiring is documented in the networking area-reference.
- [gap] Several Access apps (`Private Cloud` and `Private Cloud Photos` in particular) rely on Google OAuth + user-email allowlists that are themselves Terraform-managed — but the actual `CF_ACCESS_*_USERS` lists come from `TF_VAR_*` env vars not visible in the repo. The note treats those as black-box inputs.
- [gap] No formal disaster-recovery procedure is captured for the case where Terraform Cloud state is lost. Re-importing would require manual coordination with the live Cloudflare account.

## Relations
- relates_to [[networking]]
- relates_to [[ovh-storage]]
- part_of [[home-ops-platform]]
- supersedes [[cloudflare-readme]]
