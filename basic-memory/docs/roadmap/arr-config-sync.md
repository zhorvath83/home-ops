---
title: arr-config-sync
type: roadmap
permalink: home-ops/docs/roadmap/arr-config-sync
tags:
- roadmap
- recyclarr
- sonarr
- radarr
- arr-stack
- config-sync
- in-progress
---

# *arr quality-config sync — Recyclarr (current state)

## Metadata (observation-form, schema validation)

- [topic] Automate Sonarr/Radarr quality-profile, custom-format, quality-definition and naming synchronization from the TRaSH guide into the live `downloads` Arr instances, declaratively from GitOps via recyclarr.
- [status] implementation complete (uncommitted on branch `feat/arr-config-sync`; awaiting human review → commit → push → PR → first recyclarr sync with a VolSync snapshot)
- [priority] medium
- [scope] recyclarr CronJob under `kubernetes/apps/downloads/recyclarr/` (ConfigMap-mounted `recyclarr.yml`), ExternalSecret for the Sonarr/Radarr API keys, local Hungarian-dub CF, and callee-side CiliumNetworkPolicy edits on sonarr + radarr.
- [confidence] high on repo-side facts and recyclarr capability surface (upstream + v8 schema verified 2026-08-17)
- [note] This note is a clean current-state record (2026-08-17). The pre-decision Recyclarr-vs-Profilarr comparison, the survey corrections, and the execution-slice history are preserved in git history (pre-2026-08-17 cleanup) for reference.

## Decision — Recyclarr over Profilarr (2026-08-16)

- [decision] Recyclarr (CronJob, YAML-in-git) chosen as the single config-sync owner; Profilarr evaluated and rejected. User decision 2026-08-16.
- Rejection rationale: Profilarr trades declarative config for a UI-owned SQLite state + plaintext credential store + internal HTTP surface + a single-owner TRaSH conversion-repo dependency, and its v2 line had no stable release at decision time. Recyclarr is fully declarative, rootless, no listening surface, reads TRaSH directly, native fit with the repo's UID-10001 / read-only posture.
- Re-evaluation gate for Profilarr (future): (a) publishes a major tag, (b) resumes a stable release cadence, (c) offers declarative Arr-instance bootstrap (write endpoints under `/arr`).
- Recyclarr model: CLI (`recyclarr sync`) one-shot container; desired state = `recyclarr.yml` in git; reads the TRaSH Guides repo directly; `!env_var` / `!file` interpolation for secrets; state/ persists on a writable `/config` PVC created by the shared `components/volsync` component (VolSync/Kopia backup to OVH S3), consistent with the *arr siblings; config files are ConfigMap-subPath-projected into the PVC.

## Planning framework & priority order (szempontrendszer)

This framework records the CONSIDERATION FRAMEWORK used during planning — the priority order + governing principles — so a FUTURE change can be evaluated against this same framework: does this change respect HUN > quality > size? does it preserve 720p/1080p fallback? does it keep the HUN invariants? These are the governing rules for future changes.

1. PRIORITY ORDER (hard): HUN dub > quality > size. The Hungarian-language release is the highest priority, ranked ABOVE quality — a HUN 720p/1080p must beat a non-HUN 4K/Remux. Size is the lowest-priority lever.

2. SIZE-vs-QUALITY GOAL: balanced — EXCLUDE gigantic 4K / huge-bitrate / huge-file releases; but do NOT blanket-exclude lower resolutions. 720p and 1080p MUST remain acceptable as fallback, because content is frequently available ONLY in those qualities.

3. REMUX / BR-DISK / LQ EXCLUSION: clean UHD Remux is undesired (size); BR-DISK (full disc images) and LQ (low-quality) releases are rejected via the Unwanted CF group (BR-DISK = -10000, LQ = -10000). Remux exclusion comes from the PROFILE (allowed qualities), not CFs — BR-DISK does not match clean remuxes. (Implementation note 2026-08-17: the Radarr SQP Unwanted group lacks LQ/BR-DISK, so they are added explicitly as custom_formats; see docs/progress/arr-config-sync.)

4. BEST-PRACTICE / REFERENCE-BASED: decisions are anchored to onedr0p/home-ops + bjw-s-labs/home-ops reference repos, TRaSH-Guides, and the recyclarr upstream config-templates. Prefer recyclarr's built-in recommended config blocks over hand-rolling. Do NOT copy bjw-s's 720p-dropping qualities override.

5. PROFILE-CHOICE PRINCIPLE: SQP family for Radarr (SQP-1 2160p) + Combined for Sonarr (WEB-2160p Combined) — the quality-BALANCED presets that prefer WEB-DL, exclude remux, AND keep 1080p/720p fallback. This is deliberately OPPOSED to the quality-maximizing "UHD Bluray + WEB" (Radarr) and non-Combined "WEB-2160p" (Sonarr) presets, which forbid the 720p/1080p fallback.

