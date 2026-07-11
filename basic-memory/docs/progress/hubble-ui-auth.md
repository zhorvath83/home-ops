---
title: hubble-ui-auth
type: progress
permalink: home-ops/docs/progress/hubble-ui-auth
topic: Guard the Cilium Hubble UI (hubble.${PUBLIC_DOMAIN}, envoy-internal) with tinyauth
  forward-auth
status: implemented
roadmap: null
related_areas:
- networking
- observability
- iam
- k8s-workloads
decision_link: '[[AD-023-cnp-threat-model-audit]]'
tags:
- progress
- cilium
- hubble
- tinyauth
- forward-auth
- iam
- security
---

# hubble-ui-auth — execution progress

## Metadata (observation-form)

- [topic] Guard the Cilium Hubble UI (hubble.${PUBLIC_DOMAIN}, envoy-internal) with tinyauth forward-auth
- [status] implemented (pending live verify after push + Pocket-ID group)
- [priority] medium

## Scope (from roadmap)

Expose the Cilium Hubble UI via a Gateway API HTTPRoute (attached to `envoy-internal`) with an authentication layer in front. Originally two auth options were considered — Anubis (lightweight proof-of-work / SSO middleware) or HTTP basic-auth via an Envoy `SecurityPolicy`. Previously Hubble UI was only accessible via `kubectl port-forward`.

## Rationale (from roadmap)

Hubble flow log access during debugging is significantly faster with a persistent web UI than per-session port-forward. The data exposed (cluster pod-to-pod flow metadata) is sensitive enough to warrant auth — open-on-LAN is not acceptable since it would expose flow patterns to anyone on the network.

## Options considered (from roadmap)

1. Anubis — proof-of-work / lightweight SSO; consistent if we plan to add it for other apps later
2. HTTP basic-auth via Envoy `SecurityPolicy` — simpler, no new component
3. **tinyauth forward-auth** (chosen) — the cluster standard for OIDC-less apps; see Decisions below

## Decisions (decided with human, 2026-07-11)

- [decision] Auth method: tinyauth forward-auth (the cluster standard for OIDC-less apps), NOT the Anubis / HTTP basic-auth options the roadmap originally proposed. Consistency with bazarr/sonarr/... and the shared components/forward-auth SecurityPolicy + tinyauth ACL model.
- [decision] TinyAuth env-var app ID = `hubbleui` (a single token, no underscore/hyphen). Evidence: paerser's env decoder does `strings.ReplaceAll(k, "_", ".")` (github.com/tinyauthapp/paerser/env/env.go), so `TINYAUTH_APPS_hubble_ui_CONFIG_DOMAIN` would decode to `tinyauth.apps.hubble.ui.config.domain` where `ui` is not a field of the `App` struct (internal/model/config.go: App{Config,Users,OAuth,IP,Response,Path,LDAP}) — the ACL would not bind and the v5.0.7 nil-ACL allow-all behaviour would leak through. K8s env-var names also disallow hyphens. Matching is by CONFIG_DOMAIN (host), so the internal key name is irrelevant to the match.
- [decision] Pocket-ID group name = `hubble_users` (human choice), independent of the internal `hubbleui` app ID.
- [decision] No `dependsOn: tinyauth` on the cilium Flux Kustomization. cilium is the CNI root; tinyauth pods cannot schedule without the CNI, so the dependency would deadlock bootstrap. The SecurityPolicy `failOpen: false` fails closed until tinyauth is up — the secure default. (bazarr can safely use dependsOn:tinyauth because it is a leaf app; cilium cannot.)
- [decision] Full bazarr pattern (not forward-auth only): add `hubble.ui.podLabels.ingress.home.arpa/allow-gateway-internal: "true"` so the existing cluster-wide ingress-from-gateway-internal CCNP restricts hubble-ui ingress to envoy-internal pods only. Without it the forward-auth is bypassable via the in-cluster Service (hubble-ui previously had NO ingress CNP — Cilium default-allow).

## Changes (commit 35ccd7ec1 on main, not yet pushed)

- [file] kubernetes/apps/kube-system/cilium/ks.yaml — added `components: ../../../../components/forward-auth` + `postBuild.substitute.APP: hubble-ui` to the cilium Kustomization. SecurityPolicy `hubble-ui-forward-auth` targets the `hubble-ui` HTTPRoute.
- [file] kubernetes/apps/kube-system/cilium/app/helmrelease.yaml — `hubble.ui.podLabels.ingress.home.arpa/allow-gateway-internal: "true"` (cilium chart supports hubble.ui.podLabels, values.yaml line 670).
- [file] kubernetes/apps/security/tinyauth/app/helmrelease.yaml — per-app ACL `TINYAUTH_APPS_hubbleui_CONFIG_DOMAIN: "hubble.${PUBLIC_DOMAIN}"` + `TINYAUTH_APPS_hubbleui_OAUTH_GROUPS: hubble_users` (alphabetically between echo and maintainerr).
- [file] kubernetes/apps/security/tinyauth/app/referencegrant.yaml — added `kube-system` to the tinyauth-extauth ReferenceGrant from-list (between downloads and observability).
- pre-commit (yamlfmt, yamllint, gitleaks, k8s-secret scan) all Passed on the 4 files.

