---
title: jellyfin
type: note
permalink: home-ops/docs/progress/jellyfin
---

# jellyfin — execution progress

## Metadata (observation-form)

- [type] progress-note
- [topic] Jellyfin 12.0-rc5 media server alongside plex in the media namespace, with Introskipper support
- [status] IN PROGRESS — manifests written, rendered and linted locally; NOT yet deployed (PR open, awaiting merge + Flux reconcile)
- [branch] feat/jellyfin
- [area] k8s-workloads, networking, volsync-backup
- [created] 2026-08-20
- [reference] bjw-s-labs/home-ops kubernetes/apps/media/jellyfin (helmrelease.yaml + ks.yaml)
- [relates_to] [[k8s-workloads]]
- [relates_to] [[networking]]

## Decisions (with the human, 2026-08-20)

- [decision] **Image**: `ghcr.io/jellyfin/jellyfin:12.0-rc5@sha256:669d234c776a37b331d875f58246434f80dbbbb619fa7edef55ce26d187baa2c` — explicitly requested pre-release (Jellyfin 12 RC). Digest resolved from the ghcr manifest list. Renovate needs no extra config: every `automerge` rule in `.renovate/autoMerge.json5` is `false`, so an rc6 bump arrives as a reviewable PR.
- [decision] **Exposure**: `envoy-internal` HTTPRoute ONLY (`jellyfin.${PUBLIC_DOMAIN}`), **no LoadBalancer service**. Deliberately different from both the reference (which adds an LB IP) and plex (LB-only, no route). No `JELLYFIN_IP` cluster-setting was added.
- [decision] **No OIDC gate**: `components/gateway-oidc` deliberately NOT attached — the Envoy OIDC redirect breaks native Jellyfin clients (Android TV, iOS). Jellyfin's own auth is the boundary; acceptable because the route is internal-only.
- [decision] **GPU**: the node advertises exactly ONE `gpu.intel.com` device (`0000-00-02-0-0x9bc5`, `allowMultipleAllocations: None`), and plex's DRA claim held it. Human chose to **hand the iGPU to jellyfin**; plex loses hardware transcode. The alternative (one shared `ResourceClaim` in the `media` namespace referenced by both pods via `resourceClaimName`, which DRA's `reservedFor` permits) was surfaced and not taken.
- [decision] **Egress deviation from the discussed FQDN allowlist**: implemented as `egress.home.arpa/allow-world: "true"` (the `allow-world-egress` CCNP), NOT a per-app `toFQDNs` CNP. Rationale: a media server needs metadata providers (TMDB/TVDB image CDNs) on top of the plugin catalog, and every close sibling in the same class (plex, sonarr, radarr) uses `allow-world`. An FQDN allowlist would be a fragile, high-maintenance list. Consequence: no per-app `ciliumnetworkpolicy.yaml` exists for jellyfin at all — ingress is the `ingress-from-gateway-internal` CCNP, egress the `allow-world-egress` CCNP.
- [decision] **Storage split**: config PVC (`jellyfin`, 5Gi, VolSync-backed) + separate `jellyfin-metadata` PVC (10Gi, deliberately NOT backed up) carrying `/metadata` (library artwork) and `/config/data/introskipper` (fingerprint DB). Mirrors the plex `plex` + `plex-rebuildable` split and the reference's metadata PVC.
- [decision] **Introskipper**: plugin installation is unavoidably a manual UI step (there is no GitOps plugin installer). GitOps prepares the mount + the internet egress; the human installs from the plugin catalog. Human also chose to include the **File Transformation** plugin (optional web-UI enhancements).

## What was implemented

New app `kubernetes/apps/media/jellyfin/`:

- `ks.yaml` — components `gpu` + `volsync` + `zeroscaler`; dependsOn `onepassword-connect`, `democratic-csi`, `intel-gpu-resource-driver`; `postBuild.substitute`: `APP: jellyfin`, `VOLSYNC_CAPACITY: "5Gi"`; `targetNamespace: media`
- `app/helmrelease.yaml` — app-template 5.1.0 via the shared OCIRepository, `defaultPodOptions` style (NOT the reference's app-template v4 `controllers.x.pod` syntax); UID/GID/fsGroup 10001 (repo default, matches the VolSync mover); `readOnlyRootFilesystem: true`, drop ALL caps, seccomp RuntimeDefault; `/health` probes on 8096 with `startup: disabled` (sonarr pattern); `JELLYFIN_PublishedServerUrl` = the internal route URL; resources 25m CPU / 512Mi request, 4Gi memory limit
- `app/pvc-metadata.yaml` — `jellyfin-metadata`, 10Gi, `democratic-csi-local-hostpath`
- `app/kustomization.yaml` — pvc-metadata + helmrelease (no ExternalSecret: jellyfin needs no bootstrap secret; the VolSync ES comes from the component)
- `kubernetes/apps/media/kustomization.yaml` — jellyfin ks.yaml registered

Plex change (separate commit `8fbb42332`):

- `plex/ks.yaml` — removed `components/gpu` and the `intel-gpu-resource-driver` dependsOn
- `plex/app/helmrelease.yaml` — removed `defaultPodOptions.resourceClaims` and `resources.claims`

Mounts that differ from the reference by intent:

- `/cache` emptyDir instead of a separate `/transcode` volume — `JELLYFIN_CACHE_DIR=/cache` (from the image config) already holds the transcode working directory, so a second volume plus a UI path change would be redundant
- `DOTNET_SYSTEM_IO_DISABLEFILELOCKING` omitted — the reference needs it for config on network storage; ours is a local-hostpath PVC

## Verification (local, pre-deploy)

- [verified] `yamllint` + `yamlfmt -lint` clean on all new/touched files
- [verified] `pre-commit run --files …` — all applicable hooks Passed (gitleaks, yamlfmt, yamllint, secret check)
- [verified] `flux-local test --all-namespaces --enable-helm --path kubernetes/flux/cluster` → **134 passed** (0 failed). Note: must run with `dangerouslyDisableSandbox` — inside the Bash sandbox every `helm template` OCI pull fails with the known Go TLS error `x509: OSStatus -26276`, which is environmental and unrelated to the change.
- [verified] Rendered Deployment carries `resourceClaims: [{name: gpu, resourceClaimTemplateName: jellyfin-gpu}]`, `resources.claims: [{name: gpu}]`, all six volumeMounts (`/cache`, `/config`, `/metadata`, `/config/data/introskipper`, `/media`, `/tmp`), and the two CCNP labels
- [verified] Rendered `ResourceClaimTemplate jellyfin-gpu` exists; `plex-gpu` is gone from the build output and the plex Deployment has no GPU claim
- [verified] Rendered HTTPRoute: single `envoy-internal/https` parentRef, hostname `jellyfin.horvathzoltan.me`, Homepage annotations (group `Media`, icon `jellyfin.svg`)
- [verified] Introskipper supports Jellyfin 12 — the upstream repo ships a dedicated `12.0/v1.12.0.1` release track next to `10.11`; manifest URL `https://intro-skipper.org/manifest.json` is version-aware and returns the right build per server version
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
- [task] If `seerr` should drive jellyfin (it currently targets plex), jellyfin will need a per-app CNP admitting `downloads/seerr` on 8096 — jellyfin has no CNP today.
- [task] Update BM `docs/areas/k8s-workloads` after deployment: media namespace grows to 5 apps, and the "Plex GPU wiring" component claim becomes a jellyfin claim.
- [task] Sizing is estimated from plex, not measured — revisit `requests.memory: 512Mi` / `limits.memory: 4Gi` and the 10Gi metadata PVC once the library is scanned.
- [task] 12.0-rc5 is a pre-release. Watch for plugin ABI churn on rc bumps; Renovate PRs are review-gated, not auto-merged.
