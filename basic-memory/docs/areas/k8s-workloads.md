---
title: k8s-workloads
type: area_reference
permalink: home-ops/docs/areas/k8s-workloads
area: k8s-workloads
status: current
confidence: high
verified_at: '2026-10-14'
summary: 'Non-platform Flux-managed application workloads live under kubernetes/apps/<group>/<app>/
  with a canonical ks.yaml + app/ shape. The repo hosts 4 apps in the media namespace
  (consumption: calibre-web-automated, crosswatch, isponsorblocktv, jellyfin), 10
  apps in the downloads namespace (arr-stack + qbittorrent + cronjob helpers: bazarr,
  maintainerr, prowarr, qbittorrent, radarr, recyclarr, arr-search, seerr, sonarr,
  subsyncarr), and 11 apps in the selfhosted namespace (actual, backrest, home-gallery,
  homepage, mealie, paperless, paperless-gpt, pingvin-share-x, resticprofile, sure,
  wallos) — 25 deployed workloads, verified live 2026-10-14. The former media/suggestarr
  directory is deleted. Non-platform subtrees outside the area: cert-manager, crowdsec,
  security/pocket-id, system-upgrade/tuppr, database/ and ai/. Apps follow a strict
  minimal-spec policy for HelmRelease, a hardened security baseline, the shared VolSync
  component for PVC backups (20 of 25 deployed apps wire it across media, downloads,
  and selfhosted namespaces), and the Gateway API split between envoy-external and
  envoy-internal. Per-app secret delivery is always the onepassword-connect ClusterSecretStore
  with 12h refresh. Per-app CNPs are chart-generated from values.networkpolicies.main
  per AD-025.'
verified_against:
- kubernetes/CLAUDE.md
- kubernetes/apps/media/CLAUDE.md
- kubernetes/apps/downloads/CLAUDE.md
- kubernetes/apps/selfhosted/CLAUDE.md
- kubernetes/apps/selfhosted/paperless/ks.yaml
- kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml
- kubernetes/apps/selfhosted/backrest/ks.yaml
- kubernetes/apps/selfhosted/backrest/app/helmrelease.yaml
- kubernetes/apps/selfhosted/resticprofile/app/helmrelease.yaml
- kubernetes/apps/media/calibre-web-automated/ks.yaml
- kubernetes/apps/downloads/radarr/ks.yaml
- kubernetes/apps/downloads/subsyncarr/ks.yaml
- kubernetes/components/volsync/
- kubernetes/flux/cluster/ks.yaml
- kubernetes/components/gateway-oidc/securitypolicy.yaml
- .claude/skills/k8s-workloads/SKILL.md
- .claude/skills/k8s-workloads/references/app-scaffolding.md
- .claude/skills/k8s-workloads/references/runtime-baselines.md
- .claude/skills/k8s-workloads/references/publication-and-jobs.md
drift_risk: HelmRelease minimal-spec is enforced only by code review, not by an automated
  check — every app HR can re-introduce per-HR install/upgrade/rollback overrides
  that conflict with the cluster-root kustomize patch. The area spans three namespaces
  (media, downloads, selfhosted); the apps tree now also hosts database/ and ai/ namespaces
  outside this area. The CNI V3 baseline flip has landed and per-app CNPs are chart-generated
  per AD-025. NFS server (${NAS_IP} from cluster-settings) is a single point of failure
  for /backups and media mounts across many apps; no automated fallback. Storage strategy
  is decided per app (PVC vs NFS vs emptyDir) but the contract is documented only
  in CLAUDE.md. The `gateway-oidc` gate needs no cross-namespace ReferenceGrant (the
  OIDC provider is a public URL, not an in-cluster Service); IAM wiring per app is
  the component + a Pocket ID client, extended per app, not per namespace.
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
- [verified_at] 2026-10-14

## Summary
This area covers non-platform application workloads under `kubernetes/apps/` — anything that is **not** the networking, external-secrets, flux-system, volsync-system, observability, crowdsec, security, system-upgrade, database or ai subtree. Apps are organized into three namespace groups: `kubernetes/apps/media/` (4 deployed apps — consumption: `calibre-web-automated`, `crosswatch`, `isponsorblocktv`, `jellyfin`), `kubernetes/apps/downloads/` (10 apps — arr-stack + qbittorrent + two cronjob helpers: `bazarr`, `maintainerr`, `prowlarr`, `qbittorrent`, `radarr`, `recyclarr`, `arr-search`, `seerr`, `sonarr`, `subsyncarr`), and `kubernetes/apps/selfhosted/` (11 apps — `actual`, `backrest`, `home-gallery`, `homepage`, `mealie`, `paperless`, `paperless-gpt`, `pingvin-share-x`, `resticprofile`, `sure`, `wallos`). That is **25 deployed workloads** (verified live 2026-10-14: 25 HelmReleases across the three namespaces, all Deployments ready). The former `media/suggestarr` directory has been deleted outright — zero references survive repo-wide. `plex` and `plex-trakt-sync` were removed 2026-10-13 (commit 573c7eeb5). Outside the three namespaces, the non-platform subtrees are `cert-manager/`, `crowdsec/`, `security/pocket-id/`, `system-upgrade/tuppr/`, `database/` (cloudnative-pg, dragonfly, dragonfly-operator, postgres) and `ai/` (llama-cpp, open-webui) — `ai/open-webui` is a re-introduction under a new namespace, not the old deleted selfhosted pair.

