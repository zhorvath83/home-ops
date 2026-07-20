---
title: namespace-reorg-downloads
type: progress
permalink: home-ops/docs/progress/namespace-reorg-downloads
topic: Namespace reorganization — calibre-web-automated → media, 8 apps → downloads
status: done
branch: namespace-reorg-downloads
created_at: '2026-06-16'
updated_at: '2026-06-17'
tags:
- progress
- namespace-reorg
- migration
---

# namespace-reorg-downloads — progress

> Branch: `namespace-reorg-downloads`
> Issue: namespace reorganization (calibre-web-automated selfhosted→media, 8 apps media→downloads)
> Status: done — migration completed, PR merged, BM docs updated

## Scope

Three-namespace target state for user-facing workloads:

- `media` (4 apps, consumption): calibre-web-automated, isponsorblocktv, plex, plex-trakt-sync
- `downloads` (8 apps, content acquisition): bazarr, maintainerr, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr
- `selfhosted` (12 apps, everything else): paperless, paperless-gpt, mealie, home-gallery, actual, wallos, backrest, homepage, resticprofile, open-webui, searxng, pingvin-share-x

Continues [[namespace-split]] (now at `docs/progress/namespace-split`).

## Session Summary — 2026-06-16/17

### Phase 0 — Pre-creation (per app with PVC)

For each of 8 apps with PVCs (calibre-web-automated, bazarr, maintainerr, prowlarr, qbittorrent, radarr, seerr, sonarr):

- Triggered safety Kopia snapshot on old PVC via `just volsync snapshot <app> <old-ns>`
- Scaled old workload to 0 (freed PVC finalizer, stopped writes)
- Pre-created `<app>-volsync` ExternalSecret in new namespace (matches `kubernetes/components/volsync/externalsecret.yaml` template, pulls from 1P `volsync-template` + `ovh`)
- Pre-created `<app>-bootstrap` ReplicationDestination in new namespace with `spec.kopia.sourceIdentity.sourceNamespace: <old-ns>` (cross-namespace restore — verified the field exists in the VolSync CRD)
- `metadata.labels.kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` on the bootstrap RD — Flux applies once and never overwrites
- Waited for `status.latestMoverStatus.result == Successful` — restores latest `<app>@<old-ns>:/data` snapshot into a temp PVC and creates a VolumeSnapshot

`subsyncarr` skipped (emptyDir + NFS, no PVC, pure GitOps move).

### Phase 1 — Single GitOps commit (369b5623d)

All changes in one commit `♻️ refactor(apps): reorganize namespaces — calibre-web-automated→media, arr-stack→downloads`:

- New: `kubernetes/apps/downloads/namespace.yaml` (Namespace, name: _, prune: disabled)
- New: `kubernetes/apps/downloads/kustomization.yaml` (namespace: downloads, components: ../../components/common, resources: namespace.yaml + 8 ks.yamls)
- New: `kubernetes/apps/downloads/CLAUDE.md` (symlink to ../selfhosted/CLAUDE.md)
- Moved (git mv): `kubernetes/apps/selfhosted/calibre-web-automated` → `kubernetes/apps/media/calibre-web-automated`
- Moved (git mv): `kubernetes/apps/media/{bazarr,maintainerr,prowlarr,qbittorrent,radarr,seerr,sonarr,subsyncarr}` → `kubernetes/apps/downloads/`
- Updated each app ks.yaml: `spec.path` → new location, `spec.targetNamespace` → new namespace. Preserved `APP_UID`/`APP_GID` (calibre-web-automated: 1000/100, seerr: 1000/1000) and volsync component attachment (except subsyncarr).
- Updated `kubernetes/apps/kustomization.yaml`: added `- ./downloads`
- Updated `kubernetes/apps/media/kustomization.yaml`: removed 8 app entries, added `- ./calibre-web-automated/ks.yaml`
- Updated `kubernetes/apps/selfhosted/kustomization.yaml`: removed `- ./calibre-web-automated/ks.yaml`
- Updated the security-namespace ReferenceGrant: added `downloads` to the `from` list (SecurityPolicy cross-namespace reference authorization)

### Phase 2 — Flux reconcile + end-to-end verification

