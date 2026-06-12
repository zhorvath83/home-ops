---
title: k8s-workloads
type: area_reference
permalink: home-ops/docs/areas/k8s-workloads
area: k8s-workloads
status: current
confidence: high
verified_at: '2026-05-22'
summary: Non-platform Flux-managed application workloads live under kubernetes/apps/<group>/<app>/
  with a canonical ks.yaml + app/ shape. The repo hosts 11 apps in the media namespace
  (Arr Stack + Plex companions + Maintainerr) and 13 apps in the selfhosted namespace
  (Selfhosted, PFM, Downloading, Infrastructure groups) plus cert-manager.
  Apps follow a strict minimal-spec policy for HelmRelease, a hardened security baseline,
  the shared VolSync component for PVC backups (17 of 24 apps wire it across media and selfhosted namespaces), and
  the Gateway API split between envoy-external and envoy-internal. Per-app secret
  delivery is always the onepassword-connect ClusterSecretStore with 12h refresh.
verified_against:
- kubernetes/CLAUDE.md
- kubernetes/apps/media/CLAUDE.md
- kubernetes/apps/selfhosted/CLAUDE.md
- kubernetes/apps/selfhosted/paperless/ks.yaml
- kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml
- kubernetes/apps/selfhosted/backrest/ks.yaml
- kubernetes/apps/selfhosted/backrest/app/helmrelease.yaml
- kubernetes/apps/selfhosted/resticprofile/app/helmrelease.yaml
- kubernetes/components/volsync/
- kubernetes/flux/cluster/ks.yaml
- .claude/skills/k8s-workloads/SKILL.md
- .claude/skills/k8s-workloads/references/app-scaffolding.md
- .claude/skills/k8s-workloads/references/runtime-baselines.md
- .claude/skills/k8s-workloads/references/publication-and-jobs.md
drift_risk: HelmRelease minimal-spec is enforced only by code review, not by an automated
  check — every app HR can re-introduce per-HR install/upgrade/rollback overrides
  that conflict with the cluster-root kustomize patch. Apps now span two namespaces
  (media and selfhosted); CNI policies are evolving from coarse cluster-wide baseline toward
  per-app CNPs per AD-023. NFS server (${NAS_IP} from cluster-settings) is a single point of failure for /backups and media mounts
  across many apps; no automated fallback. Storage strategy is decided per app (PVC
  vs NFS vs emptyDir) but the contract is documented only in CLAUDE.md.
tags:
- area-reference
- k8s-workloads
- applications
---

# k8s-workloads — current state

## Metadata (observation-form, schema validation)

- [area] k8s-workloads
- [status] current
- [confidence] high
- [verified_at] 2026-05-19

## Summary

This area covers non-platform application workloads under `kubernetes/apps/` — anything that is **not** the networking, external-secrets, flux-system, volsync-system, talos, or observability subtree. Apps are organized into two namespace groups: `kubernetes/apps/media/` (11 apps — Arr Stack, Plex companions, Maintainerr) and `kubernetes/apps/selfhosted/` (13 apps — Paperless, Homepage, Mealie, PFM, Downloading, Infrastructure groups). The only other non-platform subtree is `kubernetes/apps/cert-manager/`.

Apps follow a canonical shape per the k8s-workloads skill: each app lives in `kubernetes/apps/<group>/<app>/` with a `ks.yaml` Flux entry point and an `app/` directory holding `kustomization.yaml`, `ocirepository.yaml`, `helmrelease.yaml`, optional `externalsecret.yaml`, and optional `ciliumnetworkpolicy.yaml` or `config/` static files. App manifests carry **no** `metadata.namespace` and **no** redundant `labels:` blocks — the Flux Kustomization `spec.targetNamespace` + `spec.commonMetadata.labels` are the single source of placement and labeling. HelmRelease `spec` is intentionally minimal (`chartRef`, `interval`, `values`, very rarely `postRenderers`) — the cluster-root `kubernetes/flux/cluster/ks.yaml` injects install/upgrade/rollback defaults into every HelmRelease through a kustomize patch.

Three cross-cutting patterns thread through every app:

