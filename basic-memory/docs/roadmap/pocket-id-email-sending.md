---
title: pocket-id-email-sending
type: roadmap
permalink: home-ops/docs/roadmap/pocket-id-email-sending
topic: Enable Pocket ID to send transactional email through the shared SMTP2GO relay
  so the IdP can emit login-from-new-device notifications, admin-initiated one-time
  login codes, API-key expiry warnings, and signup/email-change verification mail
status: done
priority: medium
scope: 'Wire SMTP delivery into the Pocket IdP (kubernetes/apps/security/pocket-id),
  using the existing shared SMTP2GO 1Password item and the already-deployed SMTP2GO
  egress rule in the pocket-id CiliumNetworkPolicy. Decide the configuration surface
  (env-var override vs admin UI) and the set of email feature flags to enable, then
  verify outbound delivery with a test mail. No new SMTP provider, no new DNS, no
  new network policy is in scope — the relay path is already provisioned; only the
  IdP-side config and secret delivery remain.

  '
rationale: 'Pocket ID is the cluster trust root and the sole OIDC IdP. Today it is
  silent — no login-from-new-device alert, no API-key expiry warning, no email verification
  on signup/email change, no admin recovery path for a locked-out passkey user. Passkey-only
  auth is a strong credential policy, but the absence of any email channel means a
  new-device login is invisible to the account owner and a lost passkey has no self-service
  or admin-assisted recovery via the IdP. The relay path already exists — SMTP2GO
  is the shared mail relay (used by pingvin-share-x and calibre-web-automated), its
  1Password item HomeOps/smtp2go holds smtp_hostname/port/from/user/password, and
  the pocket-id CiliumNetworkPolicy already allows egress to mail-eu.smtp2go.com:465
  (implicit TLS). The remaining work is IdP-side config + secret delivery + feature-flag
  selection + a delivery test. This is a Security > Clarity > Performance item — the
  login notification and verification mail close real gaps in the passkey-only posture;
  the one-time-access-as-unauthenticated flag is explicitly evaluated and left OFF
  because it converts strong passkey auth into email-based codes (anyone with mailbox
  access gets in).

  '
options:
- Env-var override with UI_CONFIG_DISABLED=true (GitOps-pure, recommended) — SMTP
  and ALL UI config driven from env vars / ExternalSecret, reproducible from git,
  matches the uniform secret-delivery model. Requires mirroring the current admin
  UI config (APP_NAME, SESSION_DURATION, ALLOW_USER_SIGNUPS, etc.) into env first
  to avoid a silent reset to defaults at the next rollout.
- Admin UI SMTP config only (lighter, NOT recommended) — leave UI_CONFIG_DISABLED
  unset and enter SMTP + feature flags in the Pocket ID admin UI. Same debt pattern
  as calibre-web-automated app-DB OIDC secret (iam §8 debt) — the IdP own email config
  would sit outside git and ExternalSecrets, unreproducible and invisible to just
  pocket-id audit/lint. Rejected for the trust root.
related_areas:
- iam
- external-secrets
- cloudflare
tags:
- roadmap
- iam
- pocket-id
- email
- smtp2go
- external-secrets
- proposed
---

# pocket-id-email-sending — transactional email for the IdP

## Meta