Apps follow a canonical shape per the k8s-workloads skill: each app lives in `kubernetes/apps/<group>/<app>/` with a `ks.yaml` Flux entry point and an `app/` directory holding `kustomization.yaml`, `helmrelease.yaml`, optional `externalsecret.yaml`, and optional `config/` static files. Every one of the 25 apps charts from the shared bjw-s `app-template` OCIRepository (`kubernetes/components/common/repos/app-template/`, tag 5.3.0), so no per-app `ocirepository.yaml` exists in this area. app-template apps declare their per-app CNP in HelmRelease `values.networkpolicies.main` (AD-025) — 13 of the 25 carry one; hand-written `ciliumnetworkpolicy.yaml` survives only outside this area. App manifests carry **no** `metadata.namespace` and **no** redundant `labels:` blocks — the Flux Kustomization `spec.targetNamespace` + `spec.commonMetadata.labels` are the single source of placement and labeling. HelmRelease `spec` is intentionally minimal (`chartRef`, `interval`, `values`, very rarely `postRenderers`) — the cluster-root `kubernetes/flux/cluster/ks.yaml:21-52` injects install/upgrade/rollback defaults into every HelmRelease through a kustomize patch.

Three cross-cutting patterns thread through every app:

- **Secrets**: `spec.refreshInterval: 12h`, `secretStoreRef.kind=ClusterSecretStore`, `secretStoreRef.name=onepassword-connect`, `target.creationPolicy=Owner`, no `metadata.namespace`. Reloader auto-restarts consumer pods on Secret rewrite.
- **Backups**: PVC-bearing apps that should be backed up attach the `kubernetes/components/volsync/` Kustomize component in their `ks.yaml` and supply `APP`/`APP_UID`/`APP_GID` (and optionally `VOLSYNC_*` overrides) via `postBuild.substitute`. Critical apps may **additionally** write a curated export into the shared NFS `/backups/<app>` tree so the resticprofile plane captures a second copy in OVH Object Storage. Paperless is the canonical dual-coverage example.
- **Exposure**: HTTPRoute attached to `envoy-external` in namespace `networking` for public Cloudflare-Tunnel traffic, and to `envoy-internal` when the app should also be reachable directly from the LAN (split DNS via k8s-gateway). Current membership: 7 apps carry an `envoy-external` parent (`calibre-web-automated`, `home-gallery`, `homepage`, `mealie`, `paperless`, `pingvin-share-x`, `sure`); every downloads route plus `jellyfin`, `crosswatch` and `backrest` are `envoy-internal`-only; `isponsorblocktv`, `recyclarr`, `arr-search` carry no route at all.

Homepage dashboard metadata uses a stable set of groups defined in `kubernetes/apps/selfhosted/homepage/app/config/settings.yaml` layout (tabs: Cloud Services, Finances, Multimedia, Home infra); 8 groups are actually carried by an app (Selfhosted, Media, Arr Stack, Downloading, Infrastructure, PFM, Observability, Security), the remaining layout slots are empty. Annotations are placed on HTTPRoute `metadata.annotations`. Dashboard icons are resolved against the `homarr-labs/dashboard-icons` CDN; icons from other repos (e.g. `selfhst/icons`) need the full URL form.
## Components

### App inventory
**media namespace (kubernetes/apps/media/, 4 apps, consumption):**

- [component] Media — `calibre-web-automated` (Homepage group: `Media`), `jellyfin` (group: `Media`; LAN-only route; iGPU via `components/gpu`), `crosswatch` (group: `Media`; LAN-only route; Trakt watch-state companion)
- [component] Headless companion — `isponsorblocktv` (no route, no dashboard annotations)

**downloads namespace (kubernetes/apps/downloads/, 10 apps, content acquisition):**

- [component] Arr Stack — `bazarr`, `prowlarr`, `radarr`, `seerr`, `sonarr`, `subsyncarr`, `maintainerr` (namespace: downloads, Homepage group: `Arr Stack` — maintainerr moved from `Media` to `Arr Stack`)
- [component] Downloading — `qbittorrent` (namespace: downloads, Homepage group: `Downloading`; initContainer `01-init` runs `app/config/qbt-init.sh` — the former p2pblocklist init is gone)
- [component] Cronjob helpers — `recyclarr`, `arr-search` (app-template `type: cronjob`, config/ + externalsecret, no route, no dashboard annotations, not gateway-oidc-gated; `recyclarr` wires volsync, `arr-search` does not)

**selfhosted namespace (kubernetes/apps/selfhosted/, 11 apps, everything else):**
- [component] Selfhosted — `paperless`, `paperless-gpt`, `mealie`, `home-gallery` (Homepage group: `Selfhosted`)
- [component] PFM (personal finance) — `actual`, `wallos`, `sure` (Homepage group: `PFM`; `sure` is a two-controller release — sure-server + sure-worker — with a second Flux Kustomization `sure-database` placing its CNPG Database in the `database` namespace via `components/cnpg/database`)
- [component] Infrastructure — `backrest` (group: `Infrastructure`, envoy-internal-only), `homepage` (the dashboard itself; native OIDC client, carries no annotations of its own), `resticprofile` (the file-level backup tool)
- [component] Sharing — `pingvin-share-x` (route on envoy-external + envoy-internal)
- [component] cert-manager — one of the non-platform subtrees OUTSIDE the three namespaces, alongside `crowdsec/`, `security/pocket-id/`, `system-upgrade/tuppr/`, `database/` and `ai/`
### Cross-cutting patterns

