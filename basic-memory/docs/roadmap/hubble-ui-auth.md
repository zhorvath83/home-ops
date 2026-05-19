---
title: hubble-ui-auth
type: roadmap
permalink: home-ops/docs/roadmap/hubble-ui-auth
topic: Hubble UI exposure via HTTPRoute with Anubis or basic-auth
status: proposed
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
- [status] proposed
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
