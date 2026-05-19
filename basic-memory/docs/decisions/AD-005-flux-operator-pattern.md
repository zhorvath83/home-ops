---
title: AD-005-flux-operator-pattern
type: decision
permalink: home-ops/docs/decisions/ad-005-flux-operator-pattern
decision_id: AD-005
topic: Flux Operator + FluxInstance instead of classic flux bootstrap
status: active
decided_at: '2025-10-01'
decision: Replace the `flux bootstrap` step with the Flux Operator (controlplane.io);
  the cluster state is driven by a FluxInstance CR.
rationale: All three reference repositories use this pattern Flux itself becomes declarative
  — controllers are updated via the FluxInstance YAML Cluster-level default patches
  (CRD createReplace, retry, timeout) live in one place Natural step in a helmfile
  bootstrap (flux-operator + flux-instance releases)
tradeoffs: Differs from the classic flux install workflow — small learning curve Flux
  Operator itself becomes a maintained Helm release
related_areas:
- flux-gitops
---

# AD-005 — Flux Operator + FluxInstance instead of classic flux bootstrap

## Metadata (observation-form, schema validation)
- [decision_id] AD-005
- [status] active
- [decided_at] 2025-10-01
- [topic] Flux Operator + FluxInstance instead of classic flux bootstrap

## Decision
Replace the `flux bootstrap` step with the Flux Operator (controlplane.io); the cluster state is driven by a FluxInstance CR.

## Rationale
- All three reference repositories use this pattern
- Flux itself becomes declarative — controllers are updated via the FluxInstance YAML
- Cluster-level default patches (CRD createReplace, retry, timeout) live in one place
- Natural step in a helmfile bootstrap (flux-operator + flux-instance releases)

## Tradeoffs
- Differs from the classic flux install workflow — small learning curve
- Flux Operator itself becomes a maintained Helm release

## Related
- relates_to [[flux-gitops]]