- [component] Shared GPU component — `kubernetes/components/gpu/` provides a ResourceClaimTemplate (`${APP}-gpu`, deviceClassName: gpu.intel.com, allocationMode: All) for any app needing iGPU access via DRA/CDI; no adminAccess, no namespace label needed (onedr0p pattern)
- [component] Jellyfin GPU wiring — `ks.yaml` attaches `components/gpu` (kubernetes/apps/media/jellyfin/ks.yaml:12), HelmRelease declares `resourceClaims` + `resources.claims` (kubernetes/apps/media/jellyfin/app/helmrelease.yaml:21-23, 78-79); CDI injects the device without hostPath mounts or supplementalGroups
- [component] Canonical app shape — `ks.yaml` + `app/{helmrelease,externalsecret,kustomization}.yaml` plus optional `ocirepository.yaml` (only for non-app-template charts; app-template OCIRepository comes from the shared component) and optional `config/` directory; the per-app CNP is chart-generated from `values.networkpolicies.main` for app-template apps and a hand-written `ciliumnetworkpolicy.yaml` only for non-app-template charts (AD-025) (.claude/skills/k8s-workloads/references/app-scaffolding.md)
- [component] HelmRelease minimal-spec — `spec` carries only `chartRef`, `interval`, `values` (and rare `postRenderers`); install/upgrade/rollback defaults come from the cluster-root patch (kubernetes/flux/cluster/ks.yaml:16-51)
- [component] Shared OCIRepository component — bjw-s `app-template` OCIRepository is provided by `kubernetes/components/common/repos/app-template/` and consumed via Kustomize component; new apps using `app-template` no longer need a per-app `ocirepository.yaml`. Apps using other charts still carry their own OCIRepository pairing in the app directory
- [component] App-managed Secret pattern — ExternalSecret with `refreshInterval: 12h`, `secretStoreRef` to ClusterSecretStore `onepassword-connect`, `creationPolicy: Owner`, no `metadata.namespace` (.claude/skills/k8s-workloads/references/app-scaffolding.md:84-91)
- [component] VolSync per-app wiring — `ks.yaml` attaches the `components/volsync` Kustomize component with `postBuild.substitute` providing `APP`, `APP_UID`, `APP_GID`, and optional `VOLSYNC_CAPACITY`, `VOLSYNC_CACHE`, `VOLSYNC_RETAIN_*` overrides (canonical example: kubernetes/apps/selfhosted/paperless/ks.yaml:11-29)
- [component] Apps with shared VolSync wiring — media (4/4): `calibre-web-automated`, `crosswatch`, `isponsorblocktv`, `jellyfin`; downloads (8/10): `bazarr`, `maintainerr`, `prowlarr`, `qbittorrent`, `radarr`, `recyclarr`, `seerr`, `sonarr`; selfhosted (8/11): `actual`, `backrest`, `mealie`, `paperless`, `paperless-gpt`, `pingvin-share-x`, `sure`, `wallos`; NOT wired (5): `arr-search` (downloads, cronjob, no PVC), `subsyncarr` (downloads, emptyDir + NFS), `home-gallery` (selfhosted, standalone PVC, no VolSync), `homepage` (selfhosted, configMapGenerator), `resticprofile` (selfhosted, backup tool itself)
- [component] Apps with file-level /backups/<app> export — `paperless` (canonical pattern: NFS mount of `${NAS_IP}:/backups/paperless` at `/data/nas/export`, scheduled `document_exporter` job)
- [component] Apps with NFS mounts — media: `calibre-web-automated`, `jellyfin`; downloads: `bazarr`, `qbittorrent`, `radarr`, `sonarr`, `subsyncarr`; selfhosted: `backrest`, `home-gallery`, `paperless`, `resticprofile`; all mount paths from `${NAS_IP}` (mix of read-only media mounts and read-write workspace mounts); all 11 are now probe-gated to scale-to-zero via the `components/zeroscaler` component (nfs_probe external metric through prometheus-adapter) — NAS-down scales them to 0 instead of CrashLoopBackOff (see Update 2026-07-11)
- [component] Security baseline — pod-level `runAsNonRoot: true`, aligned `runAsUser/Group/fsGroup`, `fsGroupChangePolicy: OnRootMismatch`, `seccompProfile: RuntimeDefault`; container-level `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, drop ALL caps, `automountServiceAccountToken: false` (.claude/skills/k8s-workloads/references/runtime-baselines.md:6-22)
- [component] Resource policy — explicit `requests.cpu`, `requests.memory`, `limits.memory` for user-facing apps; CPU limits only on demonstrated need (kubernetes/CLAUDE.md "Resource policy baseline")
- [component] APP_UID / APP_GID convention — defined once in `ks.yaml` `postBuild.substitute`, reused in pod securityContext, in PUID/PGID env vars, and inherited by the shared VolSync component
- [component] Exposure pattern — HTTPRoute with `parentRefs` to `envoy-external` (Cloudflare tunnel) plus optionally `envoy-internal` (LAN VIP) in namespace `networking`; route hostnames under the public domain
- [component] Homepage dashboard metadata — annotations live on the HTTPRoute `metadata.annotations`, not the backing Service, so non-app-template workloads (e.g. Cilium Hubble UI in `kube-system`) get dashboard integration without chart patches. Canonical key set: `gethomepage.dev/enabled: "true"`, `gethomepage.dev/name: <display-name>`, `gethomepage.dev/group: <settings.yaml layout section name>`, `gethomepage.dev/icon: <filename or full URL>`. URL works for icons hosted outside the default `homarr-labs/dashboard-icons` CDN (e.g. `https://cdn.jsdelivr.net/gh/selfhst/icons/svg/cilium-hubble.svg`). Filename-only is resolved against `cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/{svg|png}/<name>`; if the icon only exists in another repo (selfhst/icons, arcticons, etc.), the full URL form is required.
- [component] CronJob convention — bjw-s `app-template` with `type: cronjob`, `concurrencyPolicy: Forbid`, sibling directory like `backup/` if needed; no raw Kubernetes CronJob manifests (.claude/skills/k8s-workloads/references/publication-and-jobs.md:47-55)
- [component] YAML anchor policy — anchors allowed for repeated scalar values (`&port`, `&host`, `&exportDir`, `&tz` (now sourcing `${TIMEZONE}` from cluster-settings), `&resources`, `&probes`, `&image`) using lowerCamelCase; forbidden as map keys (`controllers`, `persistence`, `serviceAccount`, `bindings`) or on scalar app names (kubernetes/CLAUDE.md "YAML anchor policy")