- **Secrets**: `spec.refreshInterval: 12h`, `secretStoreRef.kind=ClusterSecretStore`, `secretStoreRef.name=onepassword-connect`, `target.creationPolicy=Owner`, no `metadata.namespace`. Reloader auto-restarts consumer pods on Secret rewrite.
- **Backups**: PVC-bearing apps that should be backed up attach the `kubernetes/components/volsync/` Kustomize component in their `ks.yaml` and supply `APP`/`APP_UID`/`APP_GID` (and optionally `VOLSYNC_*` overrides) via `postBuild.substitute`. Critical apps may **additionally** write a curated export into the shared NFS `/backups/<app>` tree so the resticprofile plane captures a second copy in OVH Object Storage. Paperless is the canonical dual-coverage example.
- **Exposure**: HTTPRoute attached to `envoy-external` in namespace `networking` for public Cloudflare-Tunnel traffic, and to `envoy-internal` when the app should also be reachable directly from the LAN (split DNS via k8s-gateway).

Homepage dashboard metadata uses a stable set of groups defined in `kubernetes/apps/selfhosted/homepage/app/config/settings.yaml` layout (tabs: Cloud Services, Finances, Multimedia, Home infra) with groups: Selfhosted, eMail, Cloud Storage, PFM, Bank, Investment, Funds, Media, Arr Stack, Downloading, Infrastructure, SaaS & PaaS, IoT, Observability. Annotations are placed on HTTPRoute `metadata.annotations`. Dashboard icons are resolved against the `homarr-labs/dashboard-icons` CDN; icons from other repos (e.g. `selfhst/icons`) need the full URL form.

## Components

### App inventory

**media namespace (kubernetes/apps/media/, 11 apps):**

- [component] Arr Stack — `bazarr`, `prowlarr`, `radarr`, `seerr`, `sonarr`, `subsyncarr` (namespace: media, Homepage group: `Arr Stack`)
- [component] Media — `calibre-web-automated`, `maintainerr` (namespace: media, Homepage group: `Media`); `plex`, `plex-trakt-sync`, `isponsorblocktv` (namespace: media, Plex companions)
- [component] Downloading — `qbittorrent` (namespace: media, Homepage group: `Downloading`; qbittorrent-p2pblocklist merged into qbittorrent as initContainer)

**selfhosted namespace (kubernetes/apps/selfhosted/, 13 apps):**
- [component] Selfhosted — `paperless`, `paperless-gpt`, `mealie`, `home-gallery` (Homepage group: `Selfhosted`)
- [component] PFM (personal finance) — `actual`, `wallos` (Homepage group: `PFM`)
- [component] Infrastructure — `backrest`, `homepage`, `resticprofile` (Homepage group: `Infrastructure` for those with a UI)
- [component] AI/search — `open-webui`, `searxng` (Homepage group: `Selfhosted`)
- [component] Sharing — `pingvin-share-x` (route on envoy-external + envoy-internal)
- [component] cert-manager — only non-media/selfhosted non-platform subtree under `kubernetes/apps/cert-manager/`

### Cross-cutting patterns

- [component] Shared GPU component — `kubernetes/components/gpu/` provides a ResourceClaimTemplate (${"${APP}"}-gpu, deviceClassName: gpu.intel.com, allocationMode: All) for any app needing iGPU access via DRA/CDI; no adminAccess, no namespace label needed (onedr0p pattern)
- [component] Plex GPU wiring — `ks.yaml` attaches `components/gpu`, HelmRelease declares `resourceClaims` + `resources.claims`; CDI injects the device without hostPath mounts or supplementalGroups; Plex UI must enable "Use hardware acceleration when available" → Intel Quick Sync (QSV) manually

