---
title: jellyfin
type: note
permalink: home-ops/docs/progress/jellyfin
---

# jellyfin — execution progress

## Metadata (observation-form)

- [type] progress-note
- [topic] Jellyfin 10.11.11 media server alongside plex in the media namespace, with Introskipper support
- [status] DEPLOYED - CrashLoopBackOff fixed via fsGroupChangePolicy=Always; pod 1/1 Running 0 restart, HR Ready=True; commit 88cfbb544 on main (2026-08-21)
- [branch] feat/jellyfin
- [area] k8s-workloads, networking, volsync-backup
- [created] 2026-08-20
- [reference] bjw-s-labs/home-ops kubernetes/apps/media/jellyfin (helmrelease.yaml + ks.yaml)
- [relates_to] [[k8s-workloads]]
- [relates_to] [[networking]]

## Decisions (with the human, 2026-08-20)

- [decision] **Image**: `ghcr.io/jellyfin/jellyfin:10.11.11@sha256:45f648c382a0c8b552582fcea40e95cb17c5d475473a891cba0eb7523fb92112` — **REVISED 2026-08-21.** The first round pinned the explicitly requested pre-release `12.0-rc5@sha256:669d234c…`; the human then switched to the stable 10.11.11, which is byte-identical to the tag+digest the bjw-s reference pins. Note `v10.11.11` does NOT exist in the registry — the tag carries no `v` prefix. Side effects of the switch: Introskipper now runs on its **stable 10.11 track** (`10.11/v1.10.11.22`) instead of the `12.0` pre-release track, and its documented system requirement is literally "Jellyfin 10.11.11 (or newer)" — an exact match. Renovate needs no extra config: every `automerge` rule in `.renovate/autoMerge.json5` is `false`, so both 10.11.x patches and a future 12.x major arrive as reviewable PRs.
- [decision] **Exposure**: `envoy-internal` HTTPRoute ONLY (`jellyfin.${PUBLIC_DOMAIN}`), **no LoadBalancer service**. Deliberately different from both the reference (which adds an LB IP) and plex (LB-only, no route). No `JELLYFIN_IP` cluster-setting was added.
- [decision] **No OIDC gate**: `components/gateway-oidc` deliberately NOT attached — the Envoy OIDC redirect breaks native Jellyfin clients (Android TV, iOS). Jellyfin's own auth is the boundary; acceptable because the route is internal-only.
- [decision] **GPU**: the node advertises exactly ONE `gpu.intel.com` device (`0000-00-02-0-0x9bc5`, `allowMultipleAllocations: None`), and plex's DRA claim held it. Human chose to **hand the iGPU to jellyfin**; plex loses hardware transcode. The alternative (one shared `ResourceClaim` in the `media` namespace referenced by both pods via `resourceClaimName`, which DRA's `reservedFor` permits) was surfaced and not taken.
- [decision] **Egress deviation from the discussed FQDN allowlist**: implemented as `egress.home.arpa/allow-world: "true"` (the `allow-world-egress` CCNP), NOT a per-app `toFQDNs` CNP. Rationale: a media server needs metadata providers (TMDB/TVDB image CDNs) on top of the plugin catalog, and every close sibling in the same class (plex, sonarr, radarr) uses `allow-world`. An FQDN allowlist would be a fragile, high-maintenance list. Consequence: no per-app `ciliumnetworkpolicy.yaml` exists for jellyfin at all — ingress is the `ingress-from-gateway-internal` CCNP, egress the `allow-world-egress` CCNP.
- [decision] **Storage split**: config PVC (`jellyfin`, 5Gi, VolSync-backed) + separate `jellyfin-metadata` PVC (10Gi, deliberately NOT backed up) carrying `/metadata` (library artwork) and `/config/data/introskipper` (fingerprint DB). Mirrors the plex `plex` + `plex-rebuildable` split and the reference's metadata PVC.
- [decision] **Introskipper**: plugin installation is unavoidably a manual UI step (there is no GitOps plugin installer). GitOps prepares the mount + the internet egress; the human installs from the plugin catalog. Human also chose to include the **File Transformation** plugin (optional web-UI enhancements).

## What was implemented

New app `kubernetes/apps/media/jellyfin/`:

