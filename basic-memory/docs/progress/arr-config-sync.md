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
- [status] LIVE — the HUN-first scoring model is merged and reconciled; it takes effect on the next @daily recyclarr sync
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
| HUN dub | 16000 |
| 2160p / 1080p | 10000 / 5000 (720p = implicit 0 baseline) |
| release-group tier | ≤ 3300 |
| HDR | 500 |
| audio (DD+ ATMOS, Radarr only) | 135 |
| streaming service | ≤ 1575 (Sonarr: 19 CFs × 75 + 150 boosts; Radarr: MA+CRiT 40) |
| Repack/Proper | 7 |
| junk veto (all of them, both apps) | -35000 |
| `until_score` (= `cutoffFormatScore`) | 26000 |

Worst-case non-resolution stack — max within each mutually exclusive family (tier, audio, repack),
sum where CFs stack (service, encode group): **Sonarr 3782, Radarr 3982**.

- [invariant] resolution step 5000 > 3982 → resolution outranks tier/HDR/audio/service within HUN
- [invariant] max non-HUN = 10000 + 3982 = 13982 < 16000 → HUN wins at every resolution
- [invariant] max total = 16000 + 10000 + 3982 = 29982 < 35000 → every junk veto stays a real veto
- [invariant] until_score 26000 = 16000 + 10000 (bare HUN 2160p) → the CF cutoff latches

Re-derive all four before changing any positive score. The binding constraint on a veto is
**|veto| > max achievable positive total** — not a ceiling on the HUN score. A veto left at the
guide's -10000 silently stops being a veto once the positive rungs grow past it.

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

### Size caps (MB/min, preferred ≈ 60% of max)

- Sonarr (`quality_definition: series`): 2160p 200/120, 1080p 100/60, 720p 50/30.
- Radarr (`quality_definition: sqp-uhd`): 2160p + Bluray-2160p 300/180, 1080p 150/90. sqp-uhd has
  no 720p entry, so 720p keeps Radarr's built-in 208.8 MB/min — deliberately not `sqp-streaming`,
  whose 85.7 MB/min cap would reject large Hungarian 720p releases.

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

- [followup] The scoring-model change is on `fix/sonarr-hungarian-dub-scoring`; no PR. Flux watches
  `main`, so the branch is inert until merged.
- [followup] On merge, expect library churn: a HUN 720p outranks a non-HUN 2160p, so existing
  non-HUN 4K files get replaced once a Hungarian release appears. Accepted.
- [followup] 17 Radarr files sit at a quality SQP-1 does not allow (16× Remux-1080p, 1× Remux-2160p).
  `GetIndex` returns index 0 for them, so any allowed release counts as an upgrade. Remux is
  deliberately out of the group.
- [followup] `Flow (2024)`: Latvian original with an English audio file on disk, which
  `home-ops-not-hungarian-or-original` should veto. Likely a pre-CF download.
- [followup] `arr-search` has `CutoffUnmetEpisodeSearch` commented out; worth reconsidering now
  that `until_score` latches.
- [followup] Four inert leftover user CFs at score 0 (Radarr "HUN lang"; Sonarr "HUN 1080p",
  "HUN 2160p", "HUN 720p"). No trash_id, so recyclarr will not delete them. Optional UI cleanup.
- [followup] *arr API keys live in 1Password, copied from each app's `/config/config.xml`. Re-sync
  if a key is regenerated in the UI.

## Related

- relates_to [[home-ops/docs/areas/k8s-workloads]]
- relates_to [[home-ops/docs/areas/external-secrets]]
- relates_to [[home-ops/docs/areas/networking]]
