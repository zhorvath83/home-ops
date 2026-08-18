---
title: arr-config-sync
type: note
permalink: home-ops/docs/progress/arr-config-sync
tags:
- progress
- recyclarr
- sonarr
- radarr
- arr-stack
- config-sync
- closed
---

# arr-config-sync — *arr quality-config sync via Recyclarr (closed 2026-08-17)

- [type] progress-note
- [branch] feat/arr-config-sync — merged to main (PR #4193, #4195, #4196)
- [status] DONE — deployed, live-verified, sync converged; old "Any" profiles deleted from both apps; library remapped. Merged from the former roadmap + progress notes 2026-08-17.
- [area] k8s-workloads, external-secrets, networking
- [created] 2026-08-17
- [closed] 2026-08-17

## Goal

Deploy **recyclarr** as a Flux CronJob under `kubernetes/apps/downloads/recyclarr/` that declaratively syncs Sonarr/Radarr quality profiles, custom formats, quality definitions, and media naming from the TRaSH guide into the live `downloads` instances. Preserve **Hungarian-dubbed over-weighting** (HUN > quality > size) via a local CF. Enforce balanced file size (reject gigantic 4K), keep 720p/1080p as fallback. Priority: 4K > 1080p > 720p.

## Decision — Recyclarr over Profilarr (2026-08-16)

- Recyclarr (CronJob, YAML-in-git) chosen as the single config-sync owner; Profilarr evaluated and rejected. User decision 2026-08-16.
- Rejection rationale: Profilarr trades declarative config for a UI-owned SQLite state + plaintext credential store + internal HTTP surface + a single-owner TRaSH conversion-repo dependency, and its v2 line had no stable release at decision time. Recyclarr is fully declarative, rootless, no listening surface, reads TRaSH directly, native fit with the repo's UID-10001 / read-only posture.
- Re-evaluation gate for Profilarr (future): (a) publishes a major tag, (b) resumes a stable release cadence, (c) offers declarative Arr-instance bootstrap (write endpoints under `/arr`).
- Recyclarr model: CLI (`recyclarr sync`) one-shot container; desired state = `recyclarr.yml` in git; reads the TRaSH Guides repo directly; `!env_var` interpolation for secrets; state persists on a writable `/config` PVC created by the shared `components/volsync` component (VolSync/Kopia backup to OVH S3), consistent with the *arr siblings; config files are ConfigMap-subPath-projected into the PVC.

## Planning framework & priority order (governs any future change)

This framework records the CONSIDERATION FRAMEWORK used during planning — the priority order + governing principles — so a FUTURE change can be evaluated against this same framework: does it respect HUN > quality > size? does it preserve 720p/1080p fallback? does it keep the HUN invariants?

1. PRIORITY ORDER (hard): HUN dub > quality > size. The Hungarian-language release is the highest priority, ranked ABOVE quality — a HUN 720p/1080p must beat a non-HUN 4K/Remux. Size is the lowest-priority lever.
2. SIZE-vs-QUALITY GOAL: balanced — EXCLUDE gigantic 4K / huge-bitrate / huge-file releases; but do NOT blanket-exclude lower resolutions. 720p and 1080p MUST remain acceptable as fallback, because content is frequently available ONLY in those qualities.
3. REMUX / BR-DISK / LQ EXCLUSION: clean UHD Remux is undesired (size); BR-DISK (full disc images) and LQ releases are rejected via the Unwanted CF group (BR-DISK = -10000, LQ = -10000). Remux exclusion comes from the PROFILE (allowed qualities), not CFs — BR-DISK does not match clean remuxes. (The Radarr SQP Unwanted group lacks LQ/BR-DISK, so they are added explicitly as custom_formats; see the Radarr config below.)
4. BEST-PRACTICE / REFERENCE-BASED: decisions are anchored to onedr0p/home-ops + bjw-s-labs/home-ops reference repos, TRaSH-Guides, and the recyclarr upstream config-templates. Prefer recyclarr's built-in recommended config blocks over hand-rolling. Do NOT copy bjw-s's 720p-dropping qualities override.
5. PROFILE-CHOICE PRINCIPLE: SQP family for Radarr (SQP-1 2160p) + Combined for Sonarr (WEB-2160p Combined) — the quality-BALANCED presets that prefer WEB-DL, exclude remux, AND keep 1080p/720p fallback. Deliberately OPPOSED to the quality-maximizing "UHD Bluray + WEB" (Radarr) and non-Combined "WEB-2160p" (Sonarr) presets, which forbid the 720p/1080p fallback.
6. SIZE-CAP PRINCIPLE: the TRaSH quality-size default max (2000 MB/min ≈ 240 GB / 2h movie) is NON-BINDING — it does not exclude gigantic files. A real ceiling requires an explicit `quality_definition.qualities[].max` override. The ceiling applies to the TOP quality; lower qualities get proportionally lower caps. NEVER raise a `min` floor in a way that rejects 720p/1080p. (sqp-uhd has no 720p entry → 720p stays uncapped on Radarr; the Sonarr series set has 720p → capped at 50.)
7. HUN-SCORE INVARIANTS (the bounds for any future HUN-value change):
   (a) LQ/BR-DISK rejection MUST hold: HUN + (-10000) < minFormatScore. Under min_format_score 0 this gives HUN < 10000; HUN=9900 satisfies it (HUN+LQ = 9900 + (-10000) = -100 < 0, rejected). NEVER set HUN >= 10000 under min_score=0 — it would let HUN+LQ >= 0 and accept a bad (LQ) Hungarian release.
   (b) Within-HUN upgrading MUST be preserved: HUN total < cutoffFormatScore. until_score raised to +20000 on BOTH apps, so within-HUN upgrades are preserved; HUN=9900 < 20000 (OK).
   (c) HUN MUST dominate realistic non-HUN quality sums. Under the chosen option A (NO tier/HDR/audio CF groups added explicitly), the SQP-1 profile's NATIVE score-set still scores tier/release-group CFs to ~1700 (verified live 2026-08-17); HUN=9900 > 1700 dominates. If a future change adopts option B (adds tier/HDR/audio groups), re-verify the actual sqp-1-2160p score-set integers against HUN=9900 BEFORE applying — a top non-HUN combo (Tier 01 + DV + ATMOS + ...) could approach or exceed 9900 under that score set.
8. NAMING-CONVENTION PRINCIPLE: Plex + Jellyfin + Emby friendly (the community-standard TRaSH/onedr0p scheme). Folder convention matches the existing library: {Title} (Year) for movie/series folders, Season 0X for season folders. `media_naming` does NOT auto-rename existing files — it governs new downloads + manual Organize only, so the existing library is safe.
9. media_management PRINCIPLES: PROPER/REPACK only if genuinely better (doNotPrefer); upgrades WANTED (auto_unmonitor_previous_downloads = false, so cutoff upgrades keep running); monitor everything (all Sonarr / movieOnly Radarr); recycle bin OFF; hardlinks ON for storage efficiency when qBittorrent and the arr share a filesystem. (recyclarr v8 media_management schema exposes ONLY propers_and_repacks — the other fields are not syncable via recyclarr and remain UI/manual; use_hardlinks on NFS is protocol/client-dependent and NOT guaranteed — runtime-verify on the mount; if it fails the arr falls back to copy = double storage during seeding.)
10. DECLARATIVE / GitOps PRINCIPLE: recyclarr (YAML-in-git CronJob) is the single config-sync owner. Config is Git-versioned and PVC-loss-safe (re-synced from git). The first real `recyclarr sync` was preceded by a VolSync snapshot of both PVCs (delete_old_custom_formats + new profile/score writes rewrite live state) — see Rollback point.

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
- Profile: SQP-1 (2160p) `5128baeb2b081b72126bc8482b2a86a0`, `min_format_score: 0` override (profile default 1000 would reject every score-0 non-HUN release (SQP-1's native score-set still scores tier/release-group CFs to ~1700, but releases matching NO scored CF get 0); 0 keeps that score-0 720p/1080p fallback viable while HUN 9900 > 1700 still dominates). upgrade until WEB 2160p, until_score 20000.
- Quality size caps: 2160p + Bluray-2160p max 300 / pref 180; 1080p max 150 / pref 90. **No 720p entry** in sqp-uhd → 720p left at Radarr's built-in default (max 208.8 MB/min ≈ 12.5 GB/h) — sqp-uhd defines no 720p entry so recyclarr does not touch it; far looser than sqp-streaming's 85.7 MB/min cap, so large HUN 720p releases are preserved (verified live: WEBDL/WebRip-720p max=208.8).
- custom_format_groups.add: Golden Rule UHD `ff204b…` with `assign_scores_to` targeting SQP-1 (the group's compat list excludes SQP-1, so it must be forced — applies x265-no-HDR/DV -10000); Unwanted SQP `15b1cf…` (lacks LQ/BR-DISK/AV1/3D).
- Explicit custom_formats at **-10000** on SQP-1: LQ `90a6f9a2…`, LQ-Release-Title `e204b80c…`, BR-DISK `ed38b889…`, AV1 `cae4ca30…`, 3D `b8cd450c…`.
- Local HUN CF `home-ops-hungarian-language` scored **+9900** on SQP-1.

**HUN-score invariant (HUN > quality > size):** HUN +9900, LQ/BR-DISK/AV1/3D -10000. HUN+LQ = 9900 + (-10000) = -100 < 0 → a HUN-but-LQ release is rejected. min_format_score 0 keeps the score-0 non-HUN fallback viable. A HUN 720p (+9900) beats any non-HUN 4K (~0). within-HUN upgrade 9900 < 20000 preserved (720p HUN → 1080p HUN → 2160p HUN).

## Sync result (converged, no errors)

Final live `recyclarr sync` completed cleanly (zero ERR, zero CF-group skip):

- **Radarr**: 64 custom formats synced (45 new + 19 replaced); 8 quality sizes synced (sqp-uhd); SQP-1 profile created; media naming + management updated.
- **Sonarr**: 39 custom formats synced; 14 quality sizes synced (series); WEB-2160p Combined profile created; media naming + management updated.

`delete_old_custom_formats: true` removed the user's previously hand-added (non-TRaSH) custom formats during sync — the clarity goal is met declaratively. Note: recyclarr identifies profiles by trash_id, so the user's hand-created "Any" profiles (no trash_id) were left untouched beside the new synced profiles until the manual remap + deletion below.

## Manual library remap (completed in UI 2026-08-17)

recyclarr cannot reassign library items or delete empty profiles — these were one-time UI actions, now done:

1. **Radarr** — all movies reassigned from the old "Any" profile to **`[SQP] SQP-1 (2160p)`** (Movies bulk edit), 61 Collections reassigned on the Collections page, then the empty "Any" profile deleted. ✔
2. **Sonarr** — all series reassigned from the old "Any" profile to **`WEB-2160p (Combined)`**, then the empty "Any" profile deleted. ✔

## Optional / non-recyclarr-syncable settings (stay manual in *arr UI)

recyclarr v8 `media_management` schema syncs ONLY `propers_and_repacks`. These remain UI/manual (lost on PVC rebuild): `monitor_new_items` (all Sonarr / movieOnly Radarr), `auto_unmonitor_previous_downloads` (= false, so cutoff upgrades keep running), `recycle_bin` (off), `use_hardlinks` (NFS — protocol/client-dependent, NOT guaranteed; runtime-verify on the mount; fallback is copy = double storage during seeding), `delete_empty_series_folders` (Sonarr), `enable_media_info`. The 24h Delay Profile also stays manual (recyclarr does not sync delay profiles). Buildarr is a documented future option for declarative arr-settings management.

## Residual (harmless, optional cleanup)

- **4 leftover user HUN CFs, score 0** — Radarr "HUN lang", Sonarr "HUN 1080p"/"HUN 2160p"/"HUN 720p". `reset_unmatched_scores: enabled` zeroed them (they're not in `recyclarr.yml`, so their profile score was reset to 0). Functionally inert clutter; recyclarr won't delete them (no trash_id). Optional manual UI delete.
- **Option B (documented future enhancement)** — add tier/HDR/audio CF groups + raise `min_format_score` back to 1000. Per framework 7c, re-verify the actual sqp-1-2160p score-set integers against HUN=9900 BEFORE applying — a top non-HUN combo could approach/exceed 9900.

## Rollback point

Pre-sync VolSync PVC snapshots (taken before the first live sync):

- Radarr: `cfad81a28a76337854b8de229acb64df` @ 2026-08-17T20:14:14Z (491.6 MiB)
- Sonarr: `9c4a4f97a38252586592a8b11d8e967a` @ 2026-08-17T20:11:13Z (440.5 MiB)

Restore via `just volsync restore …` if a sync ever damages live state.

## Risks still relevant

- A `recyclarr sync` rewrites live Arr state (profiles, CFs, scores) → not trivially reversible from the Arr side → the VolSync snapshot above is the rollback. (The first sync succeeded; this risk applies to any future config-changing sync.)
- `!env_var` interpolation vs Flux `postBuild` substitution collision → the ConfigMap substitution-disable annotation is load-bearing; do not remove it.
- Arr API keys were copied from each app's `/config/config.xml` into 1Password → must be re-synced if a key is regenerated in the UI.
- Option B (tier/HDR/audio CF groups) is a documented future enhancement → re-verify the sqp-1-2160p score-set vs HUN=9900 BEFORE applying (framework 7c).

## Related

- relates_to [[home-ops/docs/areas/k8s-workloads]] — app shape, canonical patterns, downloads/media split
- relates_to [[home-ops/docs/areas/external-secrets]] — 1Password properties for the Arr API keys
- relates_to [[home-ops/docs/areas/networking]] — callee-side CiliumNetworkPolicy edits


## Follow-up — SQP-1 `language=Any` reconciler (2026-08-18)

### Problem (post-deploy regression on foreign-origin films)

After the 2026-08-17 deploy, manual interactive search in Radarr rejected every Hungarian release for the French film "Zodi and Téhu: Princes of the Desert" (2023) with:

> Release Rejected — Original Language (French) is wanted, but found Hungarian

This violated the HUN > quality > size goal directly: the foreign-origin films whose HUN dubs we want were hard-gated at the language layer before the HUN CF (+9900) could score them.

### Root cause (source-verified — three independent layers all default to Original)

The SQP-1 profile's `Preferred Language` was `Original` — a hard gate that runs BEFORE custom-format scoring. Three sources independently force `Original`:

1. **TRaSH guide** — `docs/json/radarr/quality-profiles/sqp-1-2160p.json` hardcodes `"language": "Original"` on the SQP-1 preset.
2. **recyclarr** — `src/Recyclarr.Cli/Pipelines/QualityProfile/UpdatedQualityProfile.cs:114-123`: language is only ever passed through from the guide resource (`ProfileConfig.GuideResource?.Language`). The v8 quality-profiles schema has no `language` property (`additionalProperties: false`), so it cannot be overridden in YAML; name-backed profiles skip the language write entirely (preserving whatever Radarr already has).
3. **Radarr** — `src/NzbDrone.Core/Profiles/Qualities/QualityProfileService.cs:263`: `GetDefaultProfile` sets `Language = Language.Original`, so any freshly-created profile (new cluster, profile recreation) also defaults to `Original`.

TRaSH's own German guide documents this exact failure: *"We choose `Any` for the language profile, as otherwise, English movies identified with German audio and vice-versa will not be grabbed."* and the Language-CF doc: *"Using language Custom Formats is not compatible with setting a preferred language in a quality profile in Radarr. You must use one or the other."* Our config violated that mutual-exclusivity rule (HUN CF + profile language=Original).

Scope: only Radarr SQP-1 (all films map to it). Sonarr is unaffected (its quality profiles have no language field).

### Decision — idempotent post-sync reconciler (not a one-shot, not a UI step)

Ruled out:
- **One-shot `kubectl`/UI flip to `Any`**: not GitOps-durable — Radarr's default is `Original`, so every fresh deploy / profile recreation silently reverts to the broken state; a one-off non-declarative step is not reproducible from git. Rejected.
- **name-backed profile + `score_set`**: schema-valid (`score_set` is independent of `trash_id`) and avoids the language write, but sacrifices guide-backed profile management (quality list, cutoff, rename tracking) AND still cannot SET `language=Any` declaratively — name-backed only preserves the existing (already-`Original`) value.

Chosen: **keep `trash_id: 5128baeb…` (full guide auto-sync) + an idempotent post-sync reconciler script that sets SQP-1 `language=Any` after every `recyclarr sync`**. This is the GitOps reconciler for the one field with no declarative path — same role Flux plays for cluster state: in-git, idempotent, converges the current profile AND every future fresh deploy. A `debt:` marker records the recyclarr upstream gap (no `language` YAML property); remove when recyclarr ships a language override (upstream feature request warranted).

### Implementation — all four TRaSH guide tenets now in effect

The guide's recipe for our case (German-DEFAULT mode: prefer dubbed + original fallback) is `profile language=Any` + dubbed CF (high positive) + `min_format_score=0` + "Not X or Original" CF (−35000). All four now in effect:

| Tenet | Guide recipe | Our config |
|---|---|---|
| 1. profile `language=Any` | mandatory (guide rule) | reconciler sets `Any` after every sync |
| 2. "Hungarian" CF, high positive | German +10000 | HUN CF +9900 (`home-ops-hungarian-language`, LanguageSpecification value 22) |
| 3. `min_format_score=0` | original accepted as fallback | `min_format_score: 0` (720p/1080p fallback preserved) |
| 4. "Not Hungarian or Original" CF −35000 | "Not German or English" −35000 | new local CF `home-ops-not-hungarian-or-original` (3-spec negate, mirrors TRaSH "Not German or English") — blocks 3rd-language dubs, only HUN + Original accepted |

Files (branch `feat/arr-config-sync`):
- `kubernetes/apps/downloads/recyclarr/app/config/recyclarr.yml` — added the 4th CF (`assign_scores_to` SQP-1, score −35000); `trash_id` for SQP-1 kept.
- `kubernetes/apps/downloads/recyclarr/app/config/custom-formats/radarr/not-hungarian-or-original.json` — new local CF (LanguageSpecification negate value 22 + value −2; ReleaseTitleSpecification regex \`(?i)\\b(hungarian|hun|magyar)\\b\`).
- `kubernetes/apps/downloads/recyclarr/app/config/scripts/fix-radarr-language.sh` — the reconciler. Idempotent: GET `/api/v3/qualityProfile`, find SQP-1 by name, PUT `language={id:-1,name:Any}` via bash `/dev/tcp` (no curl/jq in the Alpine image), read-back verify. Runs after every `recyclarr sync`.
- `kubernetes/apps/downloads/recyclarr/app/helmrelease.yaml` — container `command: [/sbin/tini, --, /bin/sh, -c]` + `args: [recyclarr sync && bash /config/fix-radarr-language.sh]` (tini is the image's own ENTRYPOINT init, Dockerfile-verified); new CF + script added to the `config-files` ConfigMap projection.
- `kubernetes/apps/downloads/recyclarr/app/kustomization.yaml` — added the new CF + script to `configMapGenerator`.

### Verification (live, end-to-end against the real Radarr API)

- Radarr 6.4.1.10545; SQP-1 = profile id 7; `language=Any` = language id **−1** (verified live via `GET /api/v3/language`, not assumed).
- Image `ghcr.io/recyclarr/recyclarr:8.7.1` has no `curl`/`jq`/`python3`; the script uses BusyBox `wget` (GET) + bash `/dev/tcp` (PUT) — the only reliable PUT path in that image.
- Live test: `PUT /api/v3/qualityProfile/7` → 202; read-back → `language=Any`. Full reconciler logic proven against the real API in a debug pod (temporarily labelled `app.kubernetes.io/name=recyclarr` to satisfy the Cilium CNP, then cleaned up).
- Local validation: `shellcheck -x` clean; `yamllint` exit 0 on the 3 touched YAMLs; `yamlfmt --dry` no changes; `jq` valid on both CF JSONs.
- Transient: the live SQP-1 is currently `Any` (from the test); without deploying the new config the next `@daily` recyclarr sync would revert it to `Original` within 24h. Deploying the new config makes the reconciler self-heal `Any` on every sync.

### Debt

- `fix-radarr-language.sh` carries a `debt:` marker: recyclarr v8 has no `quality_profile.language` YAML override; guide-backed SQP-1 gets `language=Original` (TRaSH guide) and Radarr's own default is `Original` (`QualityProfileService.cs:263`), so there is no declarative path to `language=Any`. Remove the script + helmrelease command wrapper when recyclarr ships a language YAML override (upstream feature request warranted).


## Follow-up — configMapGenerator envsubst build-fix (2026-08-18)

The reconciler script added to the `recyclarr-config` configMapGenerator broke the Flux Kustomization build on first deploy (main `3ef09eafd`): `FluxKustomizationBuildFailed` — `envsubst error: variable not set (strict mode): "RADARR_HOST"`. The build never applied, so the new CM (script + 4th CF) was stuck and `lastApplied` stayed at the pre-reconciler revision (`9bbd02d1e`).

### Root cause

- Flux runs its OWN envsubst (`fluxcd/pkg/envsubst/template.go`), strict by default: a bare `${VAR}` not in the substitute map errors; only default-providing operators (`${VAR:-default}` and `:- :+ := :? - + = ?`) are exempt.
- The script uses bare shell `${VAR}` (`${RADARR_HOST}`, `${RADARR_PORT}`, `${profile_id}`, `${tmp}`, …) — runtime shell vars, not Flux substitution vars — so every one is a strict-mode landmine; the first (`${RADARR_HOST}`) failed the build.
- The qbittorrent `qbittorrent-scripts` ConfigMap carries the same shell `${VAR}` pattern and builds fine because its `generatorOptions` sets `annotations: kustomize.toolkit.fluxcd.io/substitute: disabled`, which tells Flux envsubst to skip that ConfigMap. The recyclarr configMapGenerator was missing this annotation — the precedent was not followed.

### Fix

`kubernetes/apps/downloads/recyclarr/app/kustomization.yaml` `generatorOptions` gained:

```yaml
  annotations:
    kustomize.toolkit.fluxcd.io/substitute: disabled  # scripts carry shell ${VAR}; skip Flux envsubst
```

Commit `62672814e` on `main` (per user instruction, committed directly to main + pushed). Pre-commit hooks green (yamlfmt aligned the comment). No other change needed — no non-script file in `recyclarr-config` uses Flux `${VAR}` substitution (the `!env_var` tags are recyclarr-native).

### Verification (live, read-only kubectl)

- `recyclarr` Kustomization `Ready=True`, `lastApplied=refs/heads/main@sha1:62672814e`.
- Applied `recyclarr-config` CM now has all 6 keys incl. `fix-radarr-language.sh` + `radarr-not-hungarian-or-original.json`, carries the `substitute: disabled` annotation, and the script's `${RADARR_HOST}` is literal (4 occurrences) — envsubst skipped it.
- `onepassword-connect` dependency `Ready=True`; the transient "dependency not ready" was a mid-reconcile state.
- `FluxKustomizationBuildFailed` alert clears (Ready False → True).

### Lesson (durable)

Script (shell `${VAR}`) embedded in a Flux-substituted configMapGenerator → always annotate the ConfigMap with `kustomize.toolkit.fluxcd.io/substitute: disabled` (qbittorrent precedent). Flux envsubst is strict on bare `${VAR}`; `${VAR:-default}` is exempt. This fix is orthogonal to the existing `debt:` marker in `fix-radarr-language.sh` (which tracks the recyclarr language-YAML-override gap, still open).