## Human prerequisite (HUMAN GATE — blocks end-to-end verify)

- [action] Create the `hubble_users` group in the Pocket-ID UI and add the users who should access Hubble UI.
- [observation] Until the group exists and the user is in it, hubble-ui is fail-closed (the per-app ACL is defined so the nil-ACL allow-all bug does NOT apply; the OAUTH_GROUPS check just denies everyone). This is the secure state.

## Verification

### Static (DONE)
- pre-commit all Passed on the 4 touched files.

### Live (PENDING — blocked on push + group)
- [ ] `git push origin main` — could not be run by the AI: the SSH agent refused the ED25519 key sign in this non-TTY context (TouchID/passphrase-protected key). User must push.
- [ ] `flux reconcile ks cilium -n kube-system` + `flux reconcile ks tinyauth -n security` (after push).
- [ ] `kubectl get securitypolicy hubble-ui-forward-auth -n kube-system` → Accepted.
- [ ] `kubectl get pods -n kube-system -l k8s-app=hubble-ui -o jsonpath='{.items[0].metadata.labels}'` → contains `ingress.home.arpa/allow-gateway-internal=true` (pod restart from podLabels).
- [ ] `curl -sI https://hubble.${PUBLIC_DOMAIN}` → tinyauth 302 redirect to auth.${PUBLIC_DOMAIN} (before group membership) / 200 Hubble UI (after).
- [ ] Bypass check: from a cluster pod, `curl hubble-ui.kube-system.svc.cluster.local:80` → Cilium drop (ingress default-deny, envoy-internal only). Hubble capture: `just k8s hubble-live-capture` then `just k8s hubble-analyze k8s:app.kubernetes.io/name=hubble-ui DROPPED ingress`.

## Tradeoffs / follow-ups

- [observation] Transient deploy window: both Kustomizations land in one commit/push. If the cilium SecurityPolicy is accepted before the tinyauth pod reloads the new `hubbleui` ACL (Reloader restart), there is a seconds-long "no matching app" state in tinyauth. Strict improvement over the previous fully-open state; negligible on a single-user home cluster.
- [follow-up] Confirm the iam area-reference ReferenceGrant coverage list (currently lists networking/selfhosted/media/observability — now also kube-system).
- [follow-up] Consider adding hubble-ui to the iam area-reference OIDC-less app registry once verified.

## Relations

- relates_to [[iam]]
- relates_to [[networking]]
- relates_to [[observability]]
- decided_in [[AD-023-cnp-threat-model-audit]]


## Session 1 — Live verify (2026-07-11, commit 35ccd7ec1 pushed as 6bfff4689)

### Deploy

- [observation] User pushed main (AI could not: SSH agent refused the ED25519 key sign in non-TTY context). flux reconcile ks cilium -n kube-system + tinyauth -n security → both applied revision refs/heads/main@sha1:6bfff4689.

### Verify (live, post-deploy) — ALL PASS

- [VERIFY pass] kubectl get securitypolicy hubble-ui-forward-auth -n kube-system → status.ancestors[envoy-internal/https].conditions[Accepted]=True, message "Policy has been accepted." (gateway.envoyproxy.io/gatewayclass-controller).
- [VERIFY pass] kubectl get httproute hubble-ui -n kube-system → Accepted=True, ResolvedRefs=True.
- [VERIFY pass] hubble-ui pod restarted (pod-template-hash 5d749c78b8 → 7f99d88955); live pod labels include ingress.home.arpa/allow-gateway-internal=true → selected by the cluster-wide ingress-from-gateway-internal CCNP (ingress now envoy-internal-only).
- [VERIFY pass] tinyauth pod restarted by the Helm upgrade (age 4m24s at check); deploy + live pod env contain TINYAUTH_APPS_hubbleui_CONFIG_DOMAIN=hubble.horvathzoltan.me and TINYAUTH_APPS_hubbleui_OAUTH_GROUPS=hubble_users.
- [VERIFY pass] End-to-end auth: `curl -sI https://hubble.horvathzoltan.me` from LAN → HTTP/2 401 with `x-tinyauth-location: https://auth.horvathzoltan.me/login?redirect_uri=...hubble.horvathzoltan.me...` and `x-envoy-upstream-service-time: 0` (request intercepted at envoy extAuth, never reached the hubble-ui backend). Hubble UI is no longer openly accessible.
- [VERIFY pass] Bypass protection: `wget http://hubble-ui.kube-system.svc.cluster.local:80` from the bazarr pod (downloads ns) → download timed out (Cilium drop — the CCNP denies non-envoy-internal ingress). The forward-auth cannot be bypassed via the in-cluster Service.

### Remaining (HUMAN GATE)

- [action] Create the `hubble_users` group in the Pocket-ID UI and add the user(s). Until then hubble-ui is fail-closed: curl → 401 → login redirect → after Pocket-ID login, tinyauth denies because the user is not in `hubble_users`. This is the intended secure state. Once the group exists and the user is in it, the same flow returns 200 (Hubble UI).
- [follow-up] After the group is created and 200 access confirmed, add hubble-ui to the iam area-reference OIDC-less app registry; update the iam ReferenceGrant coverage list to include kube-system.
