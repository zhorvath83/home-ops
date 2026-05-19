---
title: add-bjw-s-components
type: roadmap
permalink: home-ops/docs/roadmap/add-bjw-s-components
topic: Adopt additional bjw-s components — gatus, dragonfly
status: proposed
scope: 'Evaluate and adopt selected bjw-s reusable components beyond what is already
  in `kubernetes/components/` (volsync, flux-alerts). Candidates: **gatus** (lightweight
  uptime + status page, complements the kube-prometheus-stack observability) and **dragonfly**
  (Redis-compatible in-memory store, useful if any future workload needs a shared
  cache layer).'
priority: low
rationale: These are mature components in the bjw-s ecosystem; adoption is opt-in
  per workload. Status pages and Redis-compatible caches both have plausible future
  home-lab use cases but no immediate driver.
related_areas:
- k8s-workloads
- observability
---

# Adopt additional bjw-s components — gatus, dragonfly

## Metadata (observation-form, schema validation)
- [topic] Adopt additional bjw-s components — gatus, dragonfly
- [status] proposed
- [priority] low

## Scope
Evaluate and adopt selected bjw-s reusable components beyond what is already in `kubernetes/components/` (volsync, flux-alerts). Candidates: **gatus** (lightweight uptime + status page, complements the kube-prometheus-stack observability) and **dragonfly** (Redis-compatible in-memory store, useful if any future workload needs a shared cache layer).

## Rationale
These are mature components in the bjw-s ecosystem; adoption is opt-in per workload. Status pages and Redis-compatible caches both have plausible future home-lab use cases but no immediate driver.

## Related
- relates_to [[k8s-workloads]]
- relates_to [[observability]]
