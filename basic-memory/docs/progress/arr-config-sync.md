---
title: arr-config-sync
type: note
permalink: home-ops/docs/progress/arr-config-sync
---


# arr-config-sync — execution progress

- [type] progress-note
- [branch] feat/arr-config-sync
- [roadmap] home-ops/docs/roadmap/arr-config-sync
- [status] in-progress
- [area] k8s-workloads, external-secrets
- [created] 2026-08-17

## Goal

Deploy **recyclarr** as a Flux CronJob under `kubernetes/apps/downloads/recyclarr/` that syncs Sonarr/Radarr quality profiles + custom formats (and naming/media-management) from the TRaSH guide into the live `downloads` instances, declaratively from GitOps. Preserve the **Hungarian-dubbed (magyar szinkron) over-weighting** that currently lives out-of-band in the live instances.

## Decisions (Maestro, 2026-08-16/17)

- **Engine**: recyclarr (not Profilarr). User decision.
- **Hungarian over-weighting** (both Sonarr + Radarr, GitOps): a LOCAL custom format with `LanguageSpecification`, `fields.value: 22` (Hungarian language ID, stable), loaded via recyclarr `resource_providers` (settings.yml + per-service JSON CF files), assigned a HIGH positive score in the quality profile. Quality-profile `language` field is NOT manually settable in recyclarr YAML → scored CF is the uniform path. Logic: `magyar 4K > magyar 1080p > nem-magyar 4K > nem-magar 1080p` (Hungarian dominates quality, but 4K still leads within Hungarian).
- **Base presets**: Sonarr `WEB-2160p` (trash_id `d1498e7d189fbe6c7110ceaabb7473e6`); Radarr `UHD Bluray + WEB 2160p`. User wants 4K preferred but balanced file size (not huge UHD remux), 1080p/720p not excluded (fallback).
- **Radarr size-tuning** (Slice D3, Maestro ratify): prefer WEB-2160p over UHD-BluRay-remux within the profile (quality ordering / CF scores) for balanced size.
- **24h Delay Profile stays MANUAL** (out-of-band, UI) — recyclarr does NOT sync delay profiles (verified: sync pipelines are CF/QualityProfiles/QualitySizes/MediaNaming/MediaManagement only). Documented exception; one-time stable setting.
- Current (sub-optimal) profiles are NOT preserved wholesale — fresh config built from guide presets + Hungarian CF (user: "nem a legjobbak").

## Slices — done + Maestro-verified

- **Slice A — app skeleton**: `ks.yaml`, `app/{kustomization,helmrelease}.yaml`. DEVIATION (ratified): NO per-app `ocirepository.yaml` — app-template OCIRepository is shared via `components/common/repos/app-template` (sonarr/radarr use the same). HelmRelease minimal-spec (chartRef/interval/values only). CronJob @daily, image recyclarr:8.7.1 digest-pinned, hardened securityContext (UID 10001, readOnlyRootFilesystem, drop ALL), `RECYCLARR_DATA_DIR: /tmp` emptyDir. Verified: kustomize build green, yamllint green, no dangling refs.
- **Slice B — ExternalSecret + env**: `app/externalsecret.yaml` (ClusterSecretStore onepassword-connect, target `recyclarr-secret`, data: 1PW item `radarr`/`radarr_api_key` → `RADARR_API_KEY`, `sonarr`/`sonarr_api_key` → `SONARR_API_KEY`); helmrelease env `SONARR_API_KEY`+`RADARR_API_KEY` via secretKeyRef to `recyclarr-secret`; kustomization resources updated. Verified: kustomize build green, yamllint green, refs consistent.
- **Slice D1 — Hungarian local CF**: `app/config/settings.yml` (resource_providers sonarr+radarr → `/config/custom-formats/{sonarr,radarr}`); `app/config/custom-formats/{sonarr,radarr}/hungarian.json` (`trash_id: home-ops-hungarian-language`, LanguageSpecification value 22, required). Verified: yamllint 0, json ok, NOT in kustomization, kustomize build unchanged.

## Next slices (after checkpoint /clear)