- [component] Canonical app shape — `ks.yaml` + `app/{helmrelease,externalsecret,kustomization}.yaml` plus optional `ocirepository.yaml` (only for non-app-template charts; app-template OCIRepository comes from the shared component) and optional `ciliumnetworkpolicy.yaml` and `config/` directory (.claude/skills/k8s-workloads/references/app-scaffolding.md)
- [component] HelmRelease minimal-spec — `spec` carries only `chartRef`, `interval`, `values` (and rare `postRenderers`); install/upgrade/rollback defaults come from the cluster-root patch (kubernetes/flux/cluster/ks.yaml:16-51)
- [component] Shared OCIRepository component — bjw-s `app-template` OCIRepository is provided by `kubernetes/components/common/repos/app-template/` and consumed via Kustomize component; new apps using `app-template` no longer need a per-app `ocirepository.yaml`. Apps using other charts still carry their own OCIRepository pairing in the app directory
- [component] App-managed Secret pattern — ExternalSecret with `refreshInterval: 12h`, `secretStoreRef` to ClusterSecretStore `onepassword-connect`, `creationPolicy: Owner`, no `metadata.namespace` (.claude/skills/k8s-workloads/references/app-scaffolding.md:84-91)
- [component] VolSync per-app wiring — `ks.yaml` attaches the `components/volsync` Kustomize component with `postBuild.substitute` providing `APP`, `APP_UID`, `APP_GID`, and optional `VOLSYNC_CAPACITY`, `VOLSYNC_CACHE`, `VOLSYNC_RETAIN_*` overrides (canonical example: kubernetes/apps/selfhosted/paperless/ks.yaml:11-29)
- [component] Apps with shared VolSync wiring — media (10/11): `bazarr`, `calibre-web-automated`, `isponsorblocktv`, `maintainerr`, `plex`, `plex-trakt-sync`, `prowlarr`, `qbittorrent`, `radarr`, `seerr`, `sonarr`; selfhosted (7/13): `actual`, `backrest`, `mealie`, `paperless`, `paperless-gpt`, `wallos`; not wired: `subsyncarr` (media), `home-gallery` (standalone PVC, no VolSync), `homepage` (configMapGenerator), `open-webui`, `searxng`, `pingvin-share-x`, `resticprofile` (backup tool itself)
- [component] Apps with file-level /backups/<app> export — `paperless` (canonical pattern: NFS mount of `${NAS_IP}:/backups/paperless` at `/data/nas/export`, scheduled `document_exporter` job)
- [component] Apps with NFS mounts — media: `bazarr`, `calibre-web-automated`, `plex`, `qbittorrent`, `radarr`, `sonarr`, `subsyncarr`; selfhosted: `backrest`, `home-gallery`, `paperless`, `resticprofile`; all mount paths from `${NAS_IP}` (mix of read-only media mounts and read-write workspace mounts)
- [component] Security baseline — pod-level `runAsNonRoot: true`, aligned `runAsUser/Group/fsGroup`, `fsGroupChangePolicy: OnRootMismatch`, `seccompProfile: RuntimeDefault`; container-level `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, drop ALL caps, `automountServiceAccountToken: false` (.claude/skills/k8s-workloads/references/runtime-baselines.md:6-22)
- [component] Resource policy — explicit `requests.cpu`, `requests.memory`, `limits.memory` for user-facing apps; CPU limits only on demonstrated need (kubernetes/CLAUDE.md "Resource policy baseline")
- [component] APP_UID / APP_GID convention — defined once in `ks.yaml` `postBuild.substitute`, reused in pod securityContext, in PUID/PGID env vars, and inherited by the shared VolSync component
- [component] Exposure pattern — HTTPRoute with `parentRefs` to `envoy-external` (Cloudflare tunnel) plus optionally `envoy-internal` (LAN VIP) in namespace `networking`; route hostnames under the public domain
- [component] Homepage dashboard metadata — annotations live on the HTTPRoute `metadata.annotations`, not the backing Service, so non-app-template workloads (e.g. Cilium Hubble UI in `kube-system`) get dashboard integration without chart patches. Canonical key set: `gethomepage.dev/enabled: "true"`, `gethomepage.dev/name: <display-name>`, `gethomepage.dev/group: <settings.yaml layout section name>`, `gethomepage.dev/icon: <filename or full URL>`. URL works for icons hosted outside the default `homarr-labs/dashboard-icons` CDN (e.g. `https://cdn.jsdelivr.net/gh/selfhst/icons/svg/cilium-hubble.svg`). Filename-only is resolved against `cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/{svg|png}/<name>`; if the icon only exists in another repo (selfhst/icons, arcticons, etc.), the full URL form is required.
- [component] CronJob convention — bjw-s `app-template` with `type: cronjob`, `concurrencyPolicy: Forbid`, sibling directory like `backup/` if needed; no raw Kubernetes CronJob manifests (.claude/skills/k8s-workloads/references/publication-and-jobs.md:47-55)
- [component] YAML anchor policy — anchors allowed for repeated scalar values (`&port`, `&host`, `&exportDir`, `&tz` (now sourcing `${TIMEZONE}` from cluster-settings), `&resources`, `&probes`, `&image`) using lowerCamelCase; forbidden as map keys (`controllers`, `persistence`, `serviceAccount`, `bindings`) or on scalar app names (kubernetes/CLAUDE.md "YAML anchor policy")