## Claims (verified against repo)
- [claim] "The cluster hosts 25 DEPLOYED application workloads across three namespaces: `media` (4 apps — calibre-web-automated, crosswatch, isponsorblocktv, jellyfin), `downloads` (10 apps — arr-search, bazarr, maintainerr, prowarr, qbittorrent, radarr, recyclarr, seerr, sonarr, subsyncarr), and `selfhosted` (11 apps — actual, backrest, home-gallery, homepage, mealie, paperless, paperless-gpt, pingvin-share-x, resticprofile, sure, wallos). `plex` and `plex-trakt-sync` were removed 2026-10-13 (commit 573c7eeb5, PVCs pruned, orphaned Helm releases uninstalled). The former `media/suggestarr` directory has been deleted outright. `open-webui` is back in the tree under `kubernetes/apps/ai/` (outside this area); `searxng` remains gone" (evidence: repo + live, ref: kubernetes/apps/media/kustomization.yaml:11-14 + kubernetes/apps/downloads/kustomization.yaml:10-19 + kubernetes/apps/selfhosted/kustomization.yaml:11-21 + live HelmRelease counts 4/10/11 with all Deployments ready, verified: 2026-10-14)
- [claim] "Apps follow a strict canonical shape: `ks.yaml` at the app root + an `app/` subdirectory holding kustomization.yaml, helmrelease.yaml, optional externalsecret.yaml, optional config/. `metadata.namespace` is forbidden on app manifests — Flux `spec.targetNamespace` is the only source of placement" (evidence: repo, ref: kubernetes/CLAUDE.md "Editing And Validation" + .claude/skills/k8s-workloads/references/app-scaffolding.md:64-67, verified: 2026-10-14)
- [claim] "HelmRelease `spec` is minimal — only `chartRef`, `interval`, `values` and rare `postRenderers`. Install/upgrade/rollback defaults are injected globally via a kustomize patch on the cluster-root Kustomization. Per-HR overrides of those fields are repo-wide anti-pattern" (evidence: repo, ref: kubernetes/CLAUDE.md "HelmRelease minimal-spec policy" + kubernetes/flux/cluster/ks.yaml:21-52, verified: 2026-10-14)
- [claim] "20 of 25 deployed apps attach the shared VolSync component via `ks.yaml` `components: - ../../../../components/volsync` for PVC backups — media (4/4): `calibre-web-automated`, `crosswatch`, `isponsorblocktv`, `jellyfin`; downloads (8/10): `bazarr`, `maintainerr`, `prowlarr`, `qbittorrent`, `radarr`, `recyclarr`, `seerr`, `sonarr`; selfhosted (8/11): `actual`, `backrest`, `mealie`, `paperless`, `paperless-gpt`, `pingvin-share-x`, `sure`, `wallos`. A repo-wide grep returns 20 ks.yaml files in the three namespaces, matching 20 live ReplicationSources" (evidence: repo + live, ref: grep -rl 'components/volsync' across the three namespace subtrees --include=ks.yaml + kubectl get replicationsource, verified: 2026-10-14)
- [claim] "Paperless is the canonical dual-coverage pattern: VolSync backs up the app PVC AND a scheduled `document_exporter` writes to NFS `/backups/paperless` so resticprofile captures a second file-level copy. The pattern is referenced from `kubernetes/CLAUDE.md` and `kubernetes/apps/selfhosted/CLAUDE.md`" (evidence: repo, ref: kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml:59 (PAPERLESS_EXPORT_DIR), :186 (document_exporter job), :236 (nas-export nfs mount), verified: 2026-10-14)
- [claim] "App ExternalSecrets uniformly use `refreshInterval: 12h` (vs. ESO chart default 1h), `secretStoreRef.kind: ClusterSecretStore`, `secretStoreRef.name: onepassword-connect`, `target.creationPolicy: Owner`, and omit `metadata.namespace` — all 13 externalsecret.yaml files in the area conform" (evidence: repo, ref: kubernetes/apps/external-secrets/CLAUDE.md:34-36 + .claude/skills/k8s-workloads/references/app-scaffolding.md:109-115 + survey of all 13 externalsecret.yaml under the three namespaces, verified: 2026-10-14)
- [claim] "`APP_UID` and `APP_GID` come from `ks.yaml` `postBuild.substitute` and are reused in the pod securityContext, PUID/PGID env vars, and the VolSync mover securityContext — the substitution is the single source of truth for the app's runtime user" (evidence: repo, ref: kubernetes/apps/selfhosted/paperless/ks.yaml:24-31 + kubernetes/components/volsync/replicationsource.yaml:24-27, verified: 2026-10-14)
- [claim] "Apps use NFS at `${NAS_IP}` for shared media, /backups exports, and writable workspace paths — 11 apps mount paths from that server (bazarr, calibre-web-automated, backrest, home-gallery, jellyfin, paperless, qbittorrent, radarr, resticprofile, sonarr, subsyncarr), the same 11 probe-gated by the zeroscaler component" (evidence: repo, ref: grep -rl 'type: nfs' across the three namespace subtrees + grep -rl 'components/zeroscaler' kubernetes/apps --include=ks.yaml, verified: 2026-10-14)
- [claim] "HTTPRoute exposure uses `envoy-external` for public traffic (via Cloudflare Tunnel) and additionally `envoy-internal` when the app should be reachable from the LAN with the same hostname. Both Gateway parents listen on `sectionName: https`. Paperless is the canonical dual-parent example (kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml:210-215); backrest is now `envoy-internal`-only (kubernetes/apps/selfhosted/backrest/app/helmrelease.yaml:109-113) and every downloads route is internal-only — only 7 apps in the area carry an `envoy-external` parent" (evidence: repo, ref: grep -rl 'name: envoy-external' across the three namespace subtrees = 7 files + paperless/backrest helmreleases, verified: 2026-10-14)
- [claim] "Homepage dashboard groups actually carried by an app: 8 (Selfhosted, Media, Arr Stack, Downloading, Infrastructure, PFM, Observability, Security); eMail, Cloud Storage, Bank, Investment, Funds, SaaS & PaaS, IoT are empty layout slots. Dashboard metadata lives in `kubernetes/apps/selfhosted/homepage/app/config/settings.yaml` (tab layout: Cloud Services, Finances, Multimedia, Home infra). `maintainerr` sits in `Arr Stack` (kubernetes/apps/downloads/maintainerr/app/helmrelease.yaml:78), `jellyfin`/`crosswatch` in `Media` (:95-96 / :89-90); the `Security` group is carried by `crowdsec/crowdsec-web-ui` (:106) and `security/pocket-id` (httproute.yaml:25); Observability by echo-server, grafana, victoria-logs and the kube-system hubble-ui HTTPRoute (kubernetes/apps/kube-system/cilium/app/httproute.yaml:11)" (evidence: repo, ref: grep -rh 'gethomepage.dev/group' kubernetes/apps/ + homepage settings.yaml, verified: 2026-10-14)
- [claim] "Security baseline is uniform across user-facing apps: pod-level `runAsNonRoot: true` with aligned uid/gid/fsGroup, `fsGroupChangePolicy: OnRootMismatch`, `seccompProfile.type: RuntimeDefault`; container-level `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, drop ALL caps, `automountServiceAccountToken: false`" (evidence: repo, ref: .claude/skills/k8s-workloads/references/runtime-baselines.md:6-22 + sibling apps like paperless, backrest, resticprofile, verified: 2026-10-14)
- [claim] "Resource policy: every app has explicit `requests.cpu` and `requests.memory`, plus a memory limit; CPU limits are added only on demonstrated throttling need. Sizing is taken from live usage or from close sibling apps, not copied from generic defaults" (evidence: repo, ref: kubernetes/CLAUDE.md "Resource policy baseline", verified: 2026-10-14)
- [claim] "Reloader (`reloader.stakater.com/auto: "true"` annotation on the workload controller) is the standard restart trigger when ConfigMaps or Secrets are mounted — 19 of the area's helmrelease.yaml files carry it" (evidence: repo, ref: kubernetes/apps/selfhosted/backrest/app/helmrelease.yaml:30-31 + grep -rln 'reloader.stakater.com/auto' across the three namespace subtrees = 19 files, verified: 2026-10-14)
- [claim] "Chart strategy: every one of the 25 apps in the area charts from the shared bjw-s `app-template` OCIRepository in `kubernetes/components/common/repos/app-template/` (tag 5.3.0) — no per-app `ocirepository.yaml` exists in media/downloads/selfhosted. Apps outside the area using other charts (cert-manager etc.) still carry their own OCIRepository pairing" (evidence: repo, ref: grep chartRef across all 25 area helmreleases = 25x name: app-template + kubernetes/apps/cert-manager/cert-manager/app/ocirepository.yaml, verified: 2026-10-14)
- [claim] "CronJobs are written as bjw-s `app-template` with `type: cronjob` and `concurrencyPolicy: Forbid`, not as raw Kubernetes CronJob manifests — `recyclarr` and `arr-search` follow this" (evidence: repo, ref: kubernetes/apps/downloads/recyclarr/app/helmrelease.yaml:29 + kubernetes/apps/downloads/arr-search/app/helmrelease.yaml:26 + .claude/skills/k8s-workloads/references/publication-and-jobs.md:47-55, verified: 2026-10-14)
- [claim] "YAML anchor policy: anchors are allowed only for repeated scalar values (`&port`, `&host`, `&exportDir`, `&tz`, `&resources`, `&probes`, `&image`) in lowerCamelCase, and forbidden as map keys for controllers/persistence/serviceAccount/bindings or on scalar app names" (evidence: repo, ref: kubernetes/CLAUDE.md "YAML anchor policy", verified: 2026-10-14)
- [claim] "`gateway-oidc` is wired into ALL EIGHT UI-bearing downloads apps (bazarr, maintainerr, prowlarr, qbittorrent, radarr, seerr, sonarr, subsyncarr) — but NOT the `recyclarr`/`arr-search` cronjobs, so the downloads namespace is no longer OIDC-gated as a whole. Inside this area it is also wired into `selfhosted/backrest` (ks.yaml:13) and `selfhosted/paperless-gpt` (ks.yaml:13). Outside this area consumers are `networking/echo-server`, `kube-system/cilium` (hubble-ui HTTPRoute), `observability/victoria-logs` and `volsync-system/kopia` — 14 ks.yaml files repo-wide" (evidence: repo, ref: grep -rl 'components/gateway-oidc' kubernetes/apps --include=ks.yaml = 14 files, verified: 2026-10-14)
- [claim] "Six app-shaped subtrees under kubernetes/apps are outside this area's inventory and belong to other areas or are platform: `crowdsec/` (crowdsec + crowdsec-bouncer + crowdsec-web-ui), `security/pocket-id/` (docs/areas/iam), `system-upgrade/tuppr` (docs/areas/talos-cluster), `database/` (cloudnative-pg, dragonfly, dragonfly-operator, postgres), `ai/` (llama-cpp, open-webui), plus the platform subtrees. `crowdsec/crowdsec-web-ui` and `security/pocket-id` carry the `Security` Homepage group" (evidence: repo, ref: kubernetes/apps/kustomization.yaml:3-17 + ls kubernetes/apps, verified: 2026-10-14)
- [claim] "CNP label-selector convention — bjw-s `app-template` sets `global.nameOverride: {{ .Release.Name }}` when unset (re-checked at the in-use tag 5.3.0, chart templates/common.yaml:5-8), so the workload NAME and the pod `app.kubernetes.io/name` label both equal the HelmRelease `metadata.name`; a HelmRelease rename moves the `name` label. Non-app-template charts set `app.kubernetes.io/name` to the CHART name, not the release name. After AD-025 no hand-written CNP exists in this area (the 15 remaining `ciliumnetworkpolicy.yaml` files are all platform apps outside it) — per-app CNPs are chart-generated and follow a release rename automatically; controller-label selectors survive only as cross-release peer rules (kubernetes/apps/selfhosted/paperless-gpt/app/helmrelease.yaml:176) and in the show-cnp-matrix recipe (kubernetes/mod.just:307). Consequence: a release rename still moves the `name` label that platform CNPs and cross-release peers match — those rules MUST follow in the SAME commit" (evidence: repo + chart, ref: app-template 5.3.0 templates/common.yaml:5-8 (pulled and inspected 2026-10-14) + find kubernetes/apps -name ciliumnetworkpolicy.yaml = 15, none in media/downloads/selfhosted, verified: 2026-10-14)
## Drift Risk

