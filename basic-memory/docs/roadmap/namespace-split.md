---
title: namespace-split
type: roadmap
permalink: home-ops/docs/roadmap/namespace-split
topic: Namespace split — default → media, productivity, system
status: proposed
scope: 'Split the monolithic `default` namespace under `kubernetes/apps/default/`
  into multiple bjw-s-style namespaces along workload domains: `media` (Plex, Sonarr/Radarr,
  qBittorrent, etc.), `productivity` (Paperless, Mealie, Homepage, etc.), `system`
  (utility/internal). Each new namespace gets its own `kubernetes/apps/<ns>/` subtree
  with its own `ks.yaml` entry pattern.'
priority: low
rationale: Improves repo navigation, supports per-namespace RBAC and ResourceQuota
  in the future, and aligns with bjw-s/onedr0p organizational pattern. Low priority
  because the current single-namespace flat layout works on a single-node home-lab.
related_areas:
- k8s-workloads
---

# Namespace split — default → media, productivity, system

## Metadata (observation-form, schema validation)

- [topic] Namespace split — default → media, productivity, system
- [status] proposed
- [priority] low

## Scope

Split the monolithic `default` namespace under `kubernetes/apps/default/` into multiple bjw-s-style namespaces along workload domains: `media` (Plex, Sonarr/Radarr, qBittorrent, etc.), `productivity` (Paperless, Mealie, Homepage, etc.), `system` (utility/internal). Each new namespace gets its own `kubernetes/apps/<ns>/` subtree with its own `ks.yaml` entry pattern.

## Rationale

Improves repo navigation, supports per-namespace RBAC and ResourceQuota in the future, and aligns with bjw-s/onedr0p organizational pattern. Low priority because the current single-namespace flat layout works on a single-node home-lab.

## Related

- relates_to [[k8s-workloads]]
