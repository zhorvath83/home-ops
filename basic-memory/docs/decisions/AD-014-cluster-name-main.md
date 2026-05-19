---
title: AD-014-cluster-name-main
type: decision
permalink: home-ops/docs/decisions/ad-014-cluster-name-main
decision_id: AD-014
topic: Cluster name is `main`
status: active
decided_at: '2025-10-01'
decision: The new cluster is named `main`, matching most of the reference repositories.
rationale: bjw-s and onedr0p both use `main` as the cluster name `home-ops` is the
  repo name, not part of the cluster name Compatible with a future multi-cluster naming
  convention (dev/staging)
tradeoffs: None
related_areas:
- talos-cluster
---

# AD-014 — Cluster name is `main`

## Metadata (observation-form, schema validation)
- [decision_id] AD-014
- [status] active
- [decided_at] 2025-10-01
- [topic] Cluster name is `main`

## Decision
The new cluster is named `main`, matching most of the reference repositories.

## Rationale
- bjw-s and onedr0p both use `main` as the cluster name
- `home-ops` is the repo name, not part of the cluster name
- Compatible with a future multi-cluster naming convention (dev/staging)

## Tradeoffs
- None

## Related
- relates_to [[talos-cluster]]
