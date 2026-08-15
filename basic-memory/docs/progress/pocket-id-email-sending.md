---
title: pocket-id-email-sending
type: progress-note
permalink: home-ops/docs/progress/pocket-id-email-sending
status: in-progress
roadmap: '[[pocket-id-email-sending]] (docs/roadmap)'
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

# pocket-id-email-sending — execution progress

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
