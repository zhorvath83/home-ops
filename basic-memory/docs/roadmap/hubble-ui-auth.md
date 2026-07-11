---
title: hubble-ui-auth
type: roadmap
permalink: home-ops/docs/roadmap/hubble-ui-auth
topic: Hubble UI exposure via HTTPRoute with Anubis or basic-auth
status: implemented
scope: 'Expose the Cilium Hubble UI via a Gateway API HTTPRoute (attached to `envoy-internal`)
  with an authentication layer in front. Two auth options: Anubis (lightweight proof-of-work
  / SSO middleware) or HTTP basic-auth via an Envoy `SecurityPolicy`. Currently Hubble
  UI is only accessible via `kubectl port-forward`.'
priority: medium
rationale: Hubble flow log access during debugging is significantly faster with a
  persistent web UI than per-session port-forward. The data exposed (cluster pod-to-pod
  flow metadata) is sensitive enough to warrant auth — open-on-LAN is not acceptable
  since it would expose flow patterns to anyone on the network.
options:
- Anubis — proof-of-work / lightweight SSO; consistent if we plan to add it for other
  apps later
- HTTP basic-auth via Envoy `SecurityPolicy` — simpler, no new component
related_areas:
- networking
- observability
---

# Hubble UI exposure via HTTPRoute with Anubis or basic-auth

## Metadata (observation-form, schema validation)

- [topic] Hubble UI exposure via HTTPRoute with Anubis or basic-auth
- [status] implemented (code committed; live verify pending push + Pocket-ID group)
- [priority] medium

## Scope

Expose the Cilium Hubble UI via a Gateway API HTTPRoute (attached to `envoy-internal`) with an authentication layer in front. Two auth options: Anubis (lightweight proof-of-work / SSO middleware) or HTTP basic-auth via an Envoy `SecurityPolicy`. Currently Hubble UI is only accessible via `kubectl port-forward`.

## Rationale

Hubble flow log access during debugging is significantly faster with a persistent web UI than per-session port-forward. The data exposed (cluster pod-to-pod flow metadata) is sensitive enough to warrant auth — open-on-LAN is not acceptable since it would expose flow patterns to anyone on the network.

## Options

1. Anubis — proof-of-work / lightweight SSO; consistent if we plan to add it for other apps later
2. HTTP basic-auth via Envoy `SecurityPolicy` — simpler, no new component

## Related

- relates_to [[networking]]
- relates_to [[observability]]


## Implementation (2026-07-11, commit 35ccd7ec1)

- [decision] Adopted tinyauth forward-auth (Path B) instead of the Anubis / HTTP basic-auth options listed above — the cluster standard for OIDC-less apps, consistent with bazarr/sonarr/etc.
- [observation] Wiring: components/forward-auth SecurityPolicy on the hubble-ui HTTPRoute (cilium/ks.yaml APP=hubble-ui) + tinyauth per-app ACL TINYAUTH_APPS_hubbleui_* (group hubble_users) + kube-system added to the tinyauth-extauth ReferenceGrant + hubble.ui.podLabels ingress.home.arpa/allow-gateway-internal so the cluster-wide ingress-from-gateway-internal CCNP blocks in-cluster bypass.
- [observation] TinyAuth app ID is the single token `hubbleui` (paerser env decoder replaces _ with ., so an underscored ID would not bind the ACL → nil-ACL allow-all on v5.0.7). No dependsOn:tinyauth on cilium (CNI root → bootstrap deadlock). See [[hubble-ui-auth]] (docs/progress) for full detail.
- [action] HUMAN GATE: create the `hubble_users` group in Pocket-ID and add users; until then hubble-ui is fail-closed.

## Relations

- implemented_by [[hubble-ui-auth]] (docs/progress)
- relates_to [[iam]]
- decided_in [[AD-023-cnp-threat-model-audit]]