- [drift] HelmRelease minimal-spec is enforced **only by code review**. There is no automated lint that rejects `install.createNamespace`, `upgrade.remediation.retries`, `uninstall.keepHistory`, etc. on app HRs. Past K3s-era noise has been cleaned but can return with any new app.
- [drift] Apps span three namespaces (media, downloads, selfhosted) under the AD-023 two-tier Cilium model (V3 flip landed, commit 953626966). The cluster-wide baseline `allow-cluster-egress` no longer grants `toEntities: world` — public internet egress is opt-in via the `egress.home.arpa/allow-world` pod label (backed by the `allow-world-egress` CCNP, toCIDRSet 0.0.0.0/0 except RFC1918/100.64/10) or a per-app CNP. Per-app CNPs cover app-unique upstreams the flipped baseline no longer grants (coredns world:53, kube-prometheus-stack-prometheus LAN 192.168.1.1/32:9100); crown-jewel apps (external-secrets, onepassword-connect, pocket-id, paperless, actual, cloudflare-tunnel, envoy-external/internal) carry their own CNPs. A compromised pod without the allow-world label or a matching CNP has cluster-only egress — the previous "coarse baseline" residual risk is closed.
- [drift] The NFS server (at `${NAS_IP}` from cluster-settings) is a single point of failure for /backups exports and media mounts across at least 11 apps. Mitigation landed 2026-07-11 (see Update below): the 11 NFS-mount Deployments are probe-gated to scale-to-zero via the `components/zeroscaler` component (nfs_probe external metric served by prometheus-adapter), so NAS-down CrashLoopBackOff noise is eliminated. Residual gap: the Paperless `document_exporter` CronJob is not HPA-gated, so scheduled exports still silently produce stale data when the NAS is offline — Restic/Backrest health checks only catch the backup-side failure 24h later.
- [drift] Storage strategy (PVC vs NFS vs emptyDir) is decided per app and documented only in CLAUDE.md plus the runtime-baselines reference — there is no manifest-level enforcement. Apps that diverge from the documented baseline are visible only in code review.
- [drift] The "always wire VolSync when the app has a PVC" rule is informal: 20 of 25 deployed apps wire it, and the 5 that do not (`arr-search`, `subsyncarr`, `home-gallery`, `homepage`, `resticprofile`) are still not explicitly enumerated as "intentionally no backup" anywhere. Some are clearly ephemeral (`arr-search` cronjob, homepage with configMapGenerator) or self-referential (resticprofile is the backup tool), but `home-gallery` holds a standalone PVC with no backup and no recorded decision.
- [drift] APP_UID / APP_GID substitution is per-app — there is no central registry of which uid each app uses. Two apps accidentally picking the same uid against the same NFS export would silently overwrite each other.
- [drift] HTTPRoute parentRefs to `envoy-external` and `envoy-internal` are added per-route — there is no central template. Apps that need both routes but forget the `envoy-internal` parentRef become public-only with no LAN exposure (the operator may not notice if Cloudflare Access is the gate).
- [drift] The `gateway-oidc` OIDC gate requires a matching Pocket ID client (with `allowed_user_groups`) and a 1Password `${APP}_client_secret` field before a new app is reachable. A missing secret fails closed, but a missing group list does NOT — the Terraform precondition in provision/pocket-id is what keeps that from reaching the IdP — verify OIDC login works after wiring a new app.

