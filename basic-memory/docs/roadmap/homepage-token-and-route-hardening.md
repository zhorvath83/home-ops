---
title: homepage-token-and-route-hardening
type: roadmap
permalink: home-ops/docs/roadmap/homepage-token-and-route-hardening
topic: Least-privilege token + gated route for the dashboard (homepage)
status: proposed
priority: low
scope: Drop the dashboards ServiceAccount token mount if unused, and confirm its externally-exposed
  route sits behind the identity gate, so the convenience dashboard carries no cluster-recon
  token and no open route.
rationale: Removing an unneeded token and gating the route makes the dashboard a pure
  presentation surface with no cluster-visibility value to an attacker.
related_areas:
- k8s-workloads
- iam
---

# Least-privilege token + gated route for the dashboard (homepage)

## Metadata (observation-form, schema validation)

- [topic] Least-privilege token + gated route for the dashboard (homepage)
- [status] proposed
- [priority] low

## What we gain

- The dashboard stops being a source of cluster topology for reconnaissance.
- Its external route matches the auth posture of the other protected apps.
- Clean least-privilege on a widely-reachable app.

## What to do

1. If the Kubernetes widgets are not required, set automountServiceAccountToken:false; if they are, keep the read-only ClusterRole but confirm it is the minimum.
2. Attach forward-auth/OIDC to the dash route (coordinated with forward-auth-coverage-external-data-apps).
3. Verify: dashboard renders; no usable API token in the pod; route requires auth.

## Related

- relates_to [[k8s-workloads]]
- relates_to [[iam]]
- relates_to [[forward-auth-coverage-external-data-apps]]

## Execution plan (research-backed)

### Current state
- Dashboard mounts an API token: `kubernetes/apps/*/homepage/app/helmrelease.yaml:14` → `automountServiceAccountToken: true`; it has a ClusterRole (:73) + ClusterRoleBinding (:132) + serviceAccount (:137).
- Route is internet-facing: HTTPRoute `parentRefs: [envoy-external]` (:150-151) with no SecurityPolicy attached (unlike downloads/* apps).
- The token grants cluster-wide read (get/list pods, nodes, namespaces, httproutes) — recon value if the pod is compromised.

### Target state
- Homepage carries only the API access it actually uses, and its external route is behind the identity gate (or confirmed intentionally public behind CF Access).

### Implementation steps
1. **Determine if the Kubernetes integration is actually used.** Check the homepage config for `kubernetes:` widgets / cluster/resource widgets:
   ```bash
   grep -rnE 'kubernetes|cluster|resources' kubernetes/apps/*/homepage/app/config/ 2>/dev/null
   ```
   - **If NOT used:** set `automountServiceAccountToken: false` in helmrelease.yaml:14 and remove the ClusterRole/Binding (:70-132) + the `kubernetes` provider from settings. Homepage then has zero API surface.
   - **If used:** keep the token but confirm the ClusterRole is minimal read-only (it is per audit — get/list only, no secrets/write); leave as-is, do NOT widen.
2. **Gate the external route.** Attach forward-auth via the component pattern (same as hubble-ui/kopia): add to homepage's `ks.yaml`:
   ```yaml
   spec:
     components: [../../../../components/forward-auth]
     postBuild:
       substitute: { APP: homepage }   # must equal the HTTPRoute name
   ```
   Prereqs: homepage's namespace already in the tinyauth ReferenceGrant (default is in selfhosted/default — verify); define `TINYAUTH_APPS_HOMEPAGE_OAUTH_GROUPS` first (nil-ACL trap). Alternatively, if the dashboard is meant to be public, explicitly confirm it sits behind a CF Access policy and document that.

### Verification
- `kubectl get pod -n <ns> <homepage-pod> -o jsonpath='{.spec.automountServiceAccountToken}'` → false (if disabled), or the token exists but `kubectl auth can-i --list --as=system:serviceaccount:<ns>:homepage` shows only get/list.
- `https://dash.${PUBLIC_DOMAIN}` → prompts for Pocket-ID auth (if gated).
- Dashboard still renders its widgets after the change.

### Rollback & safety
- Re-enable automount / remove the component block. Low blast radius.
- **Risk:** disabling automount breaks the k8s widgets if they ARE used — hence step 1's check first. The nil-ACL trap applies to the forward-auth attach.

### Gotchas & dependencies
- `APP` must match the HTTPRoute name.
- Shares machinery with `forward-auth-coverage-external-data-apps` and `kopia-ui-forward-auth`.

### Effort
S (~1–2h).
