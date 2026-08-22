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
---

# arr-config-sync — Recyclarr-owned *arr quality config

- [type] progress-note
- [status] LIVE — the HUN-first scoring model is merged, reconciled and applied by a recyclarr sync; verified against both live profiles
- [area] k8s-workloads, external-secrets, networking
- [scope] kubernetes/apps/downloads/recyclarr/

## What this is

**recyclarr** is the single owner of Sonarr/Radarr quality profiles, custom formats, quality
definitions and media naming. Desired state is `recyclarr.yml` in git; recyclarr reads the TRaSH
Guides repo directly and writes the live *arr instances. Profilarr was evaluated and rejected
(UI-owned SQLite state, plaintext credential store, internal HTTP surface, single-owner conversion
repo). Re-evaluation gate: a major tag + stable release cadence + declarative Arr-instance bootstrap.

## Deployment shape

- **CronJob** `kubernetes/apps/downloads/recyclarr/`, Flux-managed, `ghcr.io/recyclarr/recyclarr:8.7.1`
  digest-pinned, bjw-s app-template. @daily, hardened (UID 10001, readOnlyRootFilesystem, drop ALL,
  seccomp RuntimeDefault). `RECYCLARR_DATA_DIR: /tmp` emptyDir.
- **Entrypoint**: `recyclarr sync && bash /config/fix-radarr-language.sh` under the image's own tini.
- **Egress**: pod label `egress.home.arpa/allow-world: "true"` (AD-023) for the TRaSH-Guides clone.
  In-cluster egress to the *arr FQDNs is not label-gated.
- **Secrets**: ExternalSecret `recyclarr-secret` from `onepassword-connect` (1PW `radarr`/`sonarr`
  → `RADARR_API_KEY`/`SONARR_API_KEY`).
- **Network policy**: callee-side CiliumNetworkPolicies on radarr (7878) and sonarr (8989) admit
  recyclarr by `fromEndpoints` (namespace `downloads`, name `recyclarr`).
- **Config delivery**: ConfigMap-projected files subPath-mounted into a writable `/config` PVC,
  backed up hourly by `components/volsync` (Kopia → OVH S3), mover UID 10001.
- **Load-bearing annotation**: `kustomize.toolkit.fluxcd.io/substitute: disabled` on the ConfigMap —
  `!env_var` interpolation collides with Flux `postBuild` substitution. Do not remove.

## Governing priority: HUN dub > quality > size

Hungarian audio ranks **above** quality. 720p/1080p must stay viable as fallback — content is often
available only there. Gigantic 4K encodes are excluded by size cap, not by dropping resolutions.

### The mechanism: one quality group, resolution as a score

Custom format score is a **tiebreaker within a quality tier, not a weight across tiers**:

- [fact] `DownloadDecisionComparer.Compare()` runs `CompareQuality → CompareCustomFormatScore → …`
  and short-circuits on `FirstOrDefault(r => r != 0)`. Same order in Sonarr and Radarr.
- [fact] `UpgradableSpecification.IsUpgradable()` returns `None` on
  `qualityCompare > 0 && QualityCutoffNotMet(...)` — before any CF score is computed.
- [fact] `QualityProfile.GetIndex(quality)` defaults to `respectGroupOrder: false`, returning
  `QualityIndex(i)` with `GroupIndex = 0` for every group member. One group ⇒ members compare equal
  ⇒ `CompareQuality` returns 0 ⇒ the decision falls through to the CF score.

So each profile collapses **every allowed quality into a single group** — Sonarr `WEB`
(720p/1080p/2160p WEBRip+WEBDL), Radarr `SQP` (the nine qualities SQP-1 allows; Remux excluded) —
and resolution is expressed as a custom format score. Without this, a non-HUN 2160p beats a HUN
1080p at any Hungarian score.

### The shared ladder (both apps, defined in the recyclarr.yml header)

