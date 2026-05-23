---
title: AD-019-tuppr-system-upgrade
type: decision
permalink: home-ops/docs/decisions/ad-019-tuppr-system-upgrade
decision_id: AD-019
topic: System upgrade via Tuppr (bjw-s pattern)
status: active
decided_at: '2025-10-01'
decision: Replace the current `system-upgrade-controller` with bjw-s `tuppr`.
rationale: Tuppr is Talos-native — it manages node upgrades via Talos `MachineConfigPatch`
  and the Talos API `system-upgrade-controller` is SUSE-flavored (built primarily
  for K3s); Talos integration is possible but Tuppr is the better fit
tradeoffs: Existing SUC `Plan` resources do not migrate 1:1 — new Tuppr `Plan` resources
  have to be written
related_areas:
- talos-cluster
---

# AD-019 — System upgrade via Tuppr (bjw-s pattern)

## Metadata (observation-form, schema validation)

- [decision_id] AD-019
- [status] active
- [decided_at] 2025-10-01
- [topic] System upgrade via Tuppr (bjw-s pattern)

## Decision

Replace the current `system-upgrade-controller` with bjw-s `tuppr`.

## Rationale

- Tuppr is Talos-native — it manages node upgrades via Talos `MachineConfigPatch` and the Talos API
- `system-upgrade-controller` is SUSE-flavored (built primarily for K3s); Talos integration is possible but Tuppr is the better fit

## Tradeoffs

- Existing SUC `Plan` resources do not migrate 1:1 — new Tuppr `Plan` resources have to be written

## Related

- relates_to [[talos-cluster]]