6. SIZE-CAP PRINCIPLE: the TRaSH quality-size default max (2000 MB/min ≈ 240 GB / 2h movie) is NON-BINDING — it does not exclude gigantic files. A real ceiling requires an explicit `quality_definition.qualities[].max` override. The ceiling applies to the TOP quality; lower qualities get proportionally lower caps. NEVER raise a `min` floor in a way that rejects 720p/1080p. (Implementation note 2026-08-17: the sqp-uhd size set has no 720p entry → 720p stays uncapped on Radarr; the Sonarr series set has 720p → capped at 50.)

7. HUN-SCORE INVARIANTS (the bounds for any future HUN-value change):
   (a) LQ/BR-DISK rejection MUST hold: HUN + (-10000) < minFormatScore. Under the chosen min_format_score 0 this gives HUN < 10000; HUN=9900 satisfies it (HUN+LQ = 9900 + (-10000) = -100 < 0, rejected). NEVER set HUN >= 10000 under min_score=0 -- it would let HUN+LQ >= 0 and accept a bad (LQ) Hungarian release. (Under a hypothetical minFormatScore 1000 the bound would be HUN < 11000, but min_score=0 is the implementation value.)
   (b) Within-HUN upgrading MUST be preserved: HUN total < cutoffFormatScore. Chosen path: until_score raised to +20000 on BOTH apps (Sonarr + Radarr), so within-HUN upgrades are preserved; HUN=9900 < 20000 (OK).
   (c) HUN MUST dominate realistic non-HUN quality sums. Under the chosen option A (NO tier/HDR/audio CF groups added), non-HUN scores are ~0, so HUN=9900 dominates trivially. If a future change adopts option B (adds tier/HDR/audio groups), re-verify the actual sqp-1-2160p score-set integers against HUN=9900 BEFORE applying — a top non-HUN combo (Tier 01 + DV + ATMOS + ...) could approach or exceed 9900 under that score set.
   These three inequalities are the constraints any future HUN adjustment must satisfy.

8. NAMING-CONVENTION PRINCIPLE: Plex + Jellyfin + Emby friendly (the community-standard TRaSH/onedr0p scheme). The folder convention MUST match the existing library: {Title} (Year) for movie/series folders, Season 0X for season folders. Setting `media_naming` does NOT auto-rename existing files — it governs new downloads + manual Organize only, so the existing huge library is safe; renaming existing files is a separate, opt-in, selective step.

9. media_management PRINCIPLES: PROPER/REPACK only if genuinely better (doNotPrefer — not upgraded merely for being newer); upgrades are WANTED (auto_unmonitor_previous_downloads = false, so cutoff upgrades keep running); monitor everything (all for Sonarr, movieOnly for Radarr); recycle bin OFF; hardlinks ON for storage efficiency when qBittorrent and the arr share a filesystem. (Implementation note 2026-08-17: the recyclarr v8 media_management schema exposes ONLY propers_and_repacks — the other fields are not syncable via recyclarr and remain UI/manual settings; use_hardlinks on NFS is protocol/client-dependent and NOT guaranteed — runtime-verify on the mount; if it fails the arr falls back to copy (double storage during seeding). See docs/progress/arr-config-sync.)

10. DECLARATIVE / GitOps PRINCIPLE: recyclarr (YAML-in-git CronJob) is the single config-sync owner (Profilarr was evaluated and rejected per the roadmap). Config is Git-versioned and PVC-loss-safe (re-synced from git). The first real `recyclarr sync` MUST be preceded by a VolSync snapshot of both the radarr and sonarr PVCs, because delete_old_custom_formats + new profile/score writes rewrite live state.

11. SCOPE DISCIPLINE: only the recyclarr config + callee CiliumNetworkPolicies; shared secret/store names and wiring are untouched; NO commit/push/PR until final human approval — implementation stays uncommitted in the working tree.

## Implementation — current state (2026-08-17, spec rewrite, uncommitted)

Branch `feat/arr-config-sync`. Files: `recyclarr.yml` (Sonarr + Radarr blocks), `settings.yml` + `config/custom-formats/{radarr,sonarr}/hungarian.json` (local HUN CF), `externalsecret.yaml` (1PW → `recyclarr-secret`), `helmrelease.yaml` (app-template CronJob, digest-pinned recyclarr 8.7.1, @daily, hardened UID-10001), `kustomization.yaml` (configMapGenerator + Flux substitution-disable annotation), `ks.yaml`, and callee-side CNP edits on sonarr + radarr (4th `fromEndpoints` block each).