| rung | score |
|---|---|
| HUN dub | 30000 |
| 2160p / 1080p | 20000 / 10000 (720p is the 0 baseline on both apps) |
| bluray | -4000 |
| remux | -5000 |
| release-group tier | ≤ 3300 |
| HDR | 500 |
| audio (DD+ ATMOS, Radarr only) | 135 |
| streaming service | ≤ 1575 (Sonarr: 19 CFs × 75 + 150 boosts; Radarr: MA+CRiT 40) |
| Repack/Proper | 7 |
| junk veto (all of them, both apps) | -60000 |
| `until_score` (= `cutoffFormatScore`) | 50000 |

Worst-case non-resolution stack (M) — max within each mutually exclusive family (tier, audio,
repack), sum where CFs stack (service, encode group): **Sonarr 3782, Radarr 3982**. Take M = 3982.

- [invariant] resolution step 10000 > M → resolution outranks tier/HDR/audio/service
- [invariant] remux penalty 5000 > M → a plain release always beats a remux of the same
  resolution, loaded or not
- [invariant] 2160p remux 15000 > 1080p + M = 13982 → a 4K remux still beats any 1080p
- [invariant] 1080p remux 5000 > 720p + M = 3982 → a 1080p remux still beats any 720p
- [invariant] bluray penalty 4000 > 3342 (what a BLURAY-source release can actually stack) →
  a plain WEB release always beats Bluray of the same resolution
- [invariant] 2160p bluray 16000 > 1080p + M = 13982 → a 4K Bluray still beats any 1080p
- [invariant] max non-HUN = 20000 + M = 23982 < 30000 - 4000 = 26000 → even a HUN Bluray-720p
  beats every non-HUN release
- [invariant] max total = 30000 + 20000 + M = 53982 < 60000 → every junk veto stays a real veto
- [invariant] until_score 50000 = 30000 + 20000 (bare HUN 2160p, plain WEB) → the CF cutoff latches

Re-derive all of them before changing any score. The binding constraint on a veto is
**|veto| > max achievable positive total** — not a ceiling on the HUN score. A veto left at the
guide's -10000 silently stops being a veto once the positive rungs grow past it.

- [decision] The remux penalty is what forced the 10000 resolution step. It has to exceed M to be
  a guarantee rather than a hope — a remux carrying a Bluray tier CF would otherwise outscore a
  plain release — and once the penalty is 5000, the step has to exceed penalty + M or a 4K remux
  would fall below a 1080p WEB.
- [fact] Neither guide has an "is this a remux" custom format, so it is local: Sonarr has no
  quality-modifier spec and matches `SourceSpecification` value 7 (BlurayRaw), which covers
  Bluray-1080p Remux and Bluray-2160p Remux and nothing else; Radarr uses
  `QualityModifierSpecification` value 5 (REMUX).
- [fact] There is no rung below 720p, so a 480p release scores the same as a 720p one. Inert while
  SD sits outside both profiles — a 480p release is rejected at the quality gate regardless.

Live and identical on both apps at 1080p: HUN WEB 40000 > HUN Bluray 36000 > HUN remux 35000;
HUN Bluray-720p 26000 still clears the best non-HUN release.

- [fact] recyclarr **rejects** `preferred` below the guide's `min` and aborts that app's entire
  sync ("min (102) cannot be greater than preferred (90)"), reporting only the first offender per
  app. Tightening a `max` below the usual 60%-of-max preferred silently sets up this trap.
- [fact] Sonarr's quality-definition API caps `max` at 1000, Radarr's at 2000; recyclarr clamps
  silently rather than warning, so an over-large cap looks applied but is not.

### Language gating

- [decision] Sonarr **skips** the auto-synced TRaSH group `[Optional] Language Profiles`
  (`74aff4168620ed49dcc67e92b2c2a5b4`). Its only default member, `Language: Not Original` (-10000),
  penalises every non-original track including Hungarian dubs.