## Claims (verified against repo)

- [claim] "The media namespace (`kubernetes/apps/media/`) hosts 11 application workloads (Arr Stack + Plex companions + Maintainerr) and the selfhosted namespace (`kubernetes/apps/selfhosted/`) hosts 13 workloads (Selfhosted, PFM, Downloading, Infrastructure, AI/search, Sharing groups)" (evidence: repo, ref: `ls kubernetes/apps/media/` + `ls kubernetes/apps/selfhosted/` + `grep gethomepage.dev/group` across helmrelease.yaml files, verified: 2026-06-13)
- [claim] "Apps follow a strict canonical shape: `ks.yaml` at the app root + an `app/` subdirectory holding kustomization.yaml, ocirepository.yaml, helmrelease.yaml, optional externalsecret.yaml. `metadata.namespace` is forbidden on app manifests — Flux `spec.targetNamespace` is the only source of placement" (evidence: repo, ref: kubernetes/CLAUDE.md "Editing And Validation" + .claude/skills/k8s-workloads/references/app-scaffolding.md:64-67, verified: 2026-05-19)
- [claim] "HelmRelease `spec` is minimal — only `chartRef`, `interval`, `values` and rare `postRenderers`. Install/upgrade/rollback defaults are injected globally via a kustomize patch on the cluster-root Kustomization at `kubernetes/flux/cluster/ks.yaml`. Per-HR overrides of those fields are repo-wide anti-pattern" (evidence: repo, ref: kubernetes/CLAUDE.md "HelmRelease minimal-spec policy" + kubernetes/flux/cluster/ks.yaml:16-51, verified: 2026-05-19)
- [claim] "17 of 24 apps attach the shared VolSync component via `ks.yaml` `components: - ../../../../components/volsync` for PVC backups — media (10/11): bazarr, calibre-web-automated, isponsorblocktv, maintainerr, plex, plex-trakt-sync, prowlarr, qbittorrent, radarr, seerr, sonarr; selfhosted (6/13): actual, backrest, mealie, paperless, paperless-gpt, wallos" (evidence: repo, ref: `grep -rl 'components/volsync' kubernetes/apps/media/ kubernetes/apps/selfhosted/`, verified: 2026-06-13)
- [claim] "Paperless is the canonical dual-coverage pattern: VolSync backs up the app PVC AND a scheduled `document_exporter` writes to NFS `/backups/paperless` so resticprofile captures a second file-level copy. The pattern is referenced from `kubernetes/CLAUDE.md` and `kubernetes/apps/selfhosted/CLAUDE.md`" (evidence: repo, ref: kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml (PAPERLESS_EXPORT_DIR, nas-export nfs mount, manage.py document_exporter sidecar), verified: 2026-06-13)
- [claim] "App ExternalSecrets uniformly use `refreshInterval: 12h` (vs. ESO chart default 1h), `secretStoreRef.kind: ClusterSecretStore`, `secretStoreRef.name: onepassword-connect`, `target.creationPolicy: Owner`, and omit `metadata.namespace` — the Flux Kustomization targetNamespace places the resource" (evidence: repo, ref: kubernetes/apps/external-secrets/CLAUDE.md:46-58 + .claude/skills/k8s-workloads/references/app-scaffolding.md:84-91, verified: 2026-06-13)
- [claim] "`APP_UID` and `APP_GID` come from `ks.yaml` `postBuild.substitute` and are reused in the pod securityContext, PUID/PGID env vars, and the VolSync mover securityContext — the substitution is the single source of truth for the app's runtime user" (evidence: repo, ref: kubernetes/apps/selfhosted/paperless/ks.yaml:23-24 + kubernetes/components/volsync/replicationsource.yaml:24-27, verified: 2026-06-13)
- [claim] "Apps use NFS at `${NAS_IP}` for shared media, /backups exports, and writable workspace paths — at least 11 apps mount paths from that server (backrest, bazarr, calibre-web-automated, home-gallery, paperless, plex, qbittorrent, radarr, resticprofile, sonarr, subsyncarr)" (evidence: repo, ref: `grep -rl 'type: nfs' kubernetes/apps/media/ kubernetes/apps/selfhosted/`, verified: 2026-06-13)
- [claim] "HTTPRoute exposure uses `envoy-external` for public traffic (via Cloudflare Tunnel) and additionally `envoy-internal` when the app should be reachable from the LAN with the same hostname. Both Gateway parents listen on `sectionName: https` and route to the app's service identifier" (evidence: repo, ref: kubernetes/apps/selfhosted/backrest/app/helmrelease.yaml:107-117 + kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml (route block), verified: 2026-06-13)
- [claim] "Homepage dashboard groups in active use across all namespaces: `Selfhosted`, `eMail`, `Cloud Storage`, `PFM`, `Bank`, `Investment`, `Funds`, `Media`, `Arr Stack`, `Downloading`, `Infrastructure`, `SaaS & PaaS`, `IoT`, `Observability`. Dashboard metadata lives in `kubernetes/apps/selfhosted/homepage/app/config/settings.yaml` (tab layout: Cloud Services, Finances, Multimedia, Home infra). Apps carry `gethomepage.dev/enabled: true` on HTTPRoute annotations; cross-namespace apps (Cilium Hubble UI in `kube-system`) are joined via HTTPRoute metadata annotations because the Cilium chart ships the Hubble UI Service out-of-band" (evidence: repo, ref: `grep -r 'gethomepage.dev/group' kubernetes/apps/` + `kubernetes/apps/kube-system/cilium/app/httproute.yaml:11` + `kubernetes/apps/selfhosted/homepage/app/config/settings.yaml`, verified: 2026-06-05)
- [claim] "Security baseline is uniform across user-facing apps: pod-level `runAsNonRoot: true` with aligned uid/gid/fsGroup, `fsGroupChangePolicy: OnRootMismatch`, `seccompProfile.type: RuntimeDefault`; container-level `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, drop ALL caps, `automountServiceAccountToken: false`" (evidence: repo, ref: .claude/skills/k8s-workloads/references/runtime-baselines.md:6-22 + sibling apps like paperless, backrest, resticprofile, verified: 2026-06-13)
- [claim] "Resource policy: every app has explicit `requests.cpu` and `requests.memory`, plus a memory limit; CPU limits are added only on demonstrated throttling need. Sizing is taken from live usage or from close sibling apps, not copied from generic defaults" (evidence: repo, ref: kubernetes/CLAUDE.md "Resource policy baseline" + kubernetes/apps/media/CLAUDE.md "User-facing app resource baseline" + kubernetes/apps/selfhosted/CLAUDE.md "User-facing app resource baseline", verified: 2026-06-13)
- [claim] "Reloader (`reloader.stakater.com/auto: "true"` annotation on the workload controller) is the standard restart trigger when ConfigMaps or Secrets are mounted — used by backrest, resticprofile, paperless, etc." (evidence: repo, ref: kubernetes/apps/selfhosted/backrest/app/helmrelease.yaml:27-28 + sibling apps, verified: 2026-06-13)
- [claim] "Chart strategy preference is documented as: (1) official Helm chart, (2) bjw-s `app-template`, (3) custom manifests only when needed. The repo uses bjw-s app-template for nearly every app in media and selfhosted. Apps using `app-template` consume the shared OCIRepository from `kubernetes/components/common/repos/app-template/` — no per-app `ocirepository.yaml` needed. Apps using other charts (cert-manager, flux-provider-pushover, etc.) still carry their own OCIRepository pairing" (evidence: repo, ref: kubernetes/components/common/repos/app-template/ + kubernetes/CLAUDE.md "Default Patterns", verified: 2026-05-22) (evidence: repo, ref: kubernetes/CLAUDE.md "Default Patterns" + .claude/skills/k8s-workloads/references/app-scaffolding.md:9-12, verified: 2026-05-19)
- [claim] "CronJobs are written as bjw-s `app-template` with `type: cronjob` and `concurrencyPolicy: Forbid`, not as raw Kubernetes CronJob manifests" (evidence: repo, ref: .claude/skills/k8s-workloads/references/publication-and-jobs.md:47-55, verified: 2026-05-19)
- [claim] "YAML anchor policy: anchors are allowed only for repeated scalar values (`&port`, `&host`, `&exportDir`, `&tz`, `&resources`, `&probes`, `&image`) in lowerCamelCase, and forbidden as map keys for controllers/persistence/serviceAccount/bindings or on scalar app names" (evidence: repo, ref: kubernetes/CLAUDE.md "YAML anchor policy", verified: 2026-05-19)