## Open Questions / Gaps

- [gap] The 2026-08-03 pass was repo-evidence only; the 2026-10-14 re-verification additionally checked the live cluster read-only (HelmReleases, Deployments, ReplicationSources, CiliumNetworkPolicy counts all matched the repo). Each app has its own validation step under `.claude/skills/k8s-workloads/references/validation.md`.
- [gap] Per-app detailed metadata (image, route, storage profile) lives in the app ks.yaml/helmrelease.yaml, not duplicated here to avoid drift.


## Update — 2026-07-11: NFS-dependency scale-to-zero gating (zeroscaler)

Implemented via `docs/progress/nfs-dependency-zeroscaler` (done) + `docs/progress/prometheus-adapter` (done); re-verified against the cluster after deploy.

- [observation] New reusable `kubernetes/components/zeroscaler/` Kustomize component — a single `HorizontalPodAutoscaler` (autoscaling/v2) templated via `postBuild.substitute` (`${APP}`, `${CONTROLLER:=Deployment}`, `${ZEROSCALER_METRIC_NAME:=probe_success}`, `${ZEROSCALER_JOB_NAME:=nfs_probe}`): minReplicas 0, maxReplicas 1, External metric target Value "1", behavior scaleDown/scaleUp Pods policies periodSeconds 15. Verbatim match of the bjw-s `components/zeroscaler` pattern.
- [observation] 11 NFS-mount apps wired via `ks.yaml` `components: [../../../../components/zeroscaler]`: media (`calibre-web-automated`, `plex`), downloads (`bazarr`, `qbittorrent`, `radarr`, `sonarr`, `subsyncarr`), selfhosted (`backrest`, `home-gallery`, `paperless`, `resticprofile`). Each HPA verified live: minReplicas 0, maxReplicas 1, currentReplicas 1, ScalingActive=True, ValidMetricFound on `probe_success{job: nfs_probe}`.
- [observation] Enabler: `prometheus-adapter` serves `external.metrics.k8s.io` so the HPA `type: External` metric resolves (see [[prometheus-adapter]]); without it the HPAs stay in FailedGetExternalMetric.
- [observation] Companion `Probe` CRs on blackbox-exporter renamed (nas-icmp → `devices`, nfs-tcp → `nfs`) with symmetric `<name>_probe` jobNames — the zeroscaler metric selector matches `job: nfs_probe`.
- [observation] Behavior: NAS/NFS down → `probe_success{job=nfs_probe}` → 0 → HPA scales the app to 0; NAS recovers → scales back to 1. CrashLoopBackOff noise during NAS-down is eliminated for the 11 Deployments.
- [observation] The zeroscaler HPAs (max=1, min=0) are permanently "maxed out" while the probe is healthy, so the kubernetes-apps `KubeHpaMaxedOut` rule guard `max != min` does not exclude them → 11 constant firing warnings, silenced via the giantswarm silence-operator + a global `Silence` CR (see [[silence-operator]]).
- [follow-up] The Paperless `document_exporter` CronJob is NOT HPA-gated (CronJobs have no HPA target), so it still silently produces stale exports during NAS-down — the residual unguarded slice of the NFS SPOF (reflected in the updated Drift Risk bullet above).