- `flux reconcile kustomization -n flux-system cluster-apps --with-source`
- Per-app verification: HelmRelease Ready=True, Pod Running, PVC Bound, HTTPRoute responding
- VolSync: new ReplicationSources in new namespaces, old-ns RSes pruned
- Old PVCs deleted (finalizer `kubernetes.io/pvc-protection` removed after pod scaled to 0)
- Homepage dashboard: all app tiles present (Arr Stack group, Media group, Downloading group)

### Phase 2b — Orphaned resource cleanup

Flux prune did NOT cascade-delete all owned resources because the HelmRelease controller was suspended (suspend: true) — the `finalizers.fluxcd.io` finalizer ran but the helm uninstall step was skipped, leaving Helm release Secrets in "deployed" state. Manual cleanup:

- `helm uninstall` per app in old namespaces (bypassed the HelmRelease finalizer, removed Deployment/Service/HTTPRoute/ConfigMap/Secret)
- `kubectl delete replicationsource/externalsecret/pvc` per app in old namespaces
- `kubectl -n media delete securitypolicy` for the orphaned maintainerr SecurityPolicy (not owned by Helm)

### Phase 2c — Maintainerr 500 fix (security-namespace ReferenceGrant)

Symptom: `maintainerr.horvathzoltan.me` returned 500. Diagnosis: the maintainerr SecurityPolicy status showed its ext-auth backend ref not permitted by any ReferenceGrant.

Root cause: the cluster-live security-namespace ReferenceGrant did NOT include the `downloads` namespace, even though the git HEAD did. The security-namespace Flux Kustomization `interval: 1h` had not yet reconciled the new commit.

Fix: reconciled the security-namespace Flux Kustomization `--with-source`. GitRepository fetched revision matched the HEAD; the ReferenceGrant live state was updated to include `downloads`; the SecurityPolicy status became `Accepted=True`; the maintainerr route returned 401 (auth gate active).

### Phase 3 — BM docs update (this session)

- Rewrote `docs/roadmap/namespace-split` to reflect the new three-namespace target state (status: done, scope: media=4/downloads=8/selfhosted=12)
- Moved `docs/roadmap/namespace-split` → `docs/progress/namespace-split` (per the project convention "Fully implemented roadmap items → progress/", following the `pingvin-share-x-selfhosted-roadmap` pattern). Added "Originally at" note. Deleted the old `docs/roadmap/namespace-split`.
- Updated `docs/areas/k8s-workloads` to fix drift: the previous note claimed calibre-web-automated was in selfhosted (it is now in media); the 8 arr-stack apps were listed as media (they are now in downloads). Reflected the post-migration three-namespace target state. `verified_at: 2026-06-17`. Added a new drift_risk entry about the security-namespace ReferenceGrant manual-extension requirement.
- Created this progress note (`progress/namespace-reorg-downloads`).

## Outcome

- All 9 apps Running in new namespaces with restored PVC data
- VolSync backups running in new namespaces (new ReplicationSources under `<app>@<new-ns>:/data`)
- Old namespaces drained: media has 4 apps (calibre-web-automated, isponsorblocktv, plex, plex-trakt-sync), selfhosted has 12 apps (calibre-web-automated removed)
- All HTTPRoutes responding (200/302/401 — auth gate active on maintainerr)
- Homepage dashboard: all tiles present
- No failed HelmReleases

## Next: Session-end commit-doc-commit

Per `gitlab-workflow` rule commit-doc-commit pattern:

1. **Code commit** (already done): `369b5623d ♻️ refactor(apps): reorganize namespaces — calibre-web-automated→media, arr-stack→downloads` (the namespace-reorg refactor commit, already pushed and PR merged)
2. **Update progress/[branch] note** (this note — done via BM MCP)
3. **Docs commit**: `git add basic-memory/` + `git commit -m "📝 docs(progress): update namespace-reorg-downloads session"` (covers the namespace-split move, k8s-workloads update, and this progress note)
4. **Push** the docs commit

## Related

- continues [[namespace-split]] (now at `docs/progress/namespace-split`)
- relates_to [[k8s-workloads]] (area-reference updated to reflect the three-namespace target state)
- implements the security-namespace ReferenceGrant extension
