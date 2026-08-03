---
title: cloudflare
type: area_reference
permalink: home-ops/docs/areas/cloudflare
area: cloudflare
status: current
confidence: high
verified_at: '2026-08-03'
summary: Cloudflare resources for the public domain (DNS zone, Zero Trust Access apps,
  Cloudflared tunnel, Workers + KV for MTA-STS, WAF rules, zone settings,
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
- provision/cloudflare/templates/mta_sts_policy.tpl
- provision/cloudflare/resources/mta_sts.js
- provision/cloudflare/delete_stale_tunnels.sh
- provision/cloudflare/.terraform.lock.hcl
- provision/cloudflare/mod.just
- provision/cloudflare/CLAUDE.md
- provision/CLAUDE.md
- kubernetes/apps/networking/cloudflare-tunnel/app/
- .claude/skills/cloudflare-terraform/SKILL.md
drift_risk: Cloudflare provider has a `renovate:disablePlugin terraform cloudflare/cloudflare`
  inline annotation pinning the provider version — major bumps (4.x -> 5.x already
  happened) tend to break schemas; bumping requires
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
- [verified_at] 2026-08-03

## Summary

All Cloudflare-side resources for the public domain are declared as Terraform under `provision/cloudflare/`. The configuration covers one zone (the Terraform variable `CF_DOMAIN_NAME`), one Cloudflared tunnel (`CF_TUNNEL_NAME`), Zero Trust Access apps with Google OAuth plus a service-token policy scoped to the two hosts that need header-based access, a Workers script serving MTA-STS policy with Workers KV backing, mail-stack DNS (MX/SPF/DKIM/DMARC/MTA-STS/TLSRPT/SMTP2GO), Cloudflare-managed transforms, WAF rules (GitHub-CIDR allowlist on the Flux webhook plus a non-Hungary country block on every other subdomain), zone hardening (SSL strict, TLS 1.2 floor, TLS 1.3 + 0-RTT, HTTP/3, DNSSEC, Bot Management), and Pushover-email-gateway notification policies. There is no R2 bucket in the stack any more.

Terraform state is held in **Terraform Cloud** (organization `zhorvath83`, workspace `cloudflare`). All Cloudflare credentials and Pushover gateway email come in as `TF_VAR_*` environment variables, injected from 1Password through `op run --no-masking --env-file=./.env -- terraform ...`. The four operational entry points are `just cloudflare init|plan|apply|unlock`.

A single Kubernetes consumer of the tunnel lives at `kubernetes/apps/networking/cloudflare-tunnel/`; it does not provision Cloudflare resources, it only runs the `cloudflared` daemon and consumes the tunnel credentials from 1Password via ExternalSecret. Tunnel creation/ID/secret remain Terraform-owned here.

## Components

- [component] Terraform Cloud workspace — org `zhorvath83`, workspace `cloudflare`, `required_version = "~> 1.0"` (provision/cloudflare/main.tf:1-44)
- [component] Cloudflare provider — `cloudflare/cloudflare` pinned with `# renovate:disablePlugin terraform cloudflare/cloudflare` inline directive (provision/cloudflare/main.tf:18-22)
- [component] Other providers — `integrations/github`, `hashicorp/http`, `hashicorp/external`, `hashicorp/random`, `hashicorp/null` (provision/cloudflare/main.tf:13-43)
- [component] Cloudflare zone — `cloudflare_zone.domain` with `type = "full"`, name from the `CF_DOMAIN_NAME` variable (value supplied via TF_VAR from 1Password, so the repo cannot confirm it equals the cluster `${PUBLIC_DOMAIN}`), account from `CF_ACCOUNT_ID` (provision/cloudflare/main.tf:51-57)
- [component] Cloudflared tunnel — `cloudflare_zero_trust_tunnel_cloudflared.home-ops-tunnel` with name `CF_TUNNEL_NAME` and secret `CF_TUNNEL_SECRET`, post-create `null_resource` writes `tunnel_name`/`tunnel_id`/`tunnel_secret` back into 1Password item `cloudflare` in vault `HomeOps` (provision/cloudflare/tunnel.tf:1-16)
- [component] Tunnel DNS CNAME — `external.${PUBLIC_DOMAIN}` → `<tunnel-id>.cfargotunnel.com` proxied (provision/cloudflare/tunnel.tf:18-26)
- [component] Zero Trust Access apps (provision/cloudflare/access.tf:138-244) — four hand-written apps plus a `for_each`-generated bypass set:
  - `Private Cloud` (`*.${CF_DOMAIN_NAME}`, wildcard fallback) — `unrestricted_users_policy` ONLY, `session_duration = "24h"` (:138-153). The service-token (`non_identity`) policy was deliberately removed from this wildcard so the mobile token can no longer bypass identity on every host (rationale comment at :134-137).
  - `Paperless` (`docs`) and `Mealie` (`recipes`) — the only two apps that keep the service-token policy alongside unrestricted-users, because their mobile clients authenticate with CF Access service-token headers (:155-193). Both `24h`.
  - `Private Cloud Photos` (`fenykepek`) — restricted-users policy, `24h` (:196-206).
  - `Flux webhook` (`flux-webhook`) — GitHub-CIDR bypass (:235-244).
  - `public_bypass` — one `for_each` over `local.public_bypass_apps` emitting five no-auth apps: `www` (Private website), `mta-sts` (MTA-STS policy), `share` (File share), `idm` (Identity Management), `books` (Calibre) (:209-231). Cloudflare Access needs one app per hostname, hence the loop.
- [component] Access groups + identity — `UnrestrictedUsers` and `RestrictedUsers` email-include groups, Google OAuth IdP with PKCE, mobile-app service token written back to 1Password as `CF-Access-Client-Id`/`CF-Access-Client-Secret` (provision/cloudflare/access.tf:5-49, :119-129)
- [component] MTA-STS Workers stack — `cloudflare_workers_kv_namespace.mta_sts` + `cloudflare_workers_kv.mta_sts` (key `policy`) + `cloudflare_workers_script.mta_sts_policy` (script source at `resources/mta_sts.js`, binding `POLICY_NAMESPACE`) + `cloudflare_workers_route` on `mta-sts.${PUBLIC_DOMAIN}/*` (provision/cloudflare/workers.tf:1-31)
- [removed 2026-08-03] R2 downloads bucket — `cloudflare_r2_bucket.downloads`, its `downloads.${CF_DOMAIN_NAME}` custom domain and the matching `Private R2 downloads` Access app have all been DELETED from the stack. `provision/cloudflare/r2_bucket.tf` no longer exists and no `r2`/`downloads` reference survives in any .tf file. (`provision/cloudflare/CLAUDE.md` still lists `r2_bucket.tf` in its file-split enumeration — a repo-side leftover, logged as a follow-up.)
- [component] Mail DNS records — MX (3 Zoho hosts with priorities 10/20/50), SPF, DKIM (zmail+zcal selectors), DMARC (p=reject, strict aspf/adkim), TLSRPT, MTA-STS TXT id record + proxied A/AAAA target on `mta-sts.${PUBLIC_DOMAIN}` (provision/cloudflare/dns_records.tf, provision/cloudflare/terraform.tfvars)
- [component] SMTP2GO mail subdomain — `msg` DKIM/return/tracking CNAMEs + `_dmarc.msg` policy (provision/cloudflare/dns_records.tf:159-193)
- [component] Zone WAF ruleset — `cloudflare_ruleset.zone_waf_rules` (NOT `flux_webhook_waf`) holds TWO rules (provision/cloudflare/firewall_rules.tf:31-55):
  1. GitHub-CIDR allowlist on `flux-webhook`: `cloudflare_list.github_hooks_cidr_list` is populated from `https://api.github.com/meta` `hooks` ranges via a `for_each` `cloudflare_list_item`, and everything not in the list is blocked on that host (:1-15, :42-47).
  2. **Non-Hungary country block** on all subdomains except an explicit exception set (`flux-webhook` — the GitHub sender is non-HU; `mta-sts` — foreign MX validators must fetch the policy) (:17-29 locals, :48-53 rule).
- [component] Zone settings — SSL strict, TLS 1.2 floor, TLS 1.3 + 0-RTT, HTTP/3, IPv6, WebSockets, opportunistic onion, DNSSEC active, security level high, browser/cache TTL = 0, Polish/Rocket Loader off, Brotli on, Bot Management with `fight_mode` + JS challenge, global cache-bypass ruleset (provision/cloudflare/zone_settings.tf)
- [component] Managed transforms — `add_visitor_location_headers` managed request header (provision/cloudflare/managed_transforms.tf:4-15)
- [component] Notification policies — Tunnel Health, Tunnel Update, HTTP DDoS (`dos_attack_l7`), Trust-and-Safety abuse report; all email-mechanism, delivered to the `PUSHOVER_CLOUDFLARE_EMAIL` gateway (provision/cloudflare/notification.tf)
- [component] Just recipes — `just cloudflare init|plan|apply|unlock` all wrap `op run --no-masking --env-file=./.env -- terraform ...` (provision/cloudflare/mod.just)
- [component] GitHub IP source — `data "http" "github_ip_ranges"` fetches `https://api.github.com/meta` once per plan; reused by `access.tf` (GitHub-CIDR bypass policy) and `firewall_rules.tf` (WAF list) (provision/cloudflare/main.tf:59-64)

- [component] `delete_stale_tunnels.sh` — operational helper in the area directory that keeps only the newest ACTIVE Cloudflared tunnel and deletes the rest (provision/cloudflare/delete_stale_tunnels.sh)
- [component] Zone settings scale — `zone_settings.tf` declares **27** `cloudflare_zone_setting` resources. Beyond the hardening set already named above it also pins `always_use_https`, `opportunistic_encryption`, `automatic_https_rewrites`, `browser_check`, `challenge_ttl`, `privacy_pass`, `always_online`, `development_mode`, `pseudo_ipv4`, `ip_geolocation`, `max_upload`, `email_obfuscation`, `server_side_exclude`, `hotlink_protection`

## Claims (verified against repo)

- [claim] "Terraform state lives in Terraform Cloud, org `zhorvath83`, workspace `cloudflare`" (evidence: repo, ref: provision/cloudflare/main.tf:5-10, verified: 2026-05-19)
- [claim] "Cloudflare provider is pinned with an inline `# renovate:disablePlugin terraform cloudflare/cloudflare` directive — Renovate is intentionally not bumping this provider automatically" (evidence: repo, ref: provision/cloudflare/main.tf:18-22, verified: 2026-05-19)
- [claim] "Cloudflare provider authentication uses Global API Key (`var.CF_GLOBAL_APIKEY`) + account email (`var.CF_USERNAME`), not an API Token" (evidence: repo, ref: provision/cloudflare/main.tf:46-49 + variables.tf:131-139, verified: 2026-05-19)
- [claim] "The Cloudflared tunnel resource writes its `tunnel_id`/`tunnel_name`/`tunnel_secret` back into 1Password item `cloudflare` (vault `HomeOps`) via a local-exec `op item edit` after creation — the kubernetes-side consumer fetches those from 1Password via ExternalSecret" (evidence: repo, ref: provision/cloudflare/tunnel.tf:9-16 + kubernetes/apps/networking/cloudflare-tunnel/app/externalsecret.yaml, verified: 2026-05-19)
- [claim] "Access mobile-app service token (`MobileAppsServiceToken`) is written back into the same 1Password `cloudflare` item as `CF-Access-Client-Id` + `CF-Access-Client-Secret` via a local-exec `op item edit` after creation" (evidence: repo, ref: provision/cloudflare/access.tf:5-19, verified: 2026-05-19)
- [claim] "Flux webhook is double-protected: a Zero Trust Access app with the `CIDRbasedBypass` policy AND a zone-level WAF ruleset that blocks everything not in `github_hooks_cidr_list` on `flux-webhook.${PUBLIC_DOMAIN}`" (evidence: repo, ref: provision/cloudflare/access.tf:191-201 + firewall_rules.tf:17-33, verified: 2026-05-19)
- [claim] "MTA-STS policy is rendered from `templates/mta_sts_policy.tpl` using the same `var.dns_mx_records` map driving the MX records, with policy id `md5(rendered_policy)` exported via the `_mta-sts` TXT record — the policy file itself is served by a Cloudflare Worker bound to `mta-sts.${PUBLIC_DOMAIN}/*`" (evidence: repo, ref: provision/cloudflare/dns_records.tf:1-7,109-115 + workers.tf:13-31, verified: 2026-05-19)
- [claim] "DMARC policy is `p=reject` with strict aspf+adkim and 100% application; aggregate + forensic reports go to a Mailhardener mailbox (`mailto:35be510b@in.mailhardener.com`)" (evidence: repo, ref: provision/cloudflare/dns_records.tf:88-95 + terraform.tfvars:24-28, verified: 2026-05-19)
- [claim] "Zone settings enforce strict SSL, TLS 1.2 floor, TLS 1.3 + 0-RTT, HTTP/3, IPv6, DNSSEC active, security level high, Bot Management `fight_mode` with JS challenge, and a zone-wide cache-bypass ruleset for any `*.${PUBLIC_DOMAIN}` request" (evidence: repo, ref: provision/cloudflare/zone_settings.tf:2-203, verified: 2026-05-19)
- [claim] "Notification policies route Tunnel Health, Tunnel Update, HTTP DDoS, and Abuse Report events to the Pushover email gateway via `PUSHOVER_CLOUDFLARE_EMAIL`" (evidence: repo, ref: provision/cloudflare/notification.tf:6-63, verified: 2026-05-19)
- [claim] "GitHub hook IP ranges are pulled live from `https://api.github.com/meta` on every plan; both the Access bypass policy and the WAF ruleset list depend on that single `data "http" "github_ip_ranges"` source" (evidence: repo, ref: provision/cloudflare/main.tf:59-64 + access.tf:85-97 + firewall_rules.tf:1-15, verified: 2026-05-19)
- [claim] (OBSOLETE as of 2026-08-03) "R2 bucket `downloads` is in location `EEUR` and exposed via a custom domain with min TLS 1.2; the matching Access app uses bypass-everyone (no auth)" — the entire R2 stack was removed; `r2_bucket.tf` does not exist and no `r2`/`downloads` reference remains in any .tf file (verified: 2026-08-03)
- [claim] "All four Just recipes (`init`, `plan`, `apply`, `unlock`) wrap a single Terraform subcommand inside `op run --no-masking --env-file=./.env -- terraform ...` — there is no raw-terraform path documented" (evidence: repo, ref: provision/cloudflare/mod.just:1-34, verified: 2026-05-19)
- [claim] "The Kubernetes cloudflare-tunnel workload (kubernetes/apps/networking/cloudflare-tunnel/) consumes tunnel credentials only — it does not create or mutate Cloudflare resources; the source of truth for tunnel name/ID/secret remains this Terraform stack" (evidence: repo, ref: kubernetes/apps/networking/cloudflare-tunnel/app/externalsecret.yaml + provision/cloudflare/tunnel.tf, verified: 2026-05-19)

- [claim] "The service-token (`non_identity`) policy is scoped to exactly two Access apps — Paperless (`docs`) and Mealie (`recipes`) — and was deliberately removed from the `Private Cloud` wildcard app, so a leaked mobile token can no longer bypass identity on every host. The rationale is recorded as a comment in the Terraform" (evidence: repo, ref: provision/cloudflare/access.tf:99-109,134-151,155-193, verified: 2026-08-03)
- [claim] "Every Access app session is `24h`. The former `720h` session on the `Private Cloud` wildcard is gone" (evidence: repo, ref: provision/cloudflare/access.tf:143,160,181,201, verified: 2026-08-03)
- [claim] "The five no-auth public hostnames are not hand-written apps: a single `for_each` over `local.public_bypass_apps` emits one Access app per hostname (www, mta-sts, share, idm, books), because Cloudflare Access requires one app per hostname" (evidence: repo, ref: provision/cloudflare/access.tf:209-231, verified: 2026-08-03)
- [claim] "The zone WAF blocks all non-Hungary traffic to every proxied subdomain except an explicit exception set (`flux-webhook`, `mta-sts`). Adding a service that must accept foreign traffic requires adding its host to `local.country_block_exceptions`" (evidence: repo, ref: provision/cloudflare/firewall_rules.tf:17-29,48-53, verified: 2026-08-03)

## Drift Risk

- [drift] Cloudflare provider version is pinned with a Renovate disable annotation (`main.tf:18-22`, `.terraform.lock.hcl` constraints `5.22.0`) — major-version bumps must be done manually. (The earlier claim that `.terraform/providers/` holds "many older versions" is not supportable: the local cache currently holds only 5.22.0, and `.terraform/` is a gitignored, non-authoritative artifact anyway.)
- [drift] The two `null_resource` blocks (tunnel + service token) write secrets back to 1Password via `op item edit` as a one-shot `local-exec` after create. Terraform does not track the 1Password side — if the 1Password item is renamed, deleted, or its fields differ, the Kubernetes consumers silently break. There is no automated reconciliation.
- [drift] Mail-stack DNS uses Zoho as the primary mailbox provider plus SMTP2GO for the `.msg` subdomain. Provider switches require coordinated edits to MX/SPF/DKIM/DMARC plus the MTA-STS Worker template.
- [drift] `192.0.2.1` (TEST-NET-1) and `100::` (IPv6 discard prefix) are used as content for proxied A/AAAA records — these are correct as carriers for Workers/Tunnel-fronted hostnames, but a careless cleanup could mistakenly "fix" them. For `mta-sts` (dns_records.tf:117-133) the rationale still holds: the MTA-STS Worker exists. For **`arfolyam` (dns_records.tf:138-154) it no longer does** — there is no Worker for it (workers.tf contains only `mta_sts_*`) and no Access app either, so those proxied placeholders are dangling and the `Cloudflare Worker for exchange rates` comment at dns_records.tf:136 is stale.
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

## Update 2026-08-03 — staleness re-verification

Full re-verification against the HCL source as part of the `area-reference-staleness-audit`
roadmap item. Previous `verified_at` was 2026-05-22. Verdict on arrival: MAJOR-DRIFT
(1 wrong, 4 incomplete, 2 obsolete, 7 uncovered live facts; 31 claims re-verified true).

- [correction] **The R2 stack is gone.** `r2_bucket.tf` was deleted and no `r2` / `downloads`
  reference survives in any .tf file, along with the matching `Private R2 downloads` Access app.
  The note documented the bucket, its custom domain and its Access app as live.
- [correction] **The Access inventory was substantially reshaped, in the hardening direction.** The
  `Private Cloud` wildcard lost its service-token policy (now scoped to `docs` + `recipes` only, so
  a leaked mobile token no longer bypasses identity everywhere) and its session dropped 720h -> 24h.
  The `Exchange rates` app is gone. Five apps the note never listed exist (Paperless, Mealie, File
  share, Identity Management, Calibre), and the bypass set is now generated by one `for_each` rather
  than written per app. This is the kind of drift where the stale note UNDERSTATES the security
  posture, but it also named a policy attachment that no longer exists.
- [correction] The WAF component described one rule. The ruleset (correctly named
  `cloudflare_ruleset.zone_waf_rules`, not `flux_webhook_waf`) holds TWO: the GitHub-CIDR allowlist
  on the Flux webhook AND a **non-Hungary country block** on every other proxied subdomain. That
  second rule is load-bearing for any new externally-reached endpoint — it has to be added to
  `local.country_block_exceptions` or foreign traffic is blocked.
- [correction] The `arfolyam` proxied A/AAAA placeholders are now dangling: no Worker (workers.tf has
  only `mta_sts_*`) and no Access app back them, and the "Cloudflare Worker for exchange rates"
  comment at dns_records.tf:136 is stale. The note treated `arfolyam` as a functioning host.
- [correction] "The provider cache contains many older versions" is not supportable — the local cache
  holds only 5.22.0, and `.terraform/` is gitignored and non-authoritative. Replaced with the
  `.terraform.lock.hcl` pin as the evidence.
- [correction] "CF_DOMAIN_NAME mirrors the cluster ${PUBLIC_DOMAIN}" is not repo-verifiable (the value
  comes from a TF_VAR sourced from 1Password, and this audit reads no credentials). Downgraded from a
  stated fact to an explicit unknown.
- [addition] Previously uncovered: `delete_stale_tunnels.sh`, the 27-resource scale of
  `zone_settings.tf`, and the `templates/mta_sts_policy.tpl` + `resources/mta_sts.js` files that the
  note cited without listing in `verified_against`.
- [followup] `provision/cloudflare/CLAUDE.md` still lists `r2_bucket.tf` in its file-split
  enumeration. Repo-side leftover, out of scope for this note; logged as a follow-up.