## Update 2026-08-03 — staleness re-verification

Full re-verification against the live repo as part of the `area-reference-staleness-audit`
roadmap item. Previous `verified_at` was 2026-07-05 (body block still said 2026-06-17).
Verdict on arrival: MAJOR-DRIFT — every `verified_against` path still existed, but the inventory
itself, which is the whole point of this note, was wrong.

- [correction] **The app count was wrong: 22 deployed, not 24.** The entire AI/search group
  (`open-webui`, `searxng`) was deleted in commit `ce310f0f6 cleanup`; no reference to either
  survives anywhere under `kubernetes/`. selfhosted is 10 apps, not 12.
- [correction] VolSync coverage is 18 of 22, not 17 of 24: `pingvin-share-x` now wires it, and two
  of the previously-unwired apps no longer exist. The genuine "no backup" list shrank from 7 to 4
  (`subsyncarr`, `home-gallery`, `homepage`, `resticprofile`) — of which only `home-gallery` holds a
  standalone PVC with no backup and no recorded decision, which is now stated in the drift entry.
- [correction] `gateway-oidc` was documented as a maintainerr-specific example. It now gates ALL
  EIGHT downloads apps — the namespace is OIDC-gated as a whole. The reviewer also found two uses
  the worker's namespace-scoped grep missed: `networking/echo-server` and `kube-system/cilium`
  (targeting the hubble-ui HTTPRoute). 11 ks.yaml files wire the component repo-wide.
- [correction] The Homepage group list named 14 groups; only 8 are actually carried by an app
  (Selfhosted, Media, Arr Stack, Downloading, Infrastructure, PFM, Observability, and a NEW
  `Security` group). The other 7 (eMail, Cloud Storage, Bank, Investment, Funds, SaaS & PaaS, IoT)
  are empty layout slots in `homepage/app/config/settings.yaml` with no app behind them.
- [addition] A 23rd app directory exists: `kubernetes/apps/media/suggestarr/`. It is fully shaped
  and wires volsync + gateway-oidc, but it is COMMENTED OUT of
  `kubernetes/apps/media/kustomization.yaml:15`, so Flux never reconciles it. Whether that is
  intentional or a stalled rollout is not derivable from the manifests — flagged for the human.
- [addition] Four app-shaped subtrees appeared that this note never mentioned: `crowdsec/`,
  `security/pocket-id/`, `system-upgrade/tuppr/`. Each is claimed by another area; recorded here so
  the inventory boundary is explicit rather than an unexplained absence.

## Update 2026-08-15 — homepage is now a native OIDC client