- [decision] Radarr's SQP-1 `Preferred Language` must be **Any**, not `Original`. A profile language
  is a hard gate that runs before CF scoring and is mutually exclusive with language CFs (TRaSH
  documents this). Three layers independently force `Original` — the TRaSH SQP-1 preset, recyclarr
  (no `language` property in the v8 schema; it only passes the guide value through), and Radarr's
  own `GetDefaultProfile`. `config/scripts/fix-radarr-language.sh` is the idempotent post-sync
  reconciler that sets it back to `Any` and read-back verifies, using bash `/dev/tcp` (no curl/jq
  in the image). Carries a `debt:` marker — remove when recyclarr ships a language override.
- [decision] Third-language dubs are blocked by the local CF `home-ops-not-hungarian-or-original`
  at -35000 (mirrors TRaSH's "Not German or English"): negate-Hungarian + negate-Original +
  negate-title-regex, so only Hungarian and the original language pass. This is what makes the
  Sonarr group skip safe — it covers the same ground without punishing Hungarian.
- [decision] `min_format_score: 0` on both profiles, so an untagged non-HUN release stays available
  as fallback. Junk is rejected by the -35000 vetoes, not by this floor.

### Allowed qualities and size caps

Both profiles allow the same 13 qualities in one group named `HD-UHD`: WEB (WEBDL + WEBRip),
Bluray, HDTV and Remux at 720p / 1080p / 2160p. The guide profiles gate far more narrowly —
Sonarr's WEB-2160p (Combined) is WEB-only ("covers: WEBDL 1080p, 2160p") and Radarr's SQP-1 leaves
HDTV and Remux out — and that is wrong here, because the excluded categories are where the
Hungarian dubs live: 93% of the Sonarr files at an excluded quality were Hungarian against 64%
inside, and 100% on Radarr. A quality absent from a profile also indexes as 0, so those files are
permanently cutoff-unmet and any allowed release outranks them on quality tier before scoring runs.

- [decision] Size is the lowest-priority lever, so it is enforced as a **cap per quality**, never
  by excluding a source category. Every allowed quality carries an explicit `max` because both
  guide definitions leave Bluray / HDTV / Remux effectively uncapped.
- [decision] SD stays out (WEBRip-480p, DVD — 92 Sonarr files, all Hungarian). There is no 480p
  resolution rung, so SD would tie with 720p at the 0 baseline and freeze: `newFormatScore <=
  currentFormatScore` would block the upgrade to 720p forever. Admitting SD needs a negative 480p
  rung first.
- [decision] Remux is admitted on both apps to protect the 69 Hungarian Remux files from being
  outranked by any WEB release, capped rather than excluded.

Caps in MB/min (preferred ≈ 60% of max). Multiply by ~45 for a Sonarr episode, ~120 for a film:

| quality | Sonarr | Radarr |
|---|---|---|
| Remux 2160p | 550 | 550 |
| Bluray-2160p | 300 | 300 |
| WEBDL/WEBRip-2160p | 200 | 300 |
| Remux 1080p | 250 | 300 |
| Bluray-1080p | 150 | 200 |
| WEBDL/WEBRip-1080p, HDTV-1080p | 100 | 150 |
| Bluray-720p | 80 | 100 |
| WEBDL/WEBRip-720p, HDTV-720p | 50 | 100 |

- [fact] The 4K remux cap is calibrated on the library, not guessed: existing 4K remuxes run
  411 MB/min median and 499 max, so an initial 400 would have rejected 16 of 25. 550 admits them
  and still rejects the bloated tail (~25 GB per episode, ~66 GB per film).
- [fact] Radarr uses `quality_definition: movie`, not `sqp-uhd`. sqp-uhd defines only 8 qualities
  and recyclarr **hard-errors** on a cap for any quality outside its guide type
  ("Quality 'X' does not exist in the guide for type 'sqp-uhd'"), aborting the whole Radarr run
  before it writes anything. `movie` covers all 14 — but defaults every max to 2000, so every
  allowed quality must be listed or it is effectively uncapped. Not `sqp-streaming` either: its
  85.7 MB/min 720p cap would reject large Hungarian 720p releases, against HUN > size.

## Recyclarr semantics worth knowing (v8.7.1, read from source)

- [fact] A CF group is auto-synced when it carries `"default": "true"` **and** lists a configured
  profile in `quality_profiles.include` — no `add` entry needed.
- [fact] `custom_format_groups.skip` only suppresses the auto-synced path
  (`ConfiguredCustomFormatProvider.FromDefaultGroups`). A group under `add` goes through
  `FromExplicitGroups` and ignores `skip`. Dropping an auto-synced group needs removal from `add`
  **and** an entry in `skip`.
- [fact] Score conflicts resolve **first value wins**
  (`QualityProfilePlanComponent.AddCustomFormatScore`), and `GetAll()` yields flat `custom_formats`
  before CF-group entries — so a flat score reliably overrides a guide/group score. Each override
  logs an INFO "conflicting scores" line; expected output, not a warning.
- [fact] `upgrade.until_score` maps to `cutoffFormatScore`
  (`UpdatedQualityProfile.EffectiveCutoffFormatScore`).
- [fact] A CF group's `exclude` cannot remove a member marked `required: true`.
- [fact] `media_management` exposes only `propers_and_repacks`; recyclarr syncs nothing else there.

## Not managed by recyclarr — manual in the *arr UI, lost on PVC rebuild

`monitor_new_items` (all / movieOnly), `auto_unmonitor_previous_downloads` (false, so cutoff
upgrades keep running), `recycle_bin` (off), `use_hardlinks`, `delete_empty_series_folders`,
`enable_media_info`, and the 24h Delay Profile. Buildarr is the documented future option for
declarative *arr settings.

## Rollback

A `recyclarr sync` rewrites live *arr state (profiles, CFs, scores) and is not reversible from the
*arr side. Take a VolSync snapshot of both PVCs before any config-changing sync and restore with
`just volsync restore …`.

## Open

- [followup] Library churn is now live on both apps: a HUN 720p outranks a non-HUN 2160p, so
  existing non-HUN files get replaced once a Hungarian release appears. Intended.
- [followup] 10 existing files carry a -35000 veto CF (9 of them Hungarian) — 3 Radarr Remux-1080p
  with DTS-HD MA, plus scattered TrueHD ATMOS / DV-without-HDR / x265-no-HDR / 3D. Their own score
  is deeply negative, which makes them the most replaceable files in the library despite being
  high-quality Hungarian. The lossless-audio vetoes come from SQP and are what keep bloated remuxes
  out, so they were deliberately left alone; revisit if those files start disappearing.
- [followup] Sonarr caps WEBRip-2160p at 200 MB/min, but 16 of the 20 existing WEBRip-2160p files
  exceed it (median 244, max 300). Pre-existing cap, untouched — but Sonarr will not grab more of
  the kind of 4K WEBRip already in the library.
- [followup] SD (WEBRip-480p 89 + DVD 3, all Hungarian) is still outside both profiles, and 480p
  still scores the same as 720p because there is no rung below 720p. Admitting SD needs that
  negative 480p rung first, or SD would tie with 720p and never upgrade.
- [followup] Four inert leftover user CFs at score 0 (Radarr "HUN lang"; Sonarr "HUN 1080p",
  "HUN 2160p", "HUN 720p"). No trash_id, so recyclarr will not delete them. Optional UI cleanup.
- [followup] *arr API keys live in 1Password, copied from each app's `/config/config.xml`. Re-sync
  if a key is regenerated in the UI.

## Related

- relates_to [[home-ops/docs/areas/k8s-workloads]]
- relates_to [[home-ops/docs/areas/external-secrets]]
- relates_to [[home-ops/docs/areas/networking]]