- `ks.yaml` — components `gpu` + `volsync` + `zeroscaler`; dependsOn `onepassword-connect`, `democratic-csi`, `intel-gpu-resource-driver`; `postBuild.substitute`: `APP: jellyfin`, `VOLSYNC_CAPACITY: "5Gi"`; `targetNamespace: media`
- `app/helmrelease.yaml` — app-template 5.1.0 via the shared OCIRepository, `defaultPodOptions` style (the reference pins the SAME chart version 5.1.0 but sets pod options per-controller via `controllers.jellyfin.pod`; this repo's house style is the global `defaultPodOptions`); UID/GID/fsGroup 10001 (repo default, matches the VolSync mover); `readOnlyRootFilesystem: true`, drop ALL caps, seccomp RuntimeDefault; `/health` probes on 8096 with `startup: disabled` (sonarr pattern); `JELLYFIN_PublishedServerUrl` = the internal route URL; resources 25m CPU / 512Mi request, 4Gi memory limit
- `app/pvc-metadata.yaml` — `jellyfin-metadata`, 10Gi, `democratic-csi-local-hostpath`
- `app/kustomization.yaml` — pvc-metadata + helmrelease (no ExternalSecret: jellyfin needs no bootstrap secret; the VolSync ES comes from the component)
- `kubernetes/apps/media/kustomization.yaml` — jellyfin ks.yaml registered

Plex change (separate commit `8fbb42332`):

- `plex/ks.yaml` — removed `components/gpu` and the `intel-gpu-resource-driver` dependsOn
- `plex/app/helmrelease.yaml` — removed `defaultPodOptions.resourceClaims` and `resources.claims`

Mounts that differ from the reference by intent:

- `/cache` emptyDir instead of a separate `/transcode` volume — `JELLYFIN_CACHE_DIR=/cache` (from the image config) already holds the transcode working directory, so a second volume plus a UI path change would be redundant
- ~~`DOTNET_SYSTEM_IO_DISABLEFILELOCKING` omitted~~ — **CORRECTED 2026-08-21, now set to `"true"`.** The original rationale ("the reference needs it for config on network storage") was wrong: the reference's config PVC uses `storageClassName: ${KOPIUR_STORAGECLASS:=miroir-local}` (components/kopiur/backup/pvc.yaml), a local class just like ours. The flag's real target is the **NFS media mount**, which we have identically: .NET 6+ enforces `FileShare` with `flock()`, which is unreliable over NFS and surfaces as intermittent "file in use" IOExceptions during scan/playback. A `gh api search/code` over the reference repo returns exactly ONE hit for the variable (jellyfin only, not their .NET *arr apps), confirming it is a deliberate jellyfin-specific setting rather than a house-wide default.

## Verification (local, pre-deploy)

- [verified] `yamllint` + `yamlfmt -lint` clean on all new/touched files
- [verified] `pre-commit run --files …` — all applicable hooks Passed (gitleaks, yamlfmt, yamllint, secret check)
- [verified] `flux-local test --all-namespaces --enable-helm --path kubernetes/flux/cluster` → **134 passed** (0 failed). Note: must run with `dangerouslyDisableSandbox` — inside the Bash sandbox every `helm template` OCI pull fails with the known Go TLS error `x509: OSStatus -26276`, which is environmental and unrelated to the change.
- [verified] Rendered Deployment carries `resourceClaims: [{name: gpu, resourceClaimTemplateName: jellyfin-gpu}]`, `resources.claims: [{name: gpu}]`, all six volumeMounts (`/cache`, `/config`, `/metadata`, `/config/data/introskipper`, `/media`, `/tmp`), and the two CCNP labels. The 10.11.11 image config exposes the same `JELLYFIN_DATA_DIR=/config` / `JELLYFIN_CACHE_DIR=/cache` layout as 12.0-rc5, so the mount design is unaffected by the version switch.
- [verified] Rendered `ResourceClaimTemplate jellyfin-gpu` exists; `plex-gpu` is gone from the build output and the plex Deployment has no GPU claim
- [verified] Rendered HTTPRoute: single `envoy-internal/https` parentRef, hostname `jellyfin.horvathzoltan.me`, Homepage annotations (group `Media`, icon `jellyfin.svg`)
- [verified] Introskipper supports our version — the upstream repo ships parallel `10.11` and `12.0` release tracks (`10.11/v1.10.11.22` is current on the stable track we now target, and its stated requirement is Jellyfin 10.11.11+); manifest URL `https://intro-skipper.org/manifest.json` is version-aware and returns the right build per server version, so the URL is the same either way
- [not verified] Nothing is deployed. Live behavior (pod scheduling with the freed GPU, VAAPI/QSV transcode, plugin install, NFS library scan) is post-merge work.

## Post-deploy manual steps (Jellyfin UI, after Flux reconciles)

1. Complete the Jellyfin setup wizard; add libraries from `/media`.
2. Set the metadata path to `/metadata` (Dashboard → Playback/Library settings) so artwork lands on the non-backed-up PVC instead of the config PVC.
3. Enable hardware acceleration → **Intel QuickSync (QSV)** or VAAPI on `/dev/dri/renderD128` (CDI-injected by the Intel DRA driver; same manual toggle plex needed).
4. Add plugin repository `https://intro-skipper.org/manifest.json` → install **Intro Skipper** from the catalog → restart.
5. Optional: add `https://www.iamparadox.dev/jellyfin/plugins/manifest.json` → install **File Transformation** for the web-UI extras.
6. Verify the Introskipper fingerprint DB materializes under `/config/data/introskipper` (i.e. on `jellyfin-metadata`, not the backed-up config PVC).

## Follow-ups

- [task] Plex now transcodes in software. Decide whether plex stays at all, or whether the shared-`ResourceClaim` route is worth revisiting so both servers can use the iGPU.
- [task] Any in-cluster consumer of jellyfin needs a per-app CNP admitting it on 8096, because the baseline is ingress default-deny and jellyfin has no CNP today. Two concrete cases: (a) `seerr` if it should drive jellyfin instead of plex; (b) `sonarr`/`radarr`/`bazarr` library-refresh notifications (Connect → Emby/Jellyfin) — the reference's own CNP admits exactly `bazarr`, `sonarr`, `radarr`, `maintainerr` plus two apps we do not run (`mumc`, `jellyplex-watched`).
- [task] Update BM `docs/areas/k8s-workloads` after deployment: media namespace grows to 5 apps, and the "Plex GPU wiring" component claim becomes a jellyfin claim.
- [task] Sizing is estimated from plex, not measured — revisit `requests.memory: 512Mi` / `limits.memory: 4Gi` and the 10Gi metadata PVC once the library is scanned.
- [task] ~~12.0-rc5 pre-release risk~~ — dropped, we ship stable 10.11.11. A future 12.x major bump will need an Introskipper track change (`10.11` → `12.0` plugin build) and a plugin-ABI check; Renovate PRs are review-gated, not auto-merged.

## Reference diff — full field-by-field audit (2026-08-21)

Triggered by the human asking whether any other reference setting we skipped is actually needed.
Reference: `bjw-s-labs/home-ops` @ main, `kubernetes/apps/media/jellyfin/` (helmrelease.yaml, ks.yaml,
ciliumnetworkpolicy.yaml, ocirepository.yaml).

**Adopted after the audit:**

- [decision] `DOTNET_SYSTEM_IO_DISABLEFILELOCKING: "true"` — ADDED. See the corrected rationale above (NFS media mount, not config storage).

**Reviewed and deliberately NOT adopted, with evidence:**

- [decision] `service.app.ports.http.appProtocol: kubernetes.io/ws` — **verified no-op for us.** Envoy Gateway's `kubernetes.io/ws` / `kubernetes.io/wss` handling does NOT enable websocket support (Envoy upgrades websockets on HTTP routes regardless); per the EG v1.8.1 release note it "force[s] HTTP/1.1 upstream connections instead of negotiating HTTP/2, avoiding compatibility issues with WebSocket backends that do not support RFC 8441 extended CONNECT", implemented in `internal/gatewayapi/route.go` (`shouldForceHTTP1Upstream`). Our EG is 1.9.0 and we set no `kubernetes.io/h2c`, BackendTrafficPolicy, or BackendTLSPolicy that would push the upstream to HTTP/2, so the upstream is already HTTP/1.1. Zero `appProtocol` occurrences exist anywhere in this repo. Becomes relevant only if HTTP/2-to-backend is ever enabled.
- [decision] Per-app `ciliumnetworkpolicy.yaml` — not needed for the envoy-internal ingress, which the `ingress-from-gateway-internal` CCNP already grants (the reference has no such CCNP layer, so they must spell the gateway out in the app CNP). Their CNP additionally admits `bazarr`, `sonarr`, `radarr`, `maintainerr`, `mumc`, `jellyplex-watched` — see the consumer follow-up above; none of those integrations are wired here yet.
- [decision] Probes — reference: `initialDelaySeconds: 0`, `periodSeconds: 10`, `timeoutSeconds: 1`, `failureThreshold: 3`. Ours: 30/30/5/5 (sonarr house pattern). Ours is deliberately more forgiving, which matters for a 12.0-rc first boot that may run DB migrations. Kept.
- [decision] Resources — reference: `requests.cpu: 100m`, NO memory request, `limits.memory: 8Gi`. Ours: 25m + 512Mi request, 4Gi limit. A memory request is mandatory per the repo resource baseline; 8Gi is not defensible on a single node that also runs plex. Kept, revisit after measurement.
- [decision] Metadata PVC — reference declares it chart-managed (`persistence.metadata.size/accessMode/storageClass/suffix`). Ours is an explicit `pvc-metadata.yaml` matching `plex-rebuildable`. Same resulting name (`jellyfin-metadata`); ours survives a HelmRelease deletion, which is the safer lifecycle.
- [decision] NFS mount shape — reference mounts a `Library` subPath at `/data/nas-media/Library`. We mount `${NAS_IP}:/media` wholesale at `/media`, matching plex/sonarr/radarr so library paths line up with the *arr import paths. Kept.
- [decision] `tmpfs` single emptyDir with cache/tmp/transcode subPaths — split into `cache` + `tmp` emptyDirs here; the transcode dir lives under `JELLYFIN_CACHE_DIR=/cache` anyway.
- [decision] Per-app `ocirepository.yaml` — the reference pins app-template 5.1.0 per app; this repo consumes the shared `components/common/repos/app-template` OCIRepository at the same 5.1.0. No per-app file needed.
- [decision] Pod `securityContext` — reference runs UID/GID 2000 with no `runAsNonRoot` and no `seccompProfile`. Ours is strictly harder (10001 + `runAsNonRoot: true` + RuntimeDefault + drop ALL + `readOnlyRootFilesystem`). Kept.
- [decision] `service.type: LoadBalancer` + `externalTrafficPolicy: Local` — dropped per the exposure decision (envoy-internal only).

## Session 2026-08-21 - CrashLoopBackOff fix (fsGroupChangePolicy Always)

### Root cause (live-proven)
The introskipper subPath mount at /config/data/introskipper (metadata PVC, nested under
the config PVC's /config/data) makes kubelet create /config/data as root-owned
(uid 0:10001, mode 0755) on the config PVC. fsGroupChangePolicy=OnRootMismatch skips the
recursive chown because the config volume root gid already matches fsGroup (10001), so
Jellyfin (uid 10001) gets only group r-x on /config/data and cannot write its
/config/data/.jellyfin-data sanity marker, raising UnauthorizedAccessException and
CrashLoopBackOff (27 restarts). Evidence: debug pod (uid 10001, no fsGroup) showed
/config/data owner=0:10001 mode=2755, and touch /config/data/.jellyfin-data was denied.

Why plex (same nested-subPath pattern) is unaffected: plex only writes INSIDE its
subPaths (Cache/Metadata/Scanners), never into the root-owned parent; Jellyfin writes the
sanity marker INTO the parent (/config/data) that the nested mount stole.

### Why the cleaner paths do not apply
Intro Skipper hardcodes its storage to {JellyfinDataPath}/introskipper/ (introskipper.db
plus chromaprints/); not configurable. So the nested mount is REQUIRED to keep the
fingerprint DB on the rebuildable jellyfin-metadata PVC. A non-nested /introskipper mount
would be ignored by the plugin (it writes to /config/data/introskipper on the config PVC
instead). JELLYFIN_DATA_DIR alone does not help (the nested mount re-creates the new data
dir as root) unless paired with a dedicated data PVC - a bigger diff than warranted.

### Fix
kubernetes/apps/media/jellyfin/app/helmrelease.yaml: fsGroupChangePolicy OnRootMismatch to
Always (1 file, +5/-1). kubelet now chmods g+rwX over the config volume tree on every
mount, making /config/data group-writable so the sanity marker writes.
debt: recursive chown per restart; move to a dedicated data PVC if startup slows.

### Live verification (post-push, commit 88cfbb544)
- Flux: git source flux-system fetched 88cfbb5444; cluster-apps applied it; HR jellyfin was
  initially Stalled (rollback-remediation "missing target release for rollback" from the
  prior crashloop), cleared via flux reconcile helmrelease jellyfin -n media --force, then
  Ready=True, Released=True, "Helm upgrade succeeded ... jellyfin.v4", history deployed(5.1.0).
- Pod: jellyfin-698d8586-r7g79 1/1 Running, 0 restart, Ready.
- Filesystem (live pod): /config/data now owner=0:10001 mode=2775 (group-writable);
  .jellyfin-data marker plus jellyfin.db (-wal/-shm) created as uid 10001:10001.
- Introskipper: plugin not yet installed; the /config/data/introskipper mount already points
  at the metadata PVC, so installing the plugin writes its hardcoded path to the rebuildable
  PVC automatically - no plugin reconfiguration needed.

### Maestro verification (independent)
Verified from the control lane, not from the worker self-report: pod 1/1 Running 0 restart,
HR Ready=True, diff is 1 file / 5 lines, origin/main = 88cfbb544, unrelated in-progress
working-tree files untouched.