- [observation] [auth] `homepage` (selfhosted) gained a native OIDC gate with Homepage 2.0's built-in auth, restricted to the `infra_admins` Pocket ID group. It is NOT a `gateway-oidc` consumer, so the OIDC-coverage claims above (which enumerate gateway-gated apps) are unaffected — this is the second auth model in this area's inventory alongside the envoy-gated one. Authoritative detail lives in [[iam]].
- [observation] [auth] Consequence for the exposure model: the dashboard's origin is no longer reachable unauthenticated on EITHER gateway. Previously the envoy-internal LAN path had no identity gate at all, and the envoy-external path relied solely on Cloudflare Access (which is retained as a second layer).
- [observation] [gotcha] `HOMEPAGE_ALLOWED_HOSTS` moved off `"*"` to the real hostname, which required an explicit `Host: localhost:3000` header on the kubelet probes — upstream runs host validation ahead of the `/api/healthcheck` auth exemption. See [[homepage-recon-exposure]].

## Update 2026-09-19 — jellyfin 12.1; media inventory predates two apps

- [observation] The App inventory above (verified 2026-08-03) does not list jellyfin or crosswatch
  (both deployed in the media namespace after that verification). Full inventory refresh is owed.
- [observation] jellyfin (kubernetes/apps/media/jellyfin) is digest-pinned and was migrated
  10.11.11 -> 12.1 on 2026-09-19 (commit be3c07022) with a startup probe guarding first-boot DB
  migrations (PR #4390). QSV hardware transcode re-verified on 12.1 + FFmpeg 8.1.2. Execution record:
  [[jellyfin-12-migration]].

- [drift] 2026-10-13 — plex and plex-trakt-sync were removed from the cluster (commit 573c7eeb5: app trees, ks entries, PLEX_IP var, Plex Renovate rules, the plex-trakt-sync HubblePolicyDeny tier; PVCs pruned, orphaned Helm releases uninstalled). Every plex / plex-trakt-sync mention above is stale; this note predates crosswatch and jellyfin and needs a full re-verification.

## Update 2026-10-13 — chart-generated per-app CNPs (AD-025)

- [observation] All 17 app-template apps with a per-app CNP now render it from HelmRelease `values.networkpolicies.main` (`type: cilium`): the CNP is named after the release, owned by Helm (`app.kubernetes.io/managed-by: Helm`), and its endpointSelector is derived from the controller — a release or controller rename moves the policy with the pods, closing the #4132 trap on the policy side (cross-release peers in rules stay raw matchLabels). Pattern and constraints: `.claude/skills/k8s-workloads/references/app-scaffolding.md` "Per-app CiliumNetworkPolicy (AD-025)".
- [observation] The 2026-08-06 CNP label-selector claim above (counts of `ciliumnetworkpolicy.yaml` files selecting the controller label) predates this migration and no longer reflects the tree; audit per-app policies via `networkpolicies:` in HelmReleases or the live cluster (`just k8s show-cnp-matrix`).

## Update 2026-10-14 — full re-verification (inventory refresh)

Full re-verification against the repo at HEAD and the live cluster, closing the debt recorded in the 2026-09-19 and 2026-10-13 updates. New `verified_at` 2026-10-14.

- [correction] **App count is 25, not 22**: media (4: calibre-web-automated, crosswatch, isponsorblocktv, jellyfin), downloads (10: + recyclarr, arr-search), selfhosted (11: + sure). plex and plex-trakt-sync are gone from the inventory rows (removal 2026-10-13, commit 573c7eeb5); suggestarr has been deleted outright — every suggestarr mention above is history.
- [addition] `sure` (selfhosted, PFM group): two-controller release (sure-server + sure-worker) with a second Flux Kustomization `sure-database` placing its CNPG Database in the `database` namespace via `components/cnpg/database` — the first app-owned-database-in-database-namespace pattern in this area.
- [addition] `recyclarr` + `arr-search` (downloads): app-template cronjobs, config/ + externalsecret, no routes, not gateway-oidc-gated; recyclarr wires volsync, arr-search does not — so "downloads is OIDC-gated as a whole" is no longer literally true.
- [correction] gateway-oidc consumers grew to 14 ks.yaml repo-wide; new in-area consumers are `backrest` and `paperless-gpt`; new outside-area consumers are `observability/victoria-logs` and `volsync-system/kopia`.
- [correction] Exposure membership: only 7 apps carry `envoy-external`; every downloads route, jellyfin, crosswatch and backrest are `envoy-internal`-only; backrest is no longer a dual-parent example (paperless is).
- [correction] maintainerr moved from Homepage group `Media` to `Arr Stack`; the qbittorrent p2pblocklist initContainer claim is gone — the current init is `01-init`/`qbt-init.sh` with no blocklist logic.
- [correction] Boundary: `database/` and `ai/` subtrees now exist under kubernetes/apps; open-webui is back under `ai/` (outside this area), searxng remains gone.
- [correction] Citation refresh: cluster-root HR patch at `kubernetes/flux/cluster/ks.yaml:21-52`; paperless ks substitute block `kubernetes/apps/selfhosted/paperless/ks.yaml:24-31`; app-scaffolding secret pattern at `:109-115`; backrest reloader `:30-31`; ESO pattern guide `kubernetes/apps/external-secrets/CLAUDE.md:34-36`; shared app-template chart tag 5.3.0 (nameOverride behavior re-checked at 5.3.0 by pulling the chart).
- [observation] Hand-written `ciliumnetworkpolicy.yaml` no longer exists in media/downloads/selfhosted (15 files remain repo-wide, all platform apps); 13 of the 25 area apps render their CNP from `values.networkpolicies.main` — matching the live CNP counts (selfhosted 7, downloads 4, media 2).