**Radarr (movies):**
- quality_definition.type: sqp-uhd; caps 2160p (WEBDL/WEBRip/Bluray)=300, 1080p (WEBDL/WEBRip)=150 MB/min. 720p uncapped (sqp-uhd has no 720p entry — the small fallback).
- quality_profile: [SQP] SQP-1 (2160p) (trash_id 5128baeb2b081b72126bc8482b2a86a0); reset_unmatched_scores enabled; **min_format_score: 0** (option A — no tier CF groups; see framework 7c); upgrade allowed, **until_quality: WEB 2160p**, until_score: 20000.
- custom_format_groups: Golden Rule UHD (ff204bbcecdd487d1cefcefdbf0c278d) + Unwanted Formats SQP (15b1cf0b6f1a1493856a4355907affee).
- custom_formats: HUN (home-ops-hungarian-language) **+9900**; explicit LQ (90a6f9a284dff5103f6346090e6280c8) + LQ Release Title (e204b80c87be9497a8a6eaff48f72905) + BR-DISK (ed38b889b31be83fda192888e2286d83) **-10000** (SQP Unwanted group lacks these).
- media_management: propers_and_repacks: do_not_prefer. media_naming: folder plex-imdb, movie {rename: true, standard: plex-imdb}.

**Sonarr (series):**
- quality_definition.type: series; caps 2160p (WEBDL/WEBRip)=200, 1080p=100, 720p=50 MB/min.
- quality_profile: WEB-2160p (Combined) (trash_id c4cadd6b35b95f62c3d47a408e53e2f7); reset_unmatched_scores enabled; upgrade allowed, until_quality: WEB 2160p, until_score: 20000; **qualities override re-enables WEB 720p** (Combined disables it) — ladder WEB 2160p > WEB 1080p > WEB 720p, each WEBRip + WEBDL.
- custom_format_groups: Golden Rule UHD (e3f37512790f00d0e89e54fe5e790d1c) + Language Profiles (74aff4168620ed49dcc67e92b2c2a5b4) + Streaming HD/UHD boost (85fae4a2294965b75710ef2989c850eb) + Unwanted Formats (59c3af66780d08332fdc64e68297098f, includes LQ/BR-DISK).
- custom_formats: HUN (home-ops-hungarian-language) **+9900**.
- media_management: propers_and_repacks: do_not_prefer. media_naming: series plex-imdb, season default, episodes {rename: true, standard/daily/anime: default}.

**Hungarian CF:** local custom format, `LanguageSpecification` fields.value 22 (Hungarian language ID), required, NO score — the score (+9900) lives in `recyclarr.yml` `assign_scores_to` on each profile. Modeled on the German TRaSH preset structure (no Hungarian guide preset exists).

**Validation:** yamlfmt + yamllint clean; JSON-schema validate against https://schemas.recyclarr.dev/v8/config-schema.json → 0 errors; recyclarr binary not installed locally (no live `recyclarr lint`/dry-run; field-by-field + TRaSH guide JSON verification substituted). NOT synced, uncommitted.

**Limitations / manual-UI settings (recyclarr v8 syncs ONLY propers_and_repacks from media_management):** monitor_new_items (all Sonarr / movieOnly Radarr), auto_unmonitor_previous_downloads=false (so cutoff upgrades keep running), recycle_bin=false, use_hardlinks (NFS — protocol/client-dependent and NOT guaranteed; runtime-verify on the mount; if it fails the arr falls back to copy = double storage during seeding), delete_empty_series_folders (Sonarr), enable_media_info. These are NOT GitOps-managed (lost on PVC rebuild). Buildarr evaluated-later for declarative arr-settings management.

Full decision/rationale/deviation detail: `docs/progress/arr-config-sync` → "## Implementation decisions (2026-08-17)" and "## Correction decisions (2026-08-17, Maestro verify)".

## Pending (human-gated)

- commit → push → PR → first recyclarr sync.
- BEFORE first sync: VolSync snapshot of the radarr + sonarr PVCs (delete_old_custom_formats + new profile/score writes rewrite live state).
- Verify-post-sync: Radarr `until_quality: WEB 2160p` cutoff took effect; HUN +9900 on both profiles; local HUN CF detected on releases.

## Risks still relevant

- First `recyclarr sync` rewrites live Arr state (profiles, CFs, scores) → not trivially reversible from the Arr side → VolSync snapshot first.
- `!env_var` interpolation vs Flux `postBuild` substitution collision → the ConfigMap substitution-disable annotation is load-bearing.
- Arr API keys copied from each app's `/config/config.xml` into 1Password → must be re-synced if a key is regenerated in the UI.
- Option B (tier/HDR/audio CF groups) is a documented future enhancement → re-verify the actual sqp-1-2160p score-set integers against HUN=9900 BEFORE applying (framework point 7c); a top non-HUN combo could approach/exceed 9900.

## Related

- relates_to [[k8s-workloads]] — app shape, canonical patterns, downloads/media split
- relates_to [[external-secrets]] — 1Password properties for the Arr API keys
- relates_to [[networking]] — callee-side CiliumNetworkPolicy edits
