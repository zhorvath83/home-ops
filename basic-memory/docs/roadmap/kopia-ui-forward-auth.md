---
title: kopia-ui-forward-auth
type: roadmap
permalink: home-ops/docs/roadmap/kopia-ui-forward-auth
topic: Authenticated Kopia browse UI
status: proposed
priority: low
scope: Put the Kopia web UI behind the cluster forward-auth pattern (as already done
  for hubble-ui) so backup browsing/restore requires identity even on the LAN.
rationale: Gating the Kopia UI ensures backup contents can only be browsed or restored
  by authenticated users, matching the sensitivity of the data it exposes.
related_areas:
- volsync-backup
- iam
---

# Authenticated Kopia browse UI

## Metadata (observation-form, schema validation)

- [topic] Authenticated Kopia browse UI
- [status] proposed
- [priority] low

## What we gain

- Backup browse/restore requires login — LAN presence alone is no longer enough.
- Consistent authentication across all internal admin UIs.
- Reuses an existing, proven pattern (hubble-ui).

## What to do

1. Add the forward-auth component/SecurityPolicy to the pvbackup route.
2. Keep the Kopia repo-password model unchanged (client-side encryption is unaffected).
3. Verify: pvbackup prompts for auth and restore still works after login.

## Related

- relates_to [[volsync-backup]]
- relates_to [[iam]]

## Execution plan (research-backed)

### Current state
- Kopia browse UI runs with no auth: `kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml:36-42` → `KOPIA_WEB_ENABLED: true`, `KOPIA_WEB_PORT: 8080`, args include `--without-password`. Exposed at `pvbackup.${PUBLIC_DOMAIN}` (helmrelease.yaml:89-90) on envoy-internal (LAN-only; the Cloudflare tunnel routes only envoy-external).
- The kopia Flux Kustomization (`kubernetes/apps/volsync-system/kopia/ks.yaml`) does **not** include the forward-auth component.
- Proven pattern to copy: hubble-ui — `kubernetes/apps/kube-system/cilium/ks.yaml:11-20` adds `spec.components: [../../../../components/forward-auth]` + `postBuild.substitute.APP: hubble-ui`. The component (`kubernetes/components/forward-auth/securitypolicy.yaml`) generates a SecurityPolicy targeting the HTTPRoute named `${APP}` via TinyAuth extAuth.

### Target state
- Browsing/restoring via the Kopia UI requires Pocket-ID authentication, even on the LAN — consistent with hubble-ui.

### Implementation steps
1. **Confirm the Kopia HTTPRoute name** (the SecurityPolicy targets an HTTPRoute by `${APP}`): inspect the route object in `helmrelease.yaml` (route key under `route:`) — likely `kopia`. `APP` must equal that route name.
2. **Add volsync-system to the ReferenceGrant.** `kubernetes/apps/security/tinyauth/app/referencegrant.yaml` currently lists networking, selfhosted, media, downloads, kube-system, observability (lines 12-27) — **volsync-system is missing**. Add:
   ```yaml
       - group: gateway.envoyproxy.io
         kind: SecurityPolicy
         namespace: volsync-system
   ```
   Without this, Envoy Gateway rejects the cross-namespace SecurityPolicy → tinyauth reference.
3. **Define the per-app TinyAuth ACL BEFORE attaching** (nil-ACL trap — the pinned TinyAuth defaults to *allow* when no ACL exists). In the tinyauth config/ExternalSecret add `TINYAUTH_APPS_KOPIA_OAUTH_GROUPS` scoped to your admin group.
4. **Attach forward-auth** in `kubernetes/apps/volsync-system/kopia/ks.yaml`:
   ```yaml
   spec:
     components:
       - ../../../../components/forward-auth
     postBuild:
       substitute:
         APP: kopia   # must match the HTTPRoute name
   ```
   (Mirror the exact structure from cilium/ks.yaml:11-20.)
5. Leave `--without-password` as-is — the gate is at Envoy/TinyAuth, not Kopia itself (client-side encryption unaffected). Commit: `🔒 feat(kopia): gate pvbackup UI behind forward-auth`.

### Verification
- `kubectl get securitypolicy -A | grep kopia` → present, Accepted=True.
- Browse `https://pvbackup.${PUBLIC_DOMAIN}` → redirected to Pocket-ID login; only the allowed group gets in.
- `flux reconcile ks kopia -n flux-system` clean; kopia pod healthy; restore via `just volsync` still works.

### Rollback & safety
- Remove the component block from kopia/ks.yaml + the ReferenceGrant entry → back to open UI.
- **Risk (nil-ACL trap):** attaching forward-auth without the per-app OAuth-groups ACL silently lets ANY authenticated user in — always do step 3 before step 4.
- Low blast radius: worst case the UI is unreachable until you fix the ACL/ReferenceGrant; backups themselves are unaffected.

### Gotchas & dependencies
- `APP` must match the HTTPRoute name exactly, or the SecurityPolicy targets nothing.
- ReferenceGrant + ACL are prerequisites (steps 2–3) — order matters.
- Same forward-auth machinery used by `forward-auth-coverage-external-data-apps`.

### Effort
S (~1–2h).
