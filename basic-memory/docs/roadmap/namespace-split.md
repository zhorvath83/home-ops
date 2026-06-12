---
title: namespace-split
type: roadmap
permalink: home-ops/docs/roadmap/namespace-split
topic: Namespace split — default → media + selfhosted
status: done
scope: 'The monolithic `default` namespace has been split into `media` (11 apps:
  Arr Stack + Plex companions + Maintainerr) and `selfhosted` (13 apps: Paperless,
  Homepage, Mealie, etc.). `productivity` and `system` namespaces were not implemented;
  selfhosted absorbed both domains. Each namespace has its own `kubernetes/apps/<ns>/`
  subtree with ks.yaml, namespace.yaml, kustomization.yaml, and CLAUDE.md.'
priority: low
rationale: Improves repo navigation, supports per-namespace RBAC and ResourceQuota
  in the future, and aligns with bjw-s/onedr0p organizational pattern. Low priority
  because the current single-namespace flat layout works on a single-node home-lab.
related_areas:
- k8s-workloads
---

# Namespace split — default → media + selfhosted

## Metadata (observation-form, schema validation)

- [topic] Namespace split — default → media, productivity, system
- [status] proposed
- [priority] low

## Scope
The monolithic `default` namespace under `kubernetes/apps/default/` has been split into two namespaces along workload domains:

- **media** (11 apps): bazarr, isponsorblocktv, maintainerr, plex, plex-trakt-sync, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr
- **selfhosted** (13 apps): actual, backrest, calibre-web-automated, home-gallery, homepage, mealie, open-webui, paperless, paperless-gpt, pingvin-share-x, resticprofile, searxng, wallos

Each namespace has its own `kubernetes/apps/<ns>/` subtree with its own `ks.yaml` entry pattern, `namespace.yaml`, `kustomization.yaml`, and `CLAUDE.md`.

The original proposal also included `productivity` and `system` namespaces — these were not implemented. The selfhosted namespace absorbed what would have been the productivity group (paperless, mealie, homepage, etc.) and the infrastructure apps (backrest, resticprofile).
## Rationale
Improved repo navigation, per-namespace scoping for future RBAC/ResourceQuota, and alignment with bjw-s/onedr0p organizational pattern.

## Outcome

- `kubernetes/apps/default/` directory removed entirely
- `kubernetes/apps/media/` and `kubernetes/apps/selfhosted/` created with proper namespace resources
- Homepage group layout unchanged (Arr Stack, Media, Downloading, Selfhosted, PFM, Infrastructure, etc.) — only the K8s namespace changed
- All VolSync, ExternalSecret, and CiliumNetworkPolicy references updated to new namespaces
- cert-manager remains in its own namespace (unchanged)
## Related

- relates_to [[k8s-workloads]]
