---
title: AD-013-single-node-no-vip
type: decision
permalink: home-ops/docs/decisions/ad-013-single-node-no-vip
decision_id: AD-013
topic: Single-node, no VIP for the control plane
status: active
decided_at: '2025-10-01'
decision: The Talos `controlPlane.endpoint` points directly at the node IP (`https://192.168.1.11:6443`).
  No VIP.
rationale: 'Single control plane → VIP overhead with no benefit Talos built-in VIP
  (Equinix-style) only delivers value at 2+ nodes Future-proofing is not a reason:
  adding a worker node keeps the control plane single. Scaling to 3 control-plane
  nodes can re-introduce a VIP via a `machineconfig` patch later'
tradeoffs: If the node IP changes (network reorganization), kubeconfig + Talos config
  need updating. Static IP on the router mitigates this
related_areas:
- talos-cluster
---

# AD-013 — Single-node, no VIP for the control plane

## Metadata (observation-form, schema validation)
- [decision_id] AD-013
- [status] active
- [decided_at] 2025-10-01
- [topic] Single-node, no VIP for the control plane

## Decision
The Talos `controlPlane.endpoint` points directly at the node IP (`https://192.168.1.11:6443`). No VIP.

## Rationale
- Single control plane → VIP overhead with no benefit
- Talos built-in VIP (Equinix-style) only delivers value at 2+ nodes
- Future-proofing is not a reason: adding a worker node keeps the control plane single. Scaling to 3 control-plane nodes can re-introduce a VIP via a `machineconfig` patch later

## Tradeoffs
- If the node IP changes (network reorganization), kubeconfig + Talos config need updating. Static IP on the router mitigates this

## Related
- relates_to [[talos-cluster]]
