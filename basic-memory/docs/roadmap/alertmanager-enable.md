---
title: alertmanager-enable
type: roadmap
permalink: home-ops/docs/roadmap/alertmanager-enable
topic: AlertManager enable + Flux alerts routing through AlertManager (N1)
status: proposed
scope: Decide whether to enable AlertManager in the kube-prometheus-stack HelmRelease
  and route Flux alerts through AlertManager-managed Pushover/PagerDuty routing instead
  of the current direct Flux Provider → Pushover path. The decision affects the observability-content-extract
  scope (AlertmanagerConfig CRs become relevant) and the flux-alerts component design.
priority: low
rationale: Current path (Flux Provider → Pushover, no AlertManager) is simpler and
  works. AlertManager would add deduplication, grouping, silencing, and routing rules
  — useful for richer alert workflows but introduces a new component to maintain.
  Decision is deferred until alert volume or routing complexity justifies it.
related_areas:
- observability
- flux-gitops
---

# AlertManager enable + Flux alerts routing through AlertManager (N1)

## Metadata (observation-form, schema validation)

- [topic] AlertManager enable + Flux alerts routing through AlertManager (N1)
- [status] proposed
- [priority] low

## Scope

Decide whether to enable AlertManager in the kube-prometheus-stack HelmRelease and route Flux alerts through AlertManager-managed Pushover/PagerDuty routing instead of the current direct Flux Provider → Pushover path. The decision affects the observability-content-extract scope (AlertmanagerConfig CRs become relevant) and the flux-alerts component design.

## Rationale

Current path (Flux Provider → Pushover, no AlertManager) is simpler and works. AlertManager would add deduplication, grouping, silencing, and routing rules — useful for richer alert workflows but introduces a new component to maintain. Decision is deferred until alert volume or routing complexity justifies it.

## Related

- relates_to [[observability]]
- relates_to [[flux-gitops]]