- [assessed] 2026-08-05 — repo state verified against pocket-id helmrelease/externalsecret/CNP, Pocket ID v2.12.0-distroless docs (https://pocket-id.org/docs/configuration/environment-variables), and the shared SMTP2GO 1Password item shape (pingvin-share-x externalsecret)
- [confidence] high on the gap (helmrelease has no SMTP_* env, externalsecret has no smtp2go extract); high on the relay path already being open (CNP committed in 012239c16); high on the UI_CONFIG_DISABLED scope (global override, confirmed against official docs); medium on the recommended option (env-var override is the right pattern, but the Phase 0 admin-UI config audit to avoid a silent reset is unverified — current UI values are not in git)
- [depends_on] [[iam]] (Pocket IdP), [[external-secrets]] (onepassword-connect ClusterSecretStore + shared smtp2go item), [[cloudflare]] (SMTP2GO SPF/DKIM/DMARC DNS for the .msg subdomain — already in place)
- [convention] One shared SMTP2GO 1Password item HomeOps/smtp2go with fields smtp_hostname/smtp_port/smtp_from/smtp_user/smtp_password, extracted via dataFrom with a smtp2go_ prefix rewrite (same shape as pingvin-share-x externalsecret). Implicit TLS on port 465 → SMTP_TLS=tls.

## Current state (2026-08-05)

| Layer | State | Evidence |
|---|---|---|
| CiliumNetworkPolicy egress | DONE — mail-eu.smtp2go.com:465 (implicit TLS), *.smtp2go.com wildcard | kubernetes/apps/security/pocket-id/app/ciliumnetworkpolicy.yaml:24-31 (commit 012239c16) |
| SMTP2GO 1Password item | DONE — shared item HomeOps/smtp2go, fields smtp_hostname/port/from/user/password | consumed by kubernetes/apps/selfhosted/pingvin-share-x/app/externalsecret.yaml:18-29 |
| SMTP2GO DNS (SPF/DKIM/DMARC) | DONE — CNAME return/dkim/tracking + DMARC _dmarc.msg | provision/cloudflare/dns_records.tf:160-192 |
| HelmRelease SMTP env | MISSING — no SMTP_*, no UI_CONFIG_DISABLED, no EMAIL_* flags | kubernetes/apps/security/pocket-id/app/helmrelease.yaml env block |
| ExternalSecret smtp2go extract | MISSING — template only renders ENCRYPTION_KEY + MAXMIND_LICENSE_KEY | kubernetes/apps/security/pocket-id/app/externalsecret.yaml |
| Feature flags | MISSING — all EMAIL_*_ENABLED at default false | not set anywhere |
| Delivery verification | MISSING — no test mail sent | n/a |

Net: the network path and the relay credentials already exist and are used by two other apps; the IdP just is not wired into them. The CNP rule was committed ahead of the config — it is an empty egress allow with no consumer in the pod env yet.

## Target state

Pocket IdP sends outbound transactional mail via SMTP2GO (mail-eu.smtp2go.com:465, implicit TLS), credentials pulled from the shared HomeOps/smtp2go 1Password item through the existing onepassword-connect ClusterSecretStore, configuration fully in git (env-var override path).

### Email feature flags — target selection

| Flag | Target | Rationale |
|---|---|---|
| EMAIL_LOGIN_NOTIFICATION_ENABLED | ON | new-device login alert; purely additive security signal, the main reason to do this roadmap |
| EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED | ON | admin can email a login code to a locked-out passkey user; recovery path without weakening unauthenticated surface |
| EMAIL_API_KEY_EXPIRATION_ENABLED | ON | operational awareness for Terraform/admin API key expiry; low risk |
| EMAIL_VERIFICATION_ENABLED | ON | verify email ownership on signup and email change; security best practice |
| EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED | OFF | docs warn it "reduces the security significantly" — anyone with mailbox access bypasses passkeys. Contradicts the passkey-only credential policy. Do NOT enable. |
| REQUIRE_USER_EMAIL | true (default) | kept as-is; needed for any of the above to be meaningful |
| SMTP_TLS | tls | port 465 = implicit TLS / SMTPS, not STARTTLS |
| SMTP_SKIP_CERT_VERIFY | false | SMTP2GO presents a valid public cert; no reason to skip |

### Configuration surface — the decision

UI_CONFIG_DISABLED is global: setting it true overrides the admin UI for EVERY app setting (APP_NAME, SESSION_DURATION, HOME_PAGE_URL, ALLOW_USER_SIGNUPS, LDAP_*, accent color, …), not only email. Two viable paths:

- **Option A (recommended) — env-var override, UI_CONFIG_DISABLED=true**: full GitOps, matches the uniform ExternalSecrets model, no IdP-specific debt. Cost: Phase 0 must audit the current admin UI config and mirror every non-default value into env, otherwise the next rollout silently resets it. The current UI values are not in git, so they must be read from the running admin UI before enabling the flag.
- **Option B — admin UI only, leave UI_CONFIG_DISABLED unset**: lighter, but the IdP's email config lives only in the admin UI / app DB, unreproducible from git and invisible to just pocket-id audit. Same debt as calibre-web-automated's OIDC secret (iam §8). Rejected for the trust root.

## Phases

### Phase 0 — audit current admin UI config (no cluster change)
- [ ] Read the current Pocket ID admin UI config (APP_NAME, SESSION_DURATION, HOME_PAGE_URL, ALLOW_OWN_ACCOUNT_EDIT, ALLOW_USER_SIGNUPS, EMAILS_VERIFIED, any LDAP_* in use, accent color) and record the non-default values.
- [ ] Decide whether LDAP is in use (the iam area does not mention LDAP; if unused, LDAP_* env can stay unset and default to disabled — verify, do not assume).
- [ ] Confirm ALLOW_USER_SIGNUPS current value matches the external-route hardening (the pocket-id-external HTTPRoute blocks /signup and /api/signup — signup mode in env must agree, not contradict).

### Phase 1 — secret delivery
- [ ] Extend kubernetes/apps/security/pocket-id/app/externalsecret.yaml template.data with SMTP_HOST/SMTP_PORT/SMTP_FROM/SMTP_USER/SMTP_PASSWORD mapped from the smtp2go extract (smtp2go_smtp_hostname → SMTP_HOST, etc.), SMTP_TLS: "tls", SMTP_SKIP_CERT_VERIFY: "false".
- [ ] Add a dataFrom extract of key smtp2go with the same smtp2go_ prefix rewrite used by pingvin-share-x.
- [ ] Confirm the ExternalSecret goes Ready and the rendered pocket-id-secret contains the SMTP_* keys.

### Phase 2 — helmrelease env + feature flags (Option A)
- [ ] Add to the helmrelease env block: UI_CONFIG_DISABLED: "true", plus every non-default UI config value captured in Phase 0 (APP_NAME, SESSION_DURATION, ALLOW_USER_SIGNUPS, etc.) so the global override does not reset them.
- [ ] Add the email feature flags per the target table: EMAIL_LOGIN_NOTIFICATION_ENABLED: "true", EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED: "true", EMAIL_API_KEY_EXPIRATION_ENABLED: "true", EMAIL_VERIFICATION_ENABLED: "true", and EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED: "false" (explicit, for clarity).
- [ ] Keep SMTP_* out of the helmrelease env (they come from the secret via envFrom); only literals belong in the helmrelease.
- [ ] Flux reconcile; pod redeploys via reloader; verify no config reset (APP_NAME, session length, signup mode match the pre-change admin UI).

### Phase 3 — delivery test + audit
- [ ] Trigger a login-from-new-device notification (or an admin one-time code) and confirm the mail arrives from the SMTP_FROM address, DMARC-aligned on the .msg subdomain.
- [ ] just pocket-id audit — still reports zero unrestricted clients (no regression from the env change).
- [ ] Check VictoriaLogs for the pocket-id pod: no SMTP dial/auth errors; SMTP2GO accepts the submission.
- [ ] Document the enabled feature flags and the UI_CONFIG_DISABLED decision in [[iam]] §1 (Pocket IdP) and the iam area-reference verified_at bump.

## Acceptance criteria

1. The pocket-id pod sends mail through mail-eu.smtp2go.com:465 with SMTP_TLS=tls, credentials from the HomeOps/smtp2go 1Password item via ExternalSecret — no SMTP credential is committed to git.
2. A test transactional mail (login notification OR admin one-time code) arrives at a real mailbox, DMARC-aligned on the .msg subdomain, with no pod-side SMTP error in VictoriaLogs.
3. EMAIL_LOGIN_NOTIFICATION_ENABLED, EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED, EMAIL_API_KEY_EXPIRATION_ENABLED, EMAIL_VERIFICATION_ENABLED are all ON; EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED is explicitly OFF.
4. If Option A is chosen: UI_CONFIG_DISABLED=true is set AND every non-default admin UI config value is mirrored into env — APP_NAME, SESSION_DURATION, ALLOW_USER_SIGNUPS, and any LDAP_* in use — so the next rollout does NOT silently reset them. Verified by diffing the admin UI before and after the rollout.
5. The pocket-id-external HTTPRoute /signup / /api/signup blocks still hold; the signup mode in env agrees with them (no open signup introduced via the global override).
6. just pocket-id audit is unchanged (zero unrestricted clients); the iam area-reference is updated with the new email capability and a fresh verified_at.

## Open questions / risks

- [question] **UI_CONFIG_DISABLED scope acceptance** — Option A is the GitOps-correct choice but the global override is a big hammer. Confirm we are willing to own every UI config value in env (and re-audit on each Pocket ID upgrade that adds new UI fields), or accept Option B's debt for the IdP specifically. Recommended: Option A, because the trust root is the worst place to carry untracked config debt.
- [question] **Phase 0 audit access** — reading the current admin UI config requires admin access to Pocket ID (LAN-only admin route, per iam §2). Confirm the session has it, or schedule the audit as a human step before Phase 1.
- [question] **LDAP in use?** — the iam area does not mention LDAP, but UI_CONFIG_DISABLED covers ~18 LDAP_* vars. If LDAP is configured in the admin UI today, enabling the global override without mirroring those vars would silently break LDAP login. Verify LDAP is unused before Phase 2, or mirror its config.
- [risk] **silent config reset on rollout** — the core hazard of Option A. Mitigated by Phase 0 + the before/after admin UI diff in acceptance criterion 4. If the diff shows a reset, rollback before the pod serves traffic.
- [risk] **feature-flag interaction with the passkey-only posture** — EMAIL_VERIFICATION_ENABLED on signup is fine because the external route blocks /signup; signup happens via admin UI / token, where verification mail is a useful guardrail. EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED stays OFF to preserve passkey-only strength.
- [risk] **SMTP2GO relay as a shared dependency** — pingvin-share-x and calibre-web-automated already depend on it; adding the IdP makes three consumers of one relay. A relay outage silences IdP notifications but does not break auth (passkey login is unaffected). Acceptable; noted, not mitigated.
- [debt] the CNP SMTP2GO egress rule (012239c16) was committed ahead of this roadmap with no in-pod consumer — this roadmap closes that dangling allow.


## Implementation (2026-08-15) — DONE

Delivered via Option A (UI_CONFIG_DISABLED=true with every override var pinned).

- Commits: 574483936 (code: ExternalSecret + helmrelease env) and d638e18c2 (docs: progress
  note), pushed to main by the human; this docs commit closes the roadmap + iam area-ref.
- Delivery: human-verified live — transactional mail arrived DMARC-aligned on .msg, no SMTP
  errors, just pocket-id audit unchanged, UI config did not reset.
- Execution detail, decisions, and acceptance-criteria sign-off: see
  [[pocket-id-email-sending]] (progress). The iam area-reference carries the capability record
  (Update 2026-08-15 section in [[iam]]).
