---
title: arr-config-sync
type: note
permalink: home-ops/docs/progress/arr-config-sync
---

# arr-config-sync — execution progress

- [type] progress-note
- [branch] feat/arr-config-sync — merged to main
- [roadmap] home-ops/docs/roadmap/arr-config-sync
- [status] DONE — deployed, live-verified, sync converged. Manual library remap (UI) remains.
- [area] k8s-workloads, external-secrets, networking
- [created] 2026-08-17
- [closed] 2026-08-17
- [implements] [[home-ops/docs/roadmap/arr-config-sync]]

## Goal

Deploy **recyclarr** as a Flux CronJob under `kubernetes/apps/downloads/recyclarr/` that declaratively syncs Sonarr/Radarr quality profiles, custom formats, quality definitions, and media naming from the TRaSH guide into the live `downloads` instances. Preserve **Hungarian-dubbed over-weighting** (HUN > quality > size) via a local CF. Enforce balanced file size (reject gigantic 4K), keep 720p/1080p as fallback. Priority: 4K > 1080p > 720p.

## Final deployed state (live, verified)

**recyclarr CronJob** — `kubernetes/apps/downloads/recyclarr/`, Flux-managed, image `ghcr.io/recyclarr/recyclarr:8.7.1` (digest-pinned), bjw-s app-template chart. @daily schedule, hardened (UID 10001, readOnlyRootFilesystem, drop ALL, seccomp RuntimeDefault). `args: [sync]`, `RECYCLARR_DATA_DIR: /tmp` emptyDir. Pod label `egress.home.arpa/allow-world: "true"` (AD-023 — gates internet egress behind the `allow-world-egress` CCNP for the TRaSH-Guides git clone). Config `/config` writable PVC (VolSync-backed) with ConfigMap-projected config files subPath-mounted in.

**Secret delivery** — ExternalSecret `recyclarr-secret` from the `onepassword-connect` ClusterSecretStore (1PW items `radarr`/`sonarr` → `RADARR_API_KEY`/`SONARR_API_KEY`), env `secretKeyRef` in the container.

**Network policy** — existing callee-side CiliumNetworkPolicies on radarr (7878) + sonarr (8989) admit recyclarr via `fromEndpoints` (namespace `downloads`, name `recyclarr`). In-cluster egress to the *arr svc FQDNs is NOT label-gated (`allow-cluster-egress` CCNP).

**Backup** — `/config` PVC via the shared `components/volsync` component (VolSync + Kopia → OVH S3), hourly `0 * * * *`, mover UID 10001. Matches the *arr siblings' backup pattern.

## recyclarr.yml — final config

**Sonarr (`series`, quality_definition type `series`):**
- Profile: WEB-2160p (Combined) `c4cadd6b35b95f62c3d47a408e53e2f7` with 720p re-enabled as fallback (Combined disables it by design). upgrade until WEB 2160p, until_score 20000.
- Quality size caps (MB/min, preferred ~60% of max): 2160p max 200 / pref 120; 1080p max 100 / pref 60; 720p max 50 / pref 30.
- custom_format_groups.add: Golden Rule UHD `e3f375…`, Language Profiles `74aff4…`, Streaming HD/UHD boost `85fae4…`, Unwanted `59c3af…` (carries LQ/BR-DISK/AV1 natively).
- Local HUN CF `home-ops-hungarian-language` (LanguageSpecification value 22) scored **+9900** on the Combined profile.

**Radarr (`movies`, quality_definition type `sqp-uhd`):**
- Profile: SQP-1 (2160p) `5128baeb2b081b72126bc8482b2a86a0`, `min_format_score: 0` override (profile default 1000 would reject every non-HUN release — no tier CF groups are added; 0 restores the 720p/1080p fallback). upgrade until WEB 2160p, until_score 20000.
- Quality size caps: 2160p + Bluray-2160p max 300 / pref 180; 1080p max 150 / pref 90. **No 720p entry** in sqp-uhd → 720p left at Radarr's built-in default (max 208.8 MB/min ≈ 12.5 GB/h) — sqp-uhd defines no 720p entry so recyclarr does not touch it; far looser than sqp-streaming's 85.7 MB/min cap, so large HUN 720p releases are preserved (verified live: WEBDL/WebRip-720p max=208.8).
- custom_format_groups.add: Golden Rule UHD `ff204b…` with `assign_scores_to` targeting SQP-1 (the group's compat list excludes SQP-1, so it must be forced — applies x265-no-HDR/DV -10000); Unwanted SQP `15b1cf…` (lacks LQ/BR-DISK/AV1/3D).
- Explicit custom_formats at **-10000** on SQP-1: LQ `90a6f9a2…`, LQ-Release-Title `e204b80c…`, BR-DISK `ed38b889…`, AV1 `cae4ca30…`, 3D `b8cd450c…`.
- Local HUN CF `home-ops-hungarian-language` scored **+9900** on SQP-1.

**HUN-score invariant (HUN > quality > size):** HUN +9900, LQ/BR-DISK/AV1/3D -10000. HUN+LQ = 9900 + (-10000) = -100 < 0 → a HUN-but-LQ release is rejected. min_format_score 0 keeps the score-0 non-HUN fallback viable. A HUN 720p (+9900) beats any non-HUN 4K (~0). within-HUN upgrade 9900 < 20000 preserved (720p HUN → 1080p HUN → 2160p HUN).

## Sync result (converged, no errors)

Final live `recyclarr sync` completed cleanly (zero ERR, zero CF-group skip):

- **Radarr**: 64 custom formats synced (45 new + 19 replaced); 8 quality sizes synced (sqp-uhd); SQP-1 profile created; media naming + management updated.
- **Sonarr**: 39 custom formats synced; 14 quality sizes synced (series); WEB-2160p Combined profile created; media naming + management updated.

`delete_old_custom_formats: true` removed the user's previously hand-added (non-TRaSH) custom formats during sync — the clarity goal is met declaratively.

## Manual steps remaining (UI, not GitOps-managed)

recyclarr cannot reassign library items or delete empty profiles — these are one-time UI actions:

1. **Radarr** — reassign existing movies from the old manual profile to **`[SQP] SQP-1 (2160p)`** (Movies → Filter → select all → Edit → Profile), then delete the now-empty old profile.
2. **Sonarr** — reassign existing series from the old profile to **`WEB-2160p (Combined)`**, then delete the now-empty old profile.

Optional, non-recyclarr-syncable settings (recyclarr v8 media_management schema is `propers_and_repacks` only) stay manual in the *arr UI: `monitor_new_items`, `auto_unmonitor_previous_downloads`, `recycle_bin`, `use_hardlinks`, `delete_empty_series_folders`, `enable_media_info`. The 24h Delay Profile also stays manual (recyclarr does not sync delay profiles).

## Rollback point

Pre-sync VolSync PVC snapshots (taken before the first live sync):

- Radarr: `cfad81a28a76337854b8de229acb64df` @ 2026-08-17T20:14:14Z (491.6 MiB)
- Sonarr: `9c4a4a97a38252586592a8b11d8e967a` @ 2026-08-17T20:11:13Z (440.5 MiB)

Restore via `just volsync restore …` if a sync ever damages live state.

## Relations

- implements [[home-ops/docs/roadmap/arr-config-sync]]
- relates_to [[home-ops/docs/areas/k8s-workloads]]
- relates_to [[home-ops/docs/areas/external-secrets]]
