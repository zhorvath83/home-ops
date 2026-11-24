---
title: caa-ct-monitoring
type: roadmap
permalink: docs/roadmap/caa-ct-monitoring
topic: CAA records and Certificate Transparency monitoring for the public domain
status: in-progress
priority: medium
scope: 'Add CAA records to the Cloudflare zone (Terraform, provision/cloudflare) so
  only the CAs actually in use may issue for ${PUBLIC_DOMAIN} and its subdomains,
  and turn on Certificate Transparency monitoring so any certificate issued for the
  zone is reported. Phase 4 (RFC 8657 accounturi/validationmethods pinning) is gated
  on the towonel cutover and on retiring Universal SSL. Out of scope: DNSSEC (already
  active), MTA-STS/TLS-RPT for mail.'
rationale: The zone publishes no CAA record (DoH check 2026-11-23, DNSSEC-validated
  AD=true), so every publicly trusted CA may issue for any name under ${PUBLIC_DOMAIN}.
  A leaked Cloudflare DNS token (cert-manager holds one, the cloudflare Terraform
  workspace another) is enough to pass DNS-01 at any CA, and nothing would report
  the resulting certificate. Behind the Cloudflare proxy a mis-issued certificate
  is mostly theoretical (browsers see the Cloudflare edge certificate); after the
  towonel TLS-passthrough cutover envoy-external presents our own certificate directly,
  and CAA + CT become the main defence and the only detection against domain impersonation.
options:
- 'CT: Cloudflare CT Monitoring via cloudflare_ct_alerting (Terraform, email) — RECOMMENDED'
- 'CT: self-hosted sslmate/certspotter Deployment + PVC with a hook to Alertmanager/Pushover'
- 'CT: SSLMate Cert Spotter hosted (no free tier any more, 15 USD/month)'
- 'CT: crt.sh polling CronJob (free, fragile API)'
- 'CAA: plain issuer allow-list now, accounturi/validationmethods after Universal
  SSL is gone — RECOMMENDED'
- 'CAA: disable Universal SSL now to get strict RFC 8657 pinning (breaks the proxied
  hosts while Cloudflare Tunnel is the ingress) — rejected'
related_areas:
- cloudflare
- networking
- observability
---

# CAA records + Certificate Transparency monitoring

## Metadata (observation-form, schema validation)

- [topic] CAA records and Certificate Transparency monitoring for the public domain
- [status] in-progress — Phases 0–2 live 2026-11-24 (commit c0b47a64d); AC1+AC2 met; AC3 (CT email → Pushover) pending
- [priority] medium
- [researched_at] 2026-11-23
- [effort] S (Phases 1–3), S (Phase 4, later)

## Terms

- **CAA** (Certification Authority Authorization, RFC 8659): a DNS record listing which CAs may issue certificates for a name. A CA must check it at issuance and refuse if it is not listed. `issue` covers normal names, `issuewild` wildcard names.
- **CT** (Certificate Transparency): every publicly trusted certificate must be logged in public append-only logs. A CT monitor watches those logs and reports every new certificate for your names — the detection side of CAA.
- **RFC 8657** `accounturi` / `validationmethods`: CAA parameters that pin issuance to one ACME account and one validation method (e.g. dns-01).

## What we gain

