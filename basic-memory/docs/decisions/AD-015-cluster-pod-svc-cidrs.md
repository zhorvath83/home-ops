---
title: AD-015-cluster-pod-svc-cidrs
type: decision
permalink: home-ops/docs/decisions/ad-015-cluster-pod-svc-cidrs
decision_id: AD-015
topic: Pod CIDR `10.244.0.0/16`, service CIDR `10.245.0.0/16`
status: active
decided_at: '2025-10-01'
decision: Pod CIDR is `10.244.0.0/16`, service CIDR is `10.245.0.0/16`. Both differ
  from the current cluster (`10.42`/`10.43`).
rationale: The new cluster IP plan must not collide with the old one during the cutover
  window when both are visible on the router bjw-s and buroa both use `10.244.0.0/16`
  for pod CIDR — community consensus `10.245` for services makes the `pod=244, svc=245`
  mnemonic
tradeoffs: The `cluster-settings.yaml` variables `CLUSTER_POD_CIDR` and `CLUSTER_SVC_CIDR`
  need updating — small chore
related_areas:
- networking
- talos-cluster
---

# AD-015 — Pod CIDR `10.244.0.0/16`, service CIDR `10.245.0.0/16`

## Metadata (observation-form, schema validation)
- [decision_id] AD-015
- [status] active
- [decided_at] 2025-10-01
- [topic] Pod CIDR `10.244.0.0/16`, service CIDR `10.245.0.0/16`

## Decision
Pod CIDR is `${d}{POD_CIDR}`, service CIDR is `${d}{SVC_CIDR}`. Both differ from the current cluster (`10.42`/`10.43`). These values are now defined in the `cluster-settings` ConfigMap.

## Rationale
- The new cluster IP plan must not collide with the old one during the cutover window when both are visible on the router
- bjw-s and buroa both use `10.244.0.0/16` for pod CIDR — community consensus
- `10.245` for services makes the `pod=244, svc=245` mnemonic

## Tradeoffs
- The `cluster-settings.yaml` variables `POD_CIDR` and `SVC_CIDR` are now defined and used via Flux substitution

## Related
- relates_to [[networking]]
- relates_to [[talos-cluster]]