## Drift Risk

- [drift] HelmRelease minimal-spec is enforced **only by code review**. There is no automated lint that rejects `install.createNamespace`, `upgrade.remediation.retries`, `uninstall.keepHistory`, etc. on app HRs. Past K3s-era noise has been cleaned but can return with any new app.
- [drift] Apps span two namespaces (media and selfhosted) with a coarse cluster-wide Cilium baseline (`allow-cluster-egress` + `allow-dns-egress`). Per-app CiliumNetworkPolicies are being rolled out per cnp-per-app-audit roadmap (paperless and pingvin-share-x already have CNPs; cloudflare-tunnel has its own). A compromised pod in either namespace still has cluster-wide egress unless it carries the `egress.home.arpa/custom-egress` opt-out label (Szint II).
- [drift] The NFS server (at `${NAS_IP}` from cluster-settings) is a single point of failure for /backups exports and media mounts across at least 11 apps. If the NAS is offline, scheduled exports silently produce stale data and writes block — Restic/Backrest health checks only catch the backup-side failure 24h later.
- [drift] Storage strategy (PVC vs NFS vs emptyDir) is decided per app and documented only in CLAUDE.md plus the runtime-baselines reference — there is no manifest-level enforcement. Apps that diverge from the documented baseline are visible only in code review.
- [drift] The "always wire VolSync when the app has a PVC" rule is informal: 17 of 22 apps wire it, but the 5 that don't are not explicitly enumerated as "intentionally no backup" anywhere. Some may be ephemeral (homepage with configMapGenerator), others may be oversights.
- [drift] APP_UID / APP_GID substitution is per-app — there is no central registry of which uid each app uses. Two apps accidentally picking the same uid against the same NFS export would silently overwrite each other.
- [drift] HTTPRoute parentRefs to `envoy-external` and `envoy-internal` are added per-route — there is no central template. Apps that need both routes but forget the `envoy-internal` parentRef become public-only with no LAN exposure (the operator may not notice if Cloudflare Access is the gate).

