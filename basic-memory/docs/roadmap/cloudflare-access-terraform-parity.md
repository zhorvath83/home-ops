---
title: cloudflare-access-terraform-parity
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-access-terraform-parity
topic: Full IaC parity for Cloudflare Access — every edge authz rule in Terraform
status: proposed
priority: medium
scope: Bring the complete live Cloudflare Access application/policy set (including
  the auth/id issuer hostnames) under provision/cloudflare Terraform, so the edge
  authorization model is fully reproducible from code.
rationale: When Terraform is the complete, authoritative definition of edge authz,
  the entire external security boundary is reviewable, diff-able, and rebuildable
  — no surprise dashboard state, no drift during an apply or a disaster rebuild.
related_areas:
- cloudflare
- iam
options:
- Import existing + codify
- Recreate under Terraform where import is messy
---

# Full IaC parity for Cloudflare Access — every edge authz rule in Terraform

## Metadata (observation-form, schema validation)

- [topic] Full IaC parity for Cloudflare Access — every edge authz rule in Terraform
- [status] proposed
- [priority] medium

## What we gain

- The edge authorization model becomes reproducible and reviewable end to end.
- A terraform apply or a rebuild can never silently change or lose access rules.
- Confidence that the audited posture equals the running posture.

## What to do

1. Reconcile live CF Access apps/policies against provision/cloudflare/access.tf — especially the auth/id issuer hostnames.
2. Import any dashboard-only apps into Terraform state and codify their intended policies.
3. Add a read-only terraform plan drift check in CI to catch future divergence.
4. Verify: a clean plan with no diff against live; login flows unaffected.

## Options

1. Import existing + codify
2. Recreate under Terraform where import is messy

## Related

- relates_to [[cloudflare]]
- relates_to [[iam]]

## Execution plan (research-backed)

### Current state
- `provision/cloudflare/access.tf` defines dedicated Access apps only for: Private Cloud (`*.domain`, :135), Photos (`fenykepek`, :156), www (:169), Flux webhook (:182), MTA-STS (:194), Share (:206). There is **no** app/policy for `idm.${domain}` (Kanidm), yet it is attached to envoy-external (live httproute). Its edge-authz is therefore undefined in code (it falls through the `*.domain` wildcard, which is circular for an IdP) — meaning either undocumented dashboard state or an untracked bypass.
- Provider is cloudflare/cloudflare v5.22.0.

### Target state
- Every live Access application and policy — including auth/id — is represented in Terraform, so `terraform plan` is the authoritative, drift-free definition of edge authorization.

### Implementation steps
1. **Enumerate live Access apps** (needs a token/key with Access read; via op run):
   ```bash
   # list applications for the account
   op run --env-file=./provision/cloudflare/.env -- \
     curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
     "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/apps" | jq '.result[] | {name, domain, id}'
   ```
   Diff this list against the apps declared in access.tf. Expect to find dashboard-only entries for auth/id (or confirm none exist and the wildcard genuinely covers them).
2. **Codify the missing apps/policies.** For auth/id, add dedicated `cloudflare_zero_trust_access_application` + the intended policy (likely a bypass for the IdP endpoints that must be reachable pre-auth, scoped tightly). Model on the existing app blocks in access.tf.
3. **Import any dashboard-only apps** into state rather than recreating (avoids downtime):
   ```bash
   terraform import cloudflare_zero_trust_access_application.auth "$ACCOUNT_ID/$APP_ID"
   ```
   (v5 import ID format is `<account_id>/<application_id>`; confirm in the provider docs for 5.22.0.)
4. **Add a read-only drift check to CI:** a job running `terraform plan -detailed-exitcode` (via op run with a read-scoped token) that fails if there is drift. Wire into `.github/workflows/` (pin actions per convention).
5. `just cloudflare plan` → clean (no diff) once imports + declarations match live. Commit: `🔒 feat(cloudflare): bring all Access apps under Terraform`.

### Verification
- `just cloudflare plan` → "No changes" (state == live).
- The auth/id login flows still work after any apply (test SSO end-to-end).
- CI drift job passes on a clean tree, fails on a hand-made dashboard change (test once).

### Rollback & safety
- If an import goes wrong, `terraform state rm` the resource (does not touch Cloudflare) and retry. Do NOT `apply` a plan that shows destroy/recreate on the IdP apps — that would break login.
- **Risk:** applying an incorrect policy for auth/id can lock out login (circular auth). Verify the intended bypass carefully; test on a low-stakes app first.

### Gotchas & dependencies
- Needs live Cloudflare API access (token with Access:read) — if unavailable now, this item is blocked on obtaining it; that is the single unverifiable edge finding from the audit.
- Dovetails with `cloudflare-api-token-migration`.

### Effort
M (~0.5 day incl. reconciliation + import + CI drift job).
