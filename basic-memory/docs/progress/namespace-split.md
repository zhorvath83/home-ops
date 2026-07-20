---
title: namespace-split
type: roadmap
permalink: home-ops/docs/progress/namespace-split
topic: Namespace split — default → media + selfhosted → media + downloads + selfhosted
status: done
scope: 'The monolithic `default` namespace was first split into `media` and `selfhosted`.
  Following the second wave, the layout is now three namespaces: `media` (4 apps:
  consumption), `downloads` (8 apps: arr-stack + qbittorrent), and `selfhosted` (12
  apps: everything else). `calibre-web-automated` moved from `selfhosted` to `media`.
  8 apps (bazarr, maintainerr, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr)
  moved from `media` to a new `downloads` namespace. Each namespace has its own `kubernetes/apps/<ns>/`
  subtree with ks.yaml, namespace.yaml, kustomization.yaml, and CLAUDE.md.'
priority: low
rationale: Improves repo navigation, supports per-namespace RBAC and ResourceQuota
  in the future, aligns with bjw-s/onedr0p organizational pattern, and separates media
  consumption from content acquisition (arr-stack).
related_areas:
- k8s-workloads
---

> Originally at `docs/roadmap/namespace-split`. Moved to `docs/progress/` upon completion per the project's "Fully implemented roadmap items → progress/" convention.

# Namespace split — default → media + selfhosted → media + downloads + selfhosted

## Metadata (observation-form, schema validation)

- [topic] Namespace split — default → media + selfhosted → media + downloads + selfhosted
- [status] done
- [priority] low

## Scope

The monolithic `default` namespace was first split into two namespaces, then a second wave refined it into three. The current target state:

- **media** (4 apps, consumption): `calibre-web-automated`, `isponsorblocktv`, `plex`, `plex-trakt-sync`
- **downloads** (8 apps, content acquisition): `bazarr`, `maintainerr`, `prowlarr`, `qbittorrent`, `radarr`, `seerr`, `sonarr`, `subsyncarr`
- **selfhosted** (12 apps, everything else): `actual`, `backrest`, `home-gallery`, `homepage`, `mealie`, `open-webui`, `paperless`, `paperless-gpt`, `pingvin-share-x`, `resticprofile`, `searxng`, `wallos`

Each namespace has its own `kubernetes/apps/<ns>/` subtree with its own `ks.yaml` entry pattern, `namespace.yaml`, `kustomization.yaml`, and `CLAUDE.md` (the `downloads` and `media` CLAUDE.md files are symlinks to `selfhosted/CLAUDE.md`, since the durable guardrails are shared across user-facing app namespaces).

### Second-wave migration details

- `calibre-web-automated` moved `selfhosted → media` (PVC data migrated via VolSync cross-namespace restore using `sourceIdentity.sourceNamespace`).
- 8 apps (`bazarr`, `maintainerr`, `prowlarr`, `qbittorrent`, `radarr`, `seerr`, `sonarr`, `subsyncarr`) moved `media → downloads` (PVC data migrated via VolSync cross-namespace restore for the 7 with PVCs; `subsyncarr` has no PVC, pure GitOps move).
- A security-namespace ReferenceGrant was extended to permit cross-namespace SecurityPolicy resources from the new `downloads` namespace.
- Pre-creation pattern: 8 ExternalSecrets + 8 bootstrap ReplicationDestinations were applied to the new namespaces with `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` so Flux adopts them and does not overwrite. Each bootstrap RD used `spec.kopia.sourceIdentity.sourceNamespace: <old-ns>` to restore from the old namespace's Kopia snapshots.
- Orphaned-resource cleanup: the Kustomization finalizer did not run on suspended Flux Kustomizations, leaving HelmReleases, Helm release Secrets, Deployments, HTTPRoutes, ReplicationSources, ExternalSecrets, and PVCs stranded in the old namespaces. Manual cleanup required `helm uninstall` (HelmRelease finalizer was bypassed by suspend), `kubectl delete replicationsource`, `kubectl delete externalsecret`, `kubectl delete pvc`, and `kubectl delete securitypolicy` for the orphaned maintainerr SecurityPolicy in `media`.

## Rationale

Improved repo navigation, per-namespace scoping for future RBAC/ResourceQuota, alignment with bjw-s/onedr0p organizational pattern, and clearer separation of media consumption from content acquisition workloads.

## Outcome

- `kubernetes/apps/default/` directory removed entirely (first wave)
- `kubernetes/apps/media/`, `kubernetes/apps/selfhosted/`, and `kubernetes/apps/downloads/` exist with proper namespace resources
- Homepage group layout unchanged (Arr Stack, Media, Downloading, Selfhosted, PFM, Infrastructure, etc.) — only the K8s namespace changed; Homepage is namespace-agnostic via HTTPRoute annotations
- All VolSync, ExternalSecret, and CiliumNetworkPolicy references updated to new namespaces
- The security-namespace ReferenceGrant permitted SecurityPolicy from `media`, `selfhosted`, `downloads`, `observability`, `networking` namespaces
- cert-manager remains in its own namespace (unchanged)

## Related

- relates_to [[k8s-workloads]]