- Issuance limited from "any of ~100 public CAs" to the handful we use (Let's Encrypt, plus the CAs Cloudflare adds for Universal SSL).
- Every certificate for the zone (ours, statichost's, a mis-issued one) is reported by email. A mis-issuance or a token-abuse issuance becomes visible within hours.
- A foundation for the towonel cutover (see [[cloudflare-tunnel-to-towonel]]), where TLS terminates only on envoy-external and CAA/CT pinning is part of its own plan ("CAA pinning + CT monitoring").

## What we accept

- **While Universal SSL is on, account/method pinning is void.** Cloudflare silently adds `issue` and `issuewild` records for `pki.goog; cansignhttpexchanges=yes`, `letsencrypt.org`, `ssl.com`, `sectigo.com` as soon as the zone has any CAA record; they are hidden in the dashboard and invisible to Terraform, but served (`dig CAA`). A plain `letsencrypt.org` value authorises every Let's Encrypt account (tracked as CVE-2026-14440; Cloudflare's recommended mitigation is CT monitoring). Phases 1–3 therefore only narrow the CA set.
- CT alerts are email only (Cloudflare Notifications/webhook delivery announced, not shipped). Delivered straight to the dedicated Pushover email address (D2), so they reach the phone without a mailbox rule. Pushover truncates long email bodies; the subject and hostname still arrive, the full certificate list stays in the Cloudflare dashboard.
- Cloudflare filters its own certificates (Universal, backup, ACM) out of CT alerts by SPKI hash, so a Cloudflare-side issuance is not reported — acceptable, Cloudflare already terminates that traffic.

## Research findings

### Current state (live, 2026-11-23)
- [evidence] No CAA at the apex or at `idm`/`www` (DoH `cloudflare-dns.com/dns-query`, type 257, answer section empty, AD=true). The LAN router intercepts every port-53 query (even `dig @1.1.1.1` and the authoritative `*.ns.cloudflare.com` answer with the k8s-gateway VIP), so **every DNS verification in this item must use DoH**, not `dig`.
- [evidence] Certificates in use:
  | Name | Served by | Issuer |
  |---|---|---|
  | `${PUBLIC_DOMAIN}`, `*.${PUBLIC_DOMAIN}` | cert-manager `networking/horvathzoltan-me` (envoy gateways) | Let's Encrypt (ClusterIssuer `letsencrypt-production`, ACME dns01 via Cloudflare, `profile: shortlived`) |
  | `idm.${PUBLIC_DOMAIN}` | cert-manager `security/pocket-id-tls` (Pocket ID pod, BackendTLSPolicy) | Let's Encrypt |
  | apex, `www` (DNS-only to statichost.eu) | statichost.eu | Let's Encrypt (YE1/YE2 intermediates) |
  | proxied hosts at the Cloudflare edge | Cloudflare Universal SSL | Google Trust Services (WE1), SAN apex + wildcard |
- [fact] statichost.eu documents on-demand certificates but not the CA or validation method; the served chain is Let's Encrypt, most likely HTTP-01/TLS-ALPN-01. **Never set `validationmethods=dns-01` at the apex** — it would break statichost renewals.
- [fact] Cloudflare provider is pinned at 5.29.0 (`provision/cloudflare/main.tf`). `cloudflare_ct_alerting` (zone_id, enabled, emails) exists since 5.24.0. CAA uses `cloudflare_dns_record` with `type = "CAA"` and a `data = { flags, tag, value }` block, one resource per tag/value; earlier v5 releases had CAA bugs (#5411 permanent diff, #5957/#6009 flags), reported fixed — expect a clean second `plan`.
- [fact] Cloudflare CT Monitoring is GA on all plans (Free included) since 2026-08-13, off by default; it reports every logged certificate for hostnames in the zone, including non-Cloudflare CAs and DNS-only names. API `PATCH /zones/{id}/ct/alerting {enabled, emails[]}`. The docs conflict (re-checked 2026-11-24): the API reference and the older docs say Free/Pro zones can only toggle `enabled` and mail every account member with SSL permission on the zone, `emails` being Business/Enterprise only (max 10; the Go SDK page says 100); the GA announcement promises unified recipient settings across plans without stating that Free accepts custom addresses. Whether Free accepts a custom `emails` list stays **unverified** — the dashboard (SSL/TLS → Edge Certificates → Certificate Transparency Monitoring) or the Phase 1 apply decides (Phase 0).
- [fact] Let's Encrypt enforces RFC 8657 in production; CA/B Forum ballot SC098v2 makes it mandatory for all CAs from March 2027. Value syntax: `letsencrypt.org; accounturi=https://acme-v02.api.letsencrypt.org/acme/acct/<id>; validationmethods=dns-01`. The URI is `ClusterIssuer.status.acme.uri`. It changes if the `letsencrypt-production` account key secret is lost/rotated or the server changes — then renewals fail with a CAA error.
- [fact] RFC 8659 tree-climbing: the CA checks the exact name, then each parent, stopping at the first non-empty set; CNAMEs are followed at each step, so a CAA set **at a CNAME target's exact name** overrides our apex policy for that host. Relevant after towonel, where hosts CNAME to the edge (`edge-eu.towonel.dev` published no CAA on 2026-11-14).
- [fact] `iodef` is informational; no CA is documented to send reports. Not used.
- [fact] Self-hosted certspotter needs a long-running Deployment, a PVC for log positions, `-start_at_end` to skip a multi-day backfill, a hook script for delivery and non-trivial bandwidth; SSLMate hosted has no free tier (trial only).

## Design

### CT monitoring
`cloudflare_ct_alerting` in a new `provision/cloudflare/ct_alerting.tf`, `enabled = true`, `emails` from a new `CF_CT_ALERT_EMAILS` variable injected by `op run` like the other `CF_*` variables (never a literal address in the repo). The value is the dedicated Pushover email address (Pushover turns each mail into a notification), stored in 1Password next to the other Pushover credentials. If the Free plan rejects a custom `emails` list (Phase 0 step 2), fallback: alerts go to the account users with SSL permission and a mailbox rule forwards them to the same Pushover address.

Rejected workaround: inviting the Pushover address as a Cloudflare account member with SSL permission just to receive the alerts — it would create a privileged Cloudflare identity whose mailbox (password-reset mail included) is Pushover, a worse posture than the one CT monitoring improves. Third-party monitors (SSLMate hosted, self-hosted certspotter, crt.sh polling) are not reconsidered for the Free-plan case: the mailbox-rule fallback adds no new dependency.

### CAA records (Phases 2–3)
At the apex only (tree-climbing covers every subdomain), via `cloudflare_dns_record`:

| tag | value | why |
|---|---|---|
| `issue` | `letsencrypt.org` | cert-manager (apex, `idm`) and statichost (apex, `www`) |
| `issuewild` | `letsencrypt.org` | cert-manager wildcard |

Cloudflare's hidden additions (GTS, Let's Encrypt, SSL.com, Sectigo) keep Universal SSL working. Effective allow-list: 5 CAs (live 2026-11-24: Let's Encrypt, `pki.goog`, `ssl.com`, `comodoca.com`, `digicert.com`). No explicit Cloudflare CA entries in Terraform — they would duplicate what Cloudflare injects anyway and drift when Cloudflare changes its CA list.

### Pinning (Phase 4, after towonel + Universal SSL off)
- Apex `issuewild`: `letsencrypt.org; accounturi=<production account URI>; validationmethods=dns-01`.
- Per-name `issue` CAA on every explicitly issued subdomain (today only `idm`): same pinned value. Per-name records stop the climb, so the apex `issue letsencrypt.org` (unpinned, for statichost) does not apply to them.
- Apex `issue` stays `letsencrypt.org` without parameters for statichost (apex/www), unless statichost's ACME account can be learnt — it cannot.
- A guard: a `PrometheusRule` or the existing `CertManagerRenewalLate` covers renewal failure; add an annotation to `clusterissuer.yaml` stating that the account key secret is CAA-pinned.

## Plan

### Phase 0 — Preconditions
1. Inventory every CA that issued for the zone in the last 2 years on crt.sh (manual, in a browser: it sends the domain to a third party). Expected: Let's Encrypt, Google Trust Services, maybe SSL.com/Sectigo (Cloudflare). Any other CA (e.g. a mail or hosting provider) must be added to the `issue` list or explained.
2. Check whether the Free plan accepts a custom `emails` list on `cloudflare_ct_alerting`: look for a recipients field in the dashboard first; otherwise the Phase 1 `terraform plan`/`apply` tells.
3. Decide D3 (D1, D2 decided 2026-11-23).

### Phase 1 — CT monitoring first
- Add `ct_alerting.tf` + `CF_CT_ALERT_EMAILS` (variables.tf, `.env` op reference). `just cloudflare plan` → only the new resource; `just cloudflare apply`.
- Record whether enabling reports only newly logged certificates or also recent ones (undocumented).
- Send a test: confirm the first CT email arrives as a Pushover notification (sender not filtered, subject readable).

### Phase 2 — CAA records
- Add the two apex records (`caa_issue_le`, `caa_issuewild_le`) to `dns_records.tf`. `just cloudflare plan` → 2 creates, second plan clean.
- Apply outside cert-manager's renewal window is unnecessary — `shortlived` certificates renew every few days anyway, which is the fast feedback we want.

### Phase 3 — Verify
- DoH `type=CAA` at apex: our 2 records + Cloudflare's injected set; `idm`/`www` inherit (empty own set). DNSSEC AD=true.
- `cmctl renew -n networking horvathzoltan-me` and `cmctl renew -n security pocket-id-tls`: both Ready with a fresh serial; cert-manager logs no CAA error.
- Next statichost renewal: appears in a CT email and the site keeps serving.
- The Phase 1 CT email for the forced cert-manager renewals arrived (proves CT detection end-to-end).
- Update BM `docs/areas/cloudflare` and `provision/cloudflare/CLAUDE.md`.

### Phase 4 — Pinning (gated on [[cloudflare-tunnel-to-towonel]] + Universal SSL disabled)
- After the cutover nothing is proxied: confirm `dig CAA` (DoH) on every CNAME target (towonel edge name) returns nothing, else its set overrides ours for that host.
- Disable Universal SSL; confirm the injected CAA set disappears.
- Add the pinned records from the Design section; force renewals; verify; document in the ClusterIssuer comment that losing `letsencrypt-production` breaks issuance until the CAA URI is updated.

## Implementation (2026-11-24)

- [done] Phase 0 inventory (crt.sh, issued since 2024-11-24, 259 entries): Let's Encrypt 174 (apex, wildcard, `www`, `idm`, `id`, smtp2go `link.*`), Google Trust Services 68 (apex, wildcard, `downloads`), Sectigo 17 (apex + wildcard only — Cloudflare's own). No other CA.
- [done] statichost apex serves Let's Encrypt `YE2` (openssl, 2026-11-24).
- [fact] `link.msg` CNAMEs to `track.smtp2go.net`, which publishes its own `issue letsencrypt.org`; that set governs the host, so our apex CAA cannot break it.
- [decision] CT recipients reuse the existing `PUSHOVER_CLOUDFLARE_EMAIL` variable (same dedicated Pushover gateway the notification policies use) instead of a new `CF_CT_ALERT_EMAILS`; the resource sits in `notification.tf` instead of a new `ct_alerting.tf`, keeping the file split stable.
- [done] `just cloudflare apply`: `cloudflare_ct_alerting.zone` + `caa_issue_le` + `caa_issuewild_le` created; second plan empty (AC1). Free plan accepted the custom `emails` list — the mailbox-rule fallback is not needed.
- [fact] `cloudflare_ct_alerting` cannot be destroyed from Terraform; rollback is `enabled = false`.
- [fact] Cloudflare's injected CAA set is 5 CAs incl. `digicert.com` and lists Sectigo as `comodoca.com` — differs from the research list.
- [done] AC2 (2026-11-24, forced re-issuance via the cert-manager `Issuing=True ManuallyTriggered` status condition — the `cmctl renew` mechanism, `cmctl` not installed locally): `security/pocket-id-tls` revision 27 Ready (notBefore 22:01:19Z), `networking/horvathzoltan-me` revision 42 Ready (notBefore 22:02:50Z), both ACME DNS-01 orders valid, no CAA error.
- [open] AC3: confirm the CT alert for these two certificates arrives as a Pushover notification (Cloudflare documents delivery within hours).

## Acceptance criteria

- AC1: DoH shows `issue`/`issuewild` `letsencrypt.org` at the apex; a second `just cloudflare plan` is empty.
- AC2: forced renewals of both cert-manager certificates succeed after AC1.
- AC3: a CT alert for the AC2 renewals arrives as a Pushover notification via the dedicated Pushover email address.
- AC4 (Phase 4): issuance with a different Let's Encrypt account (staging-to-production test account) is refused with a CAA error; the production issuer still renews.

## Risks and rollback

- Wrong CAA → cert-manager renewals fail; `shortlived` certificates expire within days. Detected by `CertManagerRenewalLate` / `CertManagerCertificateExpired` / `BlackboxTLSCertExpiringSoon`. Rollback: remove the records (`terraform apply`), CAA TTL 1 (auto) → minutes.
- statichost uses a CA other than Let's Encrypt in future → its renewal fails silently on their side; CT email shows the failed CA change only if issuance happens. Mitigation: Phase 0 inventory, and the site's own TLS expiry probe (consider a blackbox probe for the apex).

## Decisions

- **D1 — CT channel**: DECIDED 2026-11-23 — Cloudflare CT Monitoring (email). Rejected: self-hosted certspotter (stateful, bandwidth-heavy pod on a single node).
- **D2 — Delivery**: DECIDED 2026-11-23 — email directly to the dedicated Pushover email address (via `CF_CT_ALERT_EMAILS`); no mailbox rule unless the Free-plan fallback applies.
- **D3 — Phase 4 timing**: plan it into the towonel cutover (RECOMMENDED) or keep as a separate follow-up.

## Relations

- relates_to [[cloudflare-tunnel-to-towonel]]
- relates_to [[cloudflare-access-decommission]]
- relates_to [[cloudflare]]
- relates_to [[networking]]