## Open Questions / Gaps

- [gap] No verification was run against the live cluster in this pass — claims are repo-evidence only. Each app has its own validation step under `.claude/skills/k8s-workloads/references/validation.md`.
- [gap] Per-app detailed metadata (chart name, image, version, exposure model, NFS mounts, storage class) is **not** enumerated here. Each app deserves its own follow-up note if the area corpus needs deeper coverage; the current inventory is at the group/pattern level only.
- [gap] The exact list of apps with /backups/<app> NFS exports for dual coverage (paperless + ???) was not exhaustively enumerated. The CLAUDE.md mentions "critical apps may intentionally use both layers" but the canonical set is fuzzy beyond Paperless.
- [gap] `cert-manager/` is in scope for this area but was not detailed here — it is a single workload under its own namespace following the same canonical shape; a future expansion can either fold it in or split it out.
- [gap] The Pluto deprecated-API scan (referenced in the flux-gitops area) covers all manifests under `kubernetes/`, but the relationship between Pluto findings and the app inventory was not traced.

## Relations

- depends_on [[external-secrets]]
- depends_on [[flux-gitops]]
- depends_on [[networking]]
- relates_to [[volsync-backup]]
- relates_to [[resticprofile-backup]]
- part_of [[home-ops-platform]]

## Standalone PVC pattern (no VolSync)

- [pattern] When an app's PVC stores only **regenerable derived data** (caches, thumbnails, local indexes) and the source-of-truth lives elsewhere (NFS covered by resticprofile), the app uses a **standalone `app/pvc.yaml`** instead of the `components/volsync` component, and the `ks.yaml` omits the volsync `components:` wiring. Canonical example: `kubernetes/apps/selfhosted/home-gallery` (thumbnails + local DB; source photos on NFS). The PVC manifest must carry an inline comment stating *why* it is excluded from VolSync, so the intent survives review. (verified: 2026-06-13, ref: kubernetes/apps/selfhosted/home-gallery/app/pvc.yaml)

- [component] System Upgrade — `tuppr` controller (Tuppr v0.1.35) in `system-upgrade` namespace; declarative TalosUpgrade and KubernetesUpgrade CRs for GitOps-managed OS and K8s version upgrades. Namespace: `system-upgrade`, path: `kubernetes/apps/system-upgrade/tuppr/`
