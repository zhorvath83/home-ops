---
title: pocket-id-email-sending
type: progress-note
permalink: home-ops/docs/progress/pocket-id-email-sending
status: done
roadmap: merged from docs/roadmap/pocket-id-email-sending (deleted at completion)
priority: medium
area: iam
created: 2026-08-15
tags:
- progress
- iam
- pocket-id
- email
- smtp2go
---

# pocket-id-email-sending — transactional email for the IdP

## Meta

- [assessed] 2026-08-05 — repo state verified against pocket-id helmrelease/externalsecret/CNP, Pocket ID v2.13.0-distroless docs (https://pocket-id.org/docs/configuration/environment-variables), and the shared SMTP2GO 1Password item shape (pingvin-share-x externalsecret).
- [confidence] high on the gap (helmrelease had no SMTP_* env, externalsecret no smtp2go extract); high on the relay path already open (CNP committed in 012239c16); high on UI_CONFIG_DISABLED scope (global override, confirmed against official docs); the recommended-option uncertainty (Phase 0 admin-UI audit) was resolved below by pinning every override var.
- [depends_on] [[iam]] (Pocket IdP), [[external-secrets]] (onepassword-connect ClusterSecretStore + shared smtp2go item), [[cloudflare]] (SMTP2GO SPF/DKIM/DMARC DNS for .msg — already in place).
- [convention] One shared SMTP2GO 1Password item HomeOps/smtp2go (fields smtp_hostname/port/from/user/password), extracted via dataFrom with a smtp2go_ prefix rewrite (same shape as pingvin-share-x). Implicit TLS on 465 → SMTP_TLS=tls.

## Current state (2026-08-05, pre-implementation)

| Layer | State | Evidence |
|---|---|---|
| CiliumNetworkPolicy egress | DONE — mail-eu.smtp2go.com:465 (implicit TLS), *.smtp2go.com wildcard | ciliumnetworkpolicy.yaml:24-31 (commit 012239c16) |
| SMTP2GO 1Password item | DONE — shared item HomeOps/smtp2go | consumed by pingvin-share-x externalsecret.yaml:18-29 |
| SMTP2GO DNS (SPF/DKIM/DMARC) | DONE — .msg subdomain | provision/cloudflare/dns_records.tf:160-192 |
| HelmRelease SMTP env | MISSING — no SMTP_*, no UI_CONFIG_DISABLED, no EMAIL_* flags | helmrelease.yaml env block |
| ExternalSecret smtp2go extract | MISSING — template only ENCRYPTION_KEY + MAXMIND_LICENSE_KEY | externalsecret.yaml |
| Feature flags | MISSING — all EMAIL_*_ENABLED default false | not set anywhere |
| Delivery verification | MISSING — no test mail | n/a |

Net: the network path and relay credentials already existed (used by two other apps); the IdP was not wired into them. The CNP rule was committed ahead of config — a dangling egress allow with no in-pod consumer, which this item closes.

## Target state

Pocket IdP sends outbound transactional mail via SMTP2GO (mail-eu.smtp2go.com:465, implicit TLS), credentials from the shared HomeOps/smtp2go 1Password item through the existing onepassword-connect ClusterSecretStore, configuration fully in git (env-var override path).

### Email feature flags — selection

| Flag | Target | Rationale |
|---|---|---|
| EMAIL_LOGIN_NOTIFICATION_ENABLED | ON | new-device login alert; additive security signal, the main reason for this item |
| EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED | ON | admin can email a login code to a locked-out passkey user; recovery without weakening the unauthenticated surface |
| EMAIL_API_KEY_EXPIRATION_ENABLED | ON | operational awareness for Terraform/admin API key expiry; low risk |
| EMAIL_VERIFICATION_ENABLED | ON | verify email ownership on signup and email change |
| EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED | OFF | docs warn it "reduces the security significantly" — anyone with mailbox access bypasses passkeys. Contradicts the passkey-only policy. Do NOT enable. |
| REQUIRE_USER_EMAIL | true | default; needed for the above to be meaningful |
| SMTP_TLS | tls | port 465 = implicit TLS / SMTPS, not STARTTLS |
| SMTP_SKIP_CERT_VERIFY | false | SMTP2GO presents a valid public cert |

### Configuration surface — analysis

UI_CONFIG_DISABLED is global: true overrides the admin UI for EVERY app setting (APP_NAME, SESSION_DURATION, HOME_PAGE_URL, ALLOW_USER_SIGNUPS, LDAP_*, accent color, …), not only email. Two paths were considered:

- **Option A (chosen, recommended) — env-var override, UI_CONFIG_DISABLED=true**: full GitOps, matches the uniform ExternalSecrets model, no IdP-specific debt. Cost: must mirror every non-default UI value into env or the next rollout silently resets it — resolved by pinning every override var the docs list (see Decision below).
- **Option B — admin UI only, leave UI_CONFIG_DISABLED unset**: lighter, but the IdP email config lives only in the admin UI / app DB, unreproducible from git, invisible to just pocket-id audit. Same debt as calibre-web-automated's OIDC secret (iam §8). Rejected for the trust root.

## Open questions / risks (resolved at implementation)

- [question, resolved] UI_CONFIG_DISABLED scope acceptance — Option A chosen; every UI config value owned in env. Re-audit on Pocket ID upgrades that add new UI fields.
- [question, resolved] Phase 0 audit access — eliminated by pinning every override var to documented defaults; the human's commit-time review replaced the DB/admin-UI read.
- [question, resolved] LDAP in use? — confirmed unused; LDAP_ENABLED=false explicit, attribute maps left to defaults.
- [risk, mitigated] silent config reset on rollout — mitigated by pinning every override var; human-verified the UI did not reset after the rollout.
- [risk, accepted] feature-flag interaction with passkey-only posture — EMAIL_VERIFICATION_ENABLED on signup is fine (the external route blocks /signup); one-time-access-as-unauthenticated stays OFF.
- [risk, accepted] SMTP2GO as a shared dependency — three consumers of one relay (pingvin-share-x, calibre-web-automated, IdP). A relay outage silences IdP notifications but does not break auth (passkey login is unaffected).
- [debt, closed] the CNP SMTP2GO egress rule (012239c16) was committed ahead of this item with no in-pod consumer — this item closes the dangling allow.

## Decision (with human, 2026-08-15)

- [decision] Config surface: **Option A** — UI_CONFIG_DISABLED=true. GitOps-pure; SMTP +
  email flags + all override-able UI config driven from env / ExternalSecret. The Pocket ID
  docs are explicit: SMTP_* and EMAIL_* env vars are effective ONLY with UI_CONFIG_DISABLED=true
  (admin UI is the default source), so there is no middle path that puts only SMTP in git.
- [decision] **Pin every override-able env var the docs list**, not only the email ones. This
  makes the global override fully deterministic and removes the roadmap's Phase 0 admin-UI
  audit: the desired state is defined in git, and the human's commit-time review replaces the
  DB/admin-UI read as the source of truth for "did I customize X?".
- [decision] Delivery: direct commits to main (repo norm; Flux watches refs/heads/main), per
  the envoy-crowdsec-bouncer precedent.
- [decision] LDAP is unused (the iam area does not mention it): LDAP_ENABLED=false explicit,
  the 18 LDAP_* attribute maps left to defaults (dead config with the gate off). Human to
  confirm at review.

## Review gate (replaces Phase 0)

Vars pinned to documented defaults that the human may have customized — confirm at review:
APP_NAME (default "Pocket ID"), SESSION_DURATION (default 60), HOME_PAGE_URL
(default /settings/account), ALLOW_OWN_ACCOUNT_EDIT (default true), DISABLE_ANIMATIONS
(default false), ACCENT_COLOR (default "default"), LDAP_ENABLED (default false / unused).

## Phases (adapted)

### Phase 1 — secret delivery
- [ ] Extend externalsecret.yaml: add dataFrom extract of key `smtp2go` with smtp2go_ prefix
  rewrite (same shape as pingvin-share-x); add template.data SMTP_HOST/PORT/FROM/USER/PASSWORD
  mapped from the extract, SMTP_TLS: "tls", SMTP_SKIP_CERT_VERIFY: "false".
- [ ] Confirm ExternalSecret Ready + pocket-id-secret renders SMTP_* keys.

### Phase 2 — helmrelease env + feature flags
- [ ] Add to helmrelease env: UI_CONFIG_DISABLED: "true" + the full override-var set
  (APP_NAME, SESSION_DURATION, HOME_PAGE_URL, REQUIRE_USER_EMAIL, EMAILS_VERIFIED,
  ALLOW_OWN_ACCOUNT_EDIT, ALLOW_USER_SIGNUPS: "disabled", DISABLE_ANIMATIONS, ACCENT_COLOR,
  LDAP_ENABLED: "false", WEBAUTHN_*, CIMD_URL_ALLOWLIST) + the 4 EMAIL_* flags ON and the
  one-time-access-as-unauthenticated flag OFF. SMTP_* stay in the secret (envFrom).
- [ ] Flux reconcile; pod redeploys via reloader; verify no config reset.

### Phase 3 — delivery test + audit + docs
- [ ] Trigger login-from-new-device notification or admin one-time code; confirm mail arrives
  from SMTP_FROM, DMARC-aligned on .msg subdomain.
- [ ] just pocket-id audit (zero unrestricted clients — no regression).
- [ ] VictoriaLogs: no SMTP dial/auth errors.
- [ ] Document enabled flags + UI_CONFIG_DISABLED decision in [[iam]] §1; bump verified_at.

## Acceptance criteria (from roadmap)

1. Pod sends mail via mail-eu.smtp2go.com:465, SMTP_TLS=tls, creds from HomeOps/smtp2go via
   ExternalSecret — no SMTP credential committed to git.
2. Test transactional mail arrives, DMARC-aligned on .msg, no pod-side SMTP error in logs.
3. EMAIL_LOGIN_NOTIFICATION_ENABLED, EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED,
   EMAIL_API_KEY_EXPIRATION_ENABLED, EMAIL_VERIFICATION_ENABLED ON;
   EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED OFF.
4. UI_CONFIG_DISABLED=true AND every override-able non-default-relevant value mirrored into
   env (APP_NAME, SESSION_DURATION, ALLOW_USER_SIGNUPS, LDAP_*, etc.) — no silent reset.
5. pocket-id-external HTTPRoute /signup + /api/signup 403 still hold; ALLOW_USER_SIGNUPS=disabled
   agrees (no open signup via the override).
6. just pocket-id audit unchanged; iam area-reference updated + verified_at bumped.

## Session 1 — 2026-08-15

- Verified current state against repo + current Pocket ID docs (helmrelease is v2.13.0-distroless;
  env vars match the live docs, no drift). CNP egress (mail-eu.smtp2go.com:465), the shared
  HomeOps/smtp2go 1Password item, SPF/DKIM/DMARC DNS, and the pocket-id-external HTTPRoute
  /signup + /api/signup 403 blocks are all already DONE.
- Decision recorded above (Option A, pin all override vars, review-gate replaces Phase 0).
- Next: edit externalsecret.yaml + helmrelease.yaml, validate, present for human review before
  commit.


## Session 1 outcome (2026-08-15, pre-push)

- Edits applied and committed (574483936): externalsecret.yaml (smtp2go dataFrom extract +
  SMTP_* template.data; SMTP_TLS=tls, SMTP_SKIP_CERT_VERIFY=false) and helmrelease.yaml
  (UI_CONFIG_DISABLED=true + full override-var set + email flags).
- Human review completed: APP_NAME customized to "IdM"; SESSION_DURATION / HOME_PAGE_URL /
  ALLOW_OWN_ACCOUNT_EDIT / DISABLE_ANIMATIONS / ACCENT_COLOR kept at documented defaults; LDAP
  confirmed not in use; point-3 security decisions agreed.
- 21 override-vars excluded as dead config / alternative form (human confirmed "nem kell holt
  konfig"): 2 SIGNUP_DEFAULT_* (signup disabled), 18 LDAP_* attribute maps (LDAP off),
  SMTP_PASSWORD_FILE (using SMTP_PASSWORD). No silent-reset risk — gates explicitly off.
- Validation green: yamlfmt, yamllint, gitleaks, smartquote, unencrypted-secrets.
- Next: docs commit (this note), then human-approved push -> Flux reconcile -> pod redeploys
  via reloader -> Phase 3 delivery test (login-from-new-device notification or admin one-time
  code; DMARC check on .msg; just pocket-id audit; VictoriaLogs SMTP errors), then iam §1 +
  verified_at bump.


## Session 1 — push + delivery (2026-08-15)

- Human pushed 574483936 (code) + d638e18c2 (docs) to origin/main; Flux reconciled; pod
  redeployed with UI_CONFIG_DISABLED=true + the full override set + SMTP_* from ExternalSecret.
- Delivery test (human-verified, live): transactional mail arrived, DMARC-aligned on .msg;
  no pod-side SMTP error; UI config did not reset (override vars pinned). just pocket-id audit
  unchanged.
- Status: DONE. Phase 3 docs closure = this progress-note update + the iam area-reference
  Update section (same commit).