- **D2 — preset include files**: fetch `sonarr/templates/web-2160p.yml` + `radarr/templates/uhd-bluray-web.yml` from recyclarr/config-templates repo → save as `app/config/includes/{sonarr-web-2160p,radarr-uhd-bluray-web}.yml`. Not in kustomization.
- **D3 — recyclarr.yml** (Maestro ratify on score + Radarr tuning): instances (base_url internal svc, api_key `!env_var`, delete_old_custom_formats true), `include` the preset files, custom_formats referencing `home-ops-hungarian-language` with high score assign_scores_to the profile, Radarr size-tuning, quality_definition.
- **D4 — config mount**: ConfigMap from `app/config/` → mount in cronjob at `/config`; set recyclarr config-discovery (recyclarr.yml + settings.yml path, env/arg); wire kustomization; CNP (sonarr/radarr callee-side egress for recyclarr) deferred to Slice E.

## Open / ratify-gates

- D3: Hungarian CF score value (recommend high, e.g. +1000, to dominate quality differential) — Maestro ratify.
- D3: Radarr WEB-2160p-over-remux tuning specifics — Maestro ratify.
- Optional: light live recon to confirm Hungarian=22 in the running instances (not required; 22 is stable).
- No commit yet — files on branch feat/arr-config-sync, uncommitted. Commit at checkpoint/session-end (worker does the commit; Maestro does not).

## Maestro-side correction

2026-08-16 `write_note(overwrite:true)` accidentally clobbered the pre-existing 368-line roadmap note (docs/roadmap/arr-config-sync). Recovered from main via git checkout; session additions re-appended properly. BM safety protocol: "Updated note" ⇒ STOP, never overwrite blind.

## Relations

- implements [[home-ops/docs/roadmap/arr-config-sync]]
- relates_to [[home-ops/docs/areas/k8s-workloads]]
- relates_to [[home-ops/docs/areas/external-secrets]]


## Session 2026-08-17 — all code slices delivered + Maestro-verified (GitOps complete)

### Slices done + independently verified (verify-don't-trust)

- **D2 — preset include files**: fetched upstream `config-templates` sonarr/radarr presets verbatim. **SUPERSEDED + deleted in D3** — verify-don't-trust caught that those files are FULL-schema templates (`sonarr: web-2160p:` wrapper + `base_url`/`api_key` placeholders, the input to `recyclarr config create`), NOT valid `include: config:` files (which expect the instance-level, wrapper-less form). Decision: switch D3 to direct declaration, drop the include mechanism entirely. The `app/config/includes/` directory was deleted.
- **D3 — recyclarr.yml** (direct declaration, no includes): Sonarr WEB-2160p (`trash_id d1498e7d...`) + Radarr UHD Bluray+WEB (`trash_id 64fb5f98...`) guide-backed profiles; `custom_format_groups.add` = the preset's uncommented active groups (4 sonarr: Golden Rule UHD / Language Profiles / Streaming HD-UHD boost / Unwanted; 2 radarr: Golden Rule UHD / Unwanted); local Hungarian CF (`home-ops-hungarian-language`) scored **+1000** on each profile; `delete_old_custom_formats: true`; `quality_definition` type-only (TRaSH guide DEFAULT sizes). Wrote byte-identical to brief; `includes/` deleted; yamllint 0; not in any kustomization resources.
- **D4 — config mount**: `app/kustomization.yaml` — `configMapGenerator` (`recyclarr-config`, 4 files: recyclarr.yml, settings.yml, sonarr-hungarian.json, radarr-hungarian.json) + `generatorOptions.disableNameSuffixHash: true`. `app/helmrelease.yaml` — `persistence.config-files` (configMap + globalMounts/subPath) projecting the 4 flat ConfigMap keys to `/config/{recyclarr.yml,settings.yml,custom-formats/sonarr/hungarian.json,custom-formats/radarr/hungarian.json}`; `tmp` emptyDir kept (RECYCLARR_DATA_DIR=/tmp). `args: [sync]` unchanged. Verified: kustomize build generates the ConfigMap (name `recyclarr-config` no hash) with all 4 keys + embedded content (home-ops-hungarian-language, resource_providers, recyclarr.yml header all present in render); 4 subPath mounts present; parent build OK.
- **E — CNP admission**: edited the two EXISTING callee-side CNPs (sonarr port 8989, radarr port 7878) — added a 4th `fromEndpoints.matchLabels` block (`k8s:io.kubernetes.pod.namespace: downloads` + `app.kubernetes.io/name: recyclarr`) after seerr; updated header comments to list recyclarr. Verified: both CNPs now 4 fromEndpoints (bazarr/prowlarr/seerr/recyclarr), recyclarr block labels correct, toPorts + endpointSelector intact; kustomize build OK for sonarr/radarr/downloads; pre-commit green (yamlfmt/yamllint/gitleaks passed, nothing reformatted). No recyclarr egress CNP needed — no policy selects its pod → Cilium default-allow egress.

### Ratified decisions this session

- **Max release size**: accept TRaSH guide defaults — the prior ~11GB/hour custom cap is NOT replicated (user decision 2026-08-17). recyclarr Quality Sizes pipeline would have honored a `quality_definition.qualities[].max` override (MB/min, runtime-normalized; 11GB/h ≈ 183 MB/min), but the guide default is preferred over a custom override.
- **Hungarian CF score**: **+1000** (user decision) — strongly over-weights Hungarian-dubbed releases against the quality differential, preserving the existing intent.
- **No-include approach**: direct declaration in recyclarr.yml (preset group selections inlined) instead of `include: config:` — forced by the wrapper-mismatch D2 finding.

### Open design assumption (not locally testable)

- recyclarr image default config location = `/config` (bjw-s reference runs `sync` with no `--config`, mounts at /config; settings.yml auto-discovered in the same dir). **If a first run reports "config not found", the one-line fix is `args: [sync, --config, /config/recyclarr.yml]`.** Documented here; not applied.

### Branch state

- All code slices (A, B, D1, D3, D4, E) done + Maestro-verified. Files on `feat/arr-config-sync`, UNCOMMITTED.
- `git status --short`: modified roadmap.md, downloads/kustomization.yaml, sonarr+radarr CNPs; untracked: recyclarr/ tree + progress/.
- No commit, no push, no PR yet — Maestro does not commit (worker's lane). **Awaiting user decision: commit (code + docs) + push + open PR. Merge to main = Flux reconcile = deploy → user-gated separately.**

### Next

- User decision on commit + push + draft PR. After approval, worker runs commit-doc-commit (code commit → this progress note already updated by Maestro via BM MCP → docs commit `git add basic-memory/`) + push + open PR (draft). Merge is terminal and user-gated.
## Implementation decisions (2026-08-17) — spec-driven recyclarr.yml rewrite

Context: the prior recyclarr.yml (Sonarr WEB-2160p `d1498e7d…` / Radarr UHD Bluray+WEB `64fb5f98…`, HUN +1000, TRaSH default quality sizes) was reviewed and found not to enforce the user's goals (exclude gigantic 4K, keep 720p/1080p fallback, HUN > quality > size). A closed spec was ratified and implemented. recyclarr.yml is rewritten in place; hungarian.json + settings.yml are UNCHANGED (verified: pure LanguageSpecification value 22, score lives in recyclarr.yml). All changes UNCOMMITTED, local-only, awaiting review + commit + first-sync (with a VolSync snapshot of the radarr/sonarr PVCs first).

### Radarr — SQP-1 (2160p) on sqp-uhd size set
- quality_definition.type: `sqp-uhd` (was `movie`). Profile SQP-1 (2160p) `5128baeb2b081b72126bc8482b2a86a0` (was UHD Bluray+WEB `64fb5f98…`).
- Profile (TRaSH JSON, verified): allows Bluray-2160p, WEB 2160p, Bluray|WEB-1080p (incl. WEBDL-720p, WEBRip-720p), Bluray-720p → 720p/1080p fallback PRESERVED; excludes Remux-2160p, BR-DISK, HDTV, low-res. cutoffFormatScore 10000, minFormatScore 1000, upgradeAllowed true, trash_score_set `sqp-1-2160p`.
- upgrade.allowed: true + until_score: 20000 (override cutoff → enables within-HUN upgrades 720p→1080p→2160p; HUN total 10000 < 20000).
- Hard size caps (quality_definition.qualities[].max, MB/min): WEBDL-2160p / WEBRip-2160p / Bluray-2160p = 300; WEBDL-1080p / WEBRip-1080p = 150. DEFAULTS were 2000 for all (non-binding — did NOT exclude gigantic files). 720p has NO entry in the sqp-uhd size set → uncapped (acceptable: 720p is the small fallback; capping it risks rejecting the only available release). DEVIATION from spec's "720p:80" — impossible to express, documented.
- custom_format_groups: Golden Rule UHD `ff204b…` (x265-HD blockers) + Unwanted SQP `15b1cf…` (was regular Unwanted `a3ac6af…`).
- LQ/BR-DISK added EXPLICITLY as custom_formats (LQ `90a6f9a2…`, LQ Release Title `e204b80c…`, BR-DISK `ed38b889…`, score -10000 → SQP-1 profile): the SQP Unwanted group `15b1cf…` LACKS LQ/BR-DISK (verified), so without this the junk-rejection invariant would not hold.
- HUN `home-ops-hungarian-language` score +10000 → SQP-1 profile (was +1000).
- min_format_score: 0 OVERRIDE (profile default 1000). DEVIATION, load-bearing: with only Golden Rule + Unwanted SQP groups (no tier/HDR/audio groups, per spec), legitimate non-HUN releases score 0 < 1000 → ALL non-HUN would be rejected, breaking the 720p/1080p fallback. Lowering to 0 restores fallback. Tradeoff: loses SQP tier-based quality ranking (bad-group vs good-group 4K WEB-DL score equally); the hard cap + quality order + HUN still meet the stated goals. To restore pure SQP ranking later, add tier/HDR/audio groups (release-groups-hq, audio-formats, hdr-formats-*, required-repack-proper, optional-resolutions) and set min_format_score back to 1000.
- media_management: `propers_and_repacks: do_not_prefer` ONLY. DEVIATION: spec requested recycle_bin / use_hardlinks / monitor_new_items / enable_media_info / auto_unmonitor_previous_downloads / delete_empty_series_folders — NONE exist in the recyclarr v8 media-management schema (additionalProperties:false; only propers_and_repacks). Verified against https://schemas.recyclarr.dev/v8/config/media-management.json . use_hardlinks is a Radarr UI setting not exposed by recyclarr; the qbit/radarr/sonarr shared NFS /media mount makes hardlinks work regardless.
- media_naming: folder plex-imdb, movie {rename: true, standard: plex-imdb} (onedr0p verbatim).

### Sonarr — WEB-2160p (Combined) on series size set
- quality_definition.type: `series` (unchanged). Profile WEB-2160p (Combined) `c4cadd6b35b95f62c3d47a408e53e2f7` (was non-Combined WEB-2160p `d1498e7d…`).
- Profile (TRaSH JSON, verified): allows WEB 2160p + WEB 1080p; DISABLES WEB 720p, Bluray, Remux, HDTV. minFormatScore 0, cutoffFormatScore 10000, cutoff "WEB 2160p", no trash_score_set (default scores).
- qualities OVERRIDE (replaces the profile quality list): WEB 2160p > WEB 1080p > WEB 720p (all enabled) — RE-ENABLES 720p as fallback (phase-2 hard requirement; Combined disables it by design). upgrade.until_quality: "WEB 2160p", until_score: 20000. Tradeoff: hardcoded quality list does not track future guide updates to the Combined profile.
- Hard size caps (series set, unlike sqp-uhd, HAS 720p): WEBDL-2160p / WEBRip-2160p = 200; WEBDL-1080p / WEBRip-1080p = 100; WEBDL-720p / WEBRip-720p = 50 (defaults 1000).
- custom_format_groups: kept the 4 (Golden Rule UHD `e3f375…`, Language Profiles `74aff4…`, Streaming HD/UHD boost `85fae4…`, Unwanted `59c3af…`). The Sonarr Unwanted group `59c3af…` INCLUDES LQ/BR-DISK and lists WEB-2160p (Combined) in its include → junk rejection already covered (no explicit LQ/BR-DISK needed, unlike Radarr).
- HUN score +10000 → Combined profile (was +1000). Default score set + no tier group → non-HUN positive sums are small; HUN dominates trivially.

### HUN-score invariant math (priority: HUN > quality > size)
- HUN = +10000; LQ = BR-DISK = -10000.
- Radarr (min_format_score 0): LQ alone -10000 < 0 → rejected ✓. HUN alone 10000 ≥ 0 → accepted ✓. HUN+LQ = 0 ≥ 0 → accepted (edge case; HUN dubs are rarely LQ-tagged). Within-HUN upgrade: 10000 < until_score 20000 ✓ (720p HUN → 1080p HUN → 2160p HUN).
- Sonarr (min_format_score 0): same as Radarr.
- HUN dominates non-HUN: non-HUN releases score ~0 (Radarr, no tier CFs) or small positive (Sonarr, streaming/language CFs ≪ 10000) → any HUN release (10000) beats any non-HUN release. A HUN 720p (10000) beats a non-HUN 4K WEB-DL (~0) ✓ — the core HUN > quality requirement.
- Raising min_format_score above 0 to also reject HUN+LQ would reject score-0 fallback releases (720p/1080p with no CFs) → breaks fallback. So min_format_score 0 is the correct lever; the HUN+LQ edge case is accepted by design.
- Post-sync verify: confirm the actual tier/HDR/audio CF integers under the sqp-1-2160p score set do not produce a non-HUN sum ≥ 10000 (only relevant if tier groups are added later).

### Validation
- yamlfmt (conf .yamlfmt.yaml): clean (no content change, only EOF newline normalized).
- yamllint (conf .yamllint.yaml): clean, exit 0.
- recyclarr binary NOT installed locally → no live `recyclarr lint`/dry-run. Schema validation done by manual field-by-field verification against the v8 sub-schemas (media-management, media-naming-radarr, media-naming-sonarr, quality-definition, custom-formats, quality-profiles) at https://schemas.recyclarr.dev/v8/config/*.json , plus TRaSH guide JSON (quality-size/{sqp-uhd,series}, quality-profiles/{sqp-1-2160p,web-2160p-combined}, cf-groups). The `!env_var` tags and remote $refs make a generic JSON-schema validator impractical without pre-processing.
- NOT synced: no `recyclarr sync` run, no cluster apply. Uncommitted in the working tree.

### Open / verify-post-sync / review items
- First real `recyclarr sync` MUST be preceded by a VolSync snapshot of both radarr and sonarr PVCs (delete_old_custom_formats + new profile/score writes rewrite live state).
- Verify the SQP-1 profile does not grab unwanted Bluray-2160p encodes now that tier CFs are absent (rely on hard cap 300 MB/min + quality order). If compact 4K Bluray grabs are unwanted, add tier groups + restore min_format_score 1000.
- Verify `upgrade.until_quality: "WEB 2160p"` (Sonarr) and the qualities override are accepted by recyclarr (group-name cutoff + replaced quality list).
- Verify the local `home-ops-hungarian-language` CF resolves via settings.yml resource_providers and scores +10000 on both profiles post-sync.
- Spec field-name deviations recorded above (media_management field set, 720p Radarr cap, min_format_score 0 override, Sonarr qualities override) — flagged for human review.


## Correction decisions (2026-08-17, Maestro verify)

Maestro verify-don't-trust on the manifest confirmed it matches the implementation report. This section records the correction decisions applied to the uncommitted working tree (STILL no commit/push/PR).

### F1 -- HUN 10000 -> 9900 (both apps)
Changed the local Hungarian CF score from +10000 to +9900 on BOTH the Sonarr (WEB-2160p Combined) and Radarr (SQP-1 2160p) profiles, plus the two recyclarr.yml comments that referenced +10000. This restores the LQ-rejection invariant: with min_format_score 0, HUN(9900) + LQ(-10000) = -100 < 0 -> a HUN+LQ release is REJECTED (no longer the "accepted edge case" the +10000 value left open). Zero cost: fallback score-0 >= 0 still works; HUN 9900 > ~0 (option A) still dominates; within-HUN upgrade 9900 < 20000 still preserved. BR-DISK stays excluded by the profile's quality-allow, independent of score.

### F2 = A -- min_format_score 0 kept, NO tier CF groups (DECISION; no manifest change)
Decision: keep min_format_score 0 on Radarr and do NOT add tier/HDR/audio CF groups (release-groups-hq, audio-formats, hdr-formats-*, required-repack-proper, optional-resolutions). Rationale: A is verified-safe now (non-HUN ~0, HUN dominates trivially, 720p/1080p fallback works); B's only gain is non-HUN release-group ranking (not requested) and it carries a real risk to the user's #1 priority (HUN > quality) because the sqp-1-2160p score-set integers are unverified (a top non-HUN combo could approach/exceed HUN=9900). Framework point 7c records B's re-verification path, so B remains a documented future enhancement -- A does not foreclose it. min_format_score 0 is REQUIRED for fallback: the ratified spec's minFormatScore 1000 + no tier CF groups would have rejected every non-HUN release (the phase-1 review missed this; the implementation report's deviation #3 caught it).

### F4 -- Radarr upgrade.until_quality (VERIFY-GATED, applied)
Added 'until_quality: WEB 2160p' to the Radarr SQP-1 (2160p) upgrade block (Sonarr already had it via the Combined profile's native cutoff). Goal: stop Radarr upgrading to Bluray-2160p; make the WEB-DL preference explicit. Verification evidence: (a) "WEB 2160p" is a named, allowed:true quality item in the SQP-1 (2160p) profile (group with [WEBRip-2160p, WEBDL-2160p]); (b) group-name cutoffs are the native valid form -- the Sonarr WEB-2160p (Combined) profile's native cutoff IS "WEB 2160p". The 300 MB/min cap on Bluray-2160p protects the size goal regardless. VERIFY-POST-SYNC: confirm the cutoff took effect after the first real sync (the SQP-1 native default cutoff is "Bluray-2160p", a single quality). JSON-schema validation (v8, 9 sub-schemas resolved) returned 0 errors; the until_quality sub-schema is {"type":"string"} (the schema cannot encode profile-specific quality names, so value validity rests on the profile-structure evidence above, not the schema).

### F3 -- media_management v8 limitation (DOCUMENTATION ONLY; no manifest change)
recyclarr v8 media_management syncs ONLY propers_and_repacks (schema additionalProperties:false). The user's other media-management preferences CANNOT be set via recyclarr and must be configured manually in the Radarr/Sonarr UI (not GitOps-managed; lost on PVC rebuild):
- monitor_new_items: all (Sonarr), movieOnly (Radarr)
- auto_unmonitor_previous_downloads: false (so cutoff upgrades keep running)
- recycle_bin: false
- use_hardlinks: RUNTIME-VERIFY on the NFS /media mount -- hardlinks over NFS are protocol/client-dependent and NOT guaranteed; if it fails the arr falls back to copy (double storage during seeding). (This corrects the earlier overconfident "use_hardlinks works via NFS /media regardless" claim.)
- delete_empty_series_folders (Sonarr)
- enable_media_info
Buildarr (Terraform-like declarative arr-settings manager) evaluated-later for the non-recyclarr-syncable fields. No action now.

### Validation
- yamlfmt (.yamlfmt.yaml, dry): "No files will be changed" -- already formatted.
- yamllint (.yamllint.yaml): clean, exit 0 (no output).
- JSON-schema validate against https://schemas.recyclarr.dev/v8/config-schema.json (draft-07, 9 sub-schemas resolved, !env_var handled as string): 0 errors.
- recyclarr binary lint/dry-run: NOT available (binary not installed); schema validation + manual field-by-field verification substituted. No real 'recyclarr sync' run.

### Current state (unchanged)
Files MODIFIED, NOT committed, NOT deployed, NOT synced. Pending: first real 'recyclarr sync' MUST be preceded by a VolSync snapshot of both the radarr and sonarr PVCs (delete_old_custom_formats + new profile/score writes rewrite live state).

## Session 2026-08-17 (later) — DEEP-verify apply: 3 decisions (Ollama → Maestro, human-approved)
Read-only deep-verify (delegation 3) surfaced 3 decisions; the human approved all three via the Maestro. Applied to the uncommitted working tree (still no commit/push/PR).

1. **Item 1 — /config writable PVC.** `state/` (a config-dir artifact the recyclarr wiki says "should be backed up") must persist for `delete_old_custom_formats` cross-run cleanup; both reference repos (onedr0p + bjw-s) mount a WRITABLE PVC at /config for this. The `/config` PVC is created by the shared `components/volsync` component declared in `ks.yaml` (VolSync/Kopia backup to OVH S3), consistent with the *arr siblings, referenced via `persistence.config.existingClaim: recyclarr` mounted at /config. The 4 ConfigMap config files (recyclarr.yml, settings.yml, sonarr/radarr hungarian.json) are subPath-projected INTO the writable /config (paths unchanged). `RECYCLARR_DATA_DIR=/tmp` + `readOnlyRootFilesystem` + `args: [sync]` + `tmp` emptyDir for the data dir.

2. **Item 2 — KEEP `type: sqp-uhd` (Radarr); do NOT switch to sqp-streaming.** Authoritative evidence from `TRaSH-Guides/Guides` `docs/json/radarr/quality-size/`: `sqp-streaming.json` INCLUDES 720p entries (WEBDL-720p/WBRip-720p, default max **85.7 MB/min**) while `sqp-uhd.json` has NO 720p entry. Switching would cap 720p at 85.7 MB/min, contradicting the uncapped-720p-fallback intent AND the "HUN > size" priority (a HUN 720p >85.7 MB/min would be rejected on size alone). The explicit 2160p/1080p `max` overrides (300/150) are identical under both types → the balanced-4K goal is unaffected. The official SQP-1 template uses sqp-streaming, but the templates accept its native 720p cap; our deviation (sqp-uhd) is deliberate, documented at recyclarr.yml:86, now backed by the size-set evidence. Sonarr `type: series` unchanged. Comment at recyclarr.yml:86 tightened to cite the 85.7 MB/min evidence.

3. **Item 3 — UID 2000 → 10001.** bjw-s uses UID 2000 (so 2000 was a bjw-s reference copy, not random drift), but it contradicts the home-ops 10001 convention (runtime-baselines.md + 6 *arr siblings + roadmap intent) with no functional/shared-volume reason: recyclarr mounts only the ConfigMap + the /config PVC and shares no volume with the *arr stack; the image is rootless (native UID 1000, no PUID/PGID). All three UIDs (1000/2000/10001) work; 10001 is the documented standard. Manifest `runAsUser/runAsGroup/fsGroup` 2000 → 10001. No APP_UID/PUID/PGID env in the manifest → no ks.yaml postBuild substitute needed (confirmed).

Post-deploy verify-gates (from deep-verify, still open): (a) first real `recyclarr sync` must follow a VolSync snapshot of the radarr + sonarr PVCs (delete_old_custom_formats rewrites live state); (b) verify the PVC + fsGroup 10001 lets recyclarr write /config/state; (c) verify recyclarr does NOT attempt to write /config/settings.yml (mounted read-only from ConfigMap) — if it does, settings.yml delivery needs rework; (d) confirm delete_old_custom_formats actually deletes stale CFs across runs now that state persists.

Validation: pre-commit (yamlfmt + yamllint + gitleaks) PASS on the touched files (recyclarr.yml, kustomization.yaml, helmrelease.yaml, ks.yaml). NOT committed, NOT deployed, NOT synced.

## Session 2026-08-17 — recyclarr VolSync wiring (ks.yaml)
recyclarr's `/config` PVC is created by the shared `components/volsync` component (VolSync/Kopia backup to OVH S3), consistent with the *arr siblings — declared in `ks.yaml`, not via an app-local PVC manifest.

### ks.yaml wiring
- `components: - ../../../../components/volsync` (path resolves from `spec.path` `kubernetes/apps/downloads/recyclarr/app` → `kubernetes/components/volsync`, same depth as the siblings).
- `dependsOn: [onepassword-connect (external-secrets), democratic-csi (kube-system)]`.
- `postBuild.substitute: {APP: recyclarr}` — the only substitution; all other volsync values use the component defaults (capacity 1Gi, storageClass `democratic-csi-local-hostpath`, hourly schedule `0 * * * *`, default retention 24h/7d/2w/1m, mover UID/GID 10001).

### Justified omissions vs the *arr siblings
The *arr siblings (radarr/sonarr/bazarr) set `components: [volsync, gateway-oidc, zeroscaler]`, `dependsOn: [onepassword-connect, democratic-csi, pocket-id]`, `postBuild.substitute: {APP, APP_SUBDOMAIN}`. recyclarr intentionally omits:
- **gateway-oidc + pocket-id**: recyclarr is an internal-only CronJob with no ingress/HTTPRoute — no OIDC gate to wire.
- **zeroscaler**: scales Deployments to 0 off-hours; a CronJob is not scalable — no effect.
- **APP_SUBDOMAIN**: no route → no subdomain.

### helmrelease alignment
`persistence.config.existingClaim: recyclarr` matches the PVC name the volsync component creates (claim name derived from APP → `recyclarr`); `runAsUser/runAsGroup/fsGroup: 10001` matches the volsync mover default UID.

### Validation
- pre-commit (yamlfmt + yamllint + gitleaks) PASS on ks.yaml, kustomization.yaml, helmrelease.yaml.
- `flux build kustomization recyclarr --path kubernetes/apps/downloads/recyclarr/app --kustomization-file kubernetes/apps/downloads/recyclarr/ks.yaml --dry-run` → exit 0; renders the volsync resources: PersistentVolumeClaim name=recyclarr (matches `existingClaim: recyclarr`), ReplicationSource name=recyclarr (mover runAsUser 10001, repository recyclarr-volsync-secret), ReplicationDestination name=recyclarr-bootstrap, ExternalSecret name=recyclarr-volsync.
- NOT committed, NOT deployed, NOT synced.


## Session 2026-08-17 — merge-prep: review + VolSync snapshots + PR

Best-practice review of the recyclarr config against TRaSH-Guides (Radarr + Sonarr profile/file-size/german-en pages) and the recyclarr v8 schema complete and verified:

- **Sonarr (WEB-2160p Combined)**: full "exclude BAD quality" coverage natively — the Unwanted group (59c3af) carries AV1/LQ/LQ-RT/BR-DISK/Upscaled. HUN +9900, cutoff WEB 2160p, 720p re-enabled as fallback.
- **Radarr (SQP-1 2160p, sqp-uhd)**: covered after the explicit AV1+3D add (-10000) — the SQP Unwanted group (15b1cf) lacks AV1/3D/LQ/BR-DISK, so all four are added explicitly at -10000 on profile 5128baeb2b081b72126bc8482b2a86a0. Golden Rule UHD (ff204b) supplies x265-no-HDR/DV -10000.
- **Human decisions applied**: AV1=exclude, 3D=exclude, HDR/DV boost CFs left out (keep non-HUN ~0, HUN dominance trivial; option B re-add would require re-verifying +9900 against sqp-1-2160p score-set), min-floors skipped (Upscaled CF covers fake/upscaled 4K).
- **HUN-score invariant**: HUN 9900 + LQ -10000 = -100 < 0 → HUN+LQ rejected; +9900 (not +10000) preserves fallback and within-HUN upgrade to WEB 2160p.
- **Size caps**: explicit quality_definition max overrides reject bloated encodes (Radarr 2160p=300/1080p=150; Sonarr 2160p=200/1080p=100/720p=50 MB/min); 720p left uncapped on Radarr (sqp-uhd) as the small HUN fallback.

**Pre-merge VolSync snapshots taken (rollback point)** — both manual triggers patched ReplicationSource in namespace `downloads`; confirmed Successful via kopia snapshot list:

- Radarr: snapshot `cfad81a28a76337854b8de229acb64df` @ 2026-08-17T20:14:14Z (491.6 MiB, latest-1).
- Sonarr: snapshot `9c4a4f97a38252586592a8b11d8e967a` @ 2026-08-17T20:11:13Z (440.5 MiB, latest-1).

Code committed (11 kubernetes/ files, explicit pathspecs): `✨ feat(downloads): add recyclarr for sonarr/radarr config sync` — recyclarr CronJob (digest-pinned 8.7.1, hardened UID 10001, @daily), local HUN CF +9900, max-cap quality defs, AV1/3D/LQ/BR-DISK -10000, ESO-delivered arr API keys from 1Password, callee-side CiliumNetworkPolicy admitting recyclarr to radarr/sonarr. Closes the arr-config-sync roadmap.

PR opened against `main` (transition plan + review verdict in PR body). First manual recyclarr sync pending — **Maestro holds merge until green CI + confirmed snapshots**; merge + first sync are the Maestro's, not the worker's.

### Next
- Wait for Maestro merge (after green CI).
- Post-merge: verify recyclarr CronJob live + ExternalSecret synced, then trigger first sync manually.
- Post-sync verify: read back live *arr profiles (HUN +9900, cutoff WEB 2160p, unwanted -10000); remap library naming + delete old sub-optimal profiles in UI.
- Rollback path: `just volsync restore …` from the pre-merge snapshots above if the first sync goes wrong.
