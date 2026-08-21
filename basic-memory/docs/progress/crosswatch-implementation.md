---
title: crosswatch-implementation
type: progress_note
permalink: home-ops/docs/progress/crosswatch-implementation
---

# CrossWatch implementation — execution progress

## Metadata (observation-form)

- [topic] P0 Trakt watch-history rescue: ZIP inventory, ground-truth measurement, second copy into the file-level backup plane
- [status] P0 DONE (rescue + measurement + second copy). API-application check still pending (human-only). P1 merged into P2 (in-cluster PoC) — not started.
- [branch] feat/crosswatch
- [area] k8s-workloads / media, resticprofile-backup
- [created] 2026-08-21
- [implements] [[crosswatch-implementation]] roadmap (P0 leg)

## P0 results — ZIP inventory and integrity

Source archive: `~/Downloads/trakt-json-export-zhorvath83.zip` — 715542 bytes, SHA-256 `825b560fb53ad0e651169f0f2859c6f21da7ceec4f5625c04259000944ba425f`. `unzip -t`: no errors, 82 files, all OK.

CrossWatch trakt-importer expected filename patterns (verified by human on cenodude/CrossWatch v0.11.2, L95-104) vs actual ZIP contents:

- `watched-history-*.json` → MATCH (watched-history-1..23.json, 23 files) — the event log
- `ratings*.json` → MATCH (4 files), all empty `[]`
- `watchlist*.json` → 0 match. Watchlist data lives in `lists-watchlist.json` (caught by `lists*`), empty `[]`
- `lists*.json` → MATCH (4 files), all empty `[]`
- `comments*.json` → MATCH (5 files), all empty `[]`

46 files in the ZIP are NOT picked up by the trakt importer; none represent watch-history data loss:

- `watched-movies.json` / `watched-shows.json` / `watched-playback.json` — deduplicated per-title summaries of the same events already in `watched-history-*` (cross-check confirms the event log is complete). Not ingested, not a loss.
- `collection-*.json` (20 files: 85 movies, 230 shows, ~4395 collected episodes) + `hidden-progress-watched.json` — the Trakt COLLECTION (ownership), out of P0 scope. Preserved in the ZIP archive (P6 keeps the ZIP permanently).
- `user-*`, `hidden-*`, `network-*`, `likes-*`, `notes-*` — account metadata or empty `[]`. No history data.

## P0 results — ground-truth measurement (the P1 reference baseline)

Measured from the `watched-history-*.json` event log (what CrossWatch imports), cross-checked against Trakt's own `user-stats.json` counters. Both agreed exactly → the export lost no events.

- Total watch-events: 5639 (23 files: 22×250 + 139)
- Movie watch-events: 310 / unique movies: 174 (→ 136 rewatch-events; playcount preserved at event level)
- Episode watch-events: 5329 / unique episodes: 4688
- Unique shows: 249
- watched_at coverage: 5639/5639 = 100% — no dateless event
- watched_at range: 2010-12-04T02:00:00.000Z .. 2026-07-29T18:53:00.000Z
- action breakdown: scrobble 4642, watch 997
- ratings: 0 (all `ratings-*.json` empty; `user-stats` ratings.total=0)
- watchlist: 0 (`lists-watchlist.json` empty)
- lists: 0 (all `lists-*.json` empty)
- comments: 0 (all `comments-*.json` empty)

Cross-check (event log vs Trakt `user-stats.json`): movie events 310 = movies.plays 310; episode events 5329 = episodes.plays 5329; unique movies 174 = movies.watched 174; unique episodes 4688 = episodes.watched 4688; unique shows 249 = shows.watched 249. All MATCH → export complete.

Earlier "3-episode gap" (`watched-shows.json` plays sum 5326 vs 5329) and "249 vs 248 shows" were drift in the `watched-shows.json` SUMMARY file, not the event log. Resolved: the event log is authoritative and complete.

## P0 results — second copy (file-level backup plane)

Acceptance criterion: ZIP in ≥2 locations outside the Trakt account, one in the file-level backup plane.

- Copy 1 (local): `~/Downloads/trakt-json-export-zhorvath83.zip` — untouched.
- Copy 2 (file-level backup plane): `/Volumes/backups/trakt/trakt-json-export-zhorvath83.zip` — created 2026-08-21. The NAS `/backups` SMB share (192.168.1.10:/backups, mounted on the Mac at `/Volumes/backups`). Per-app subdir follows the SOURCE-name convention (trakt), not the consumer (crosswatch), because the archive outlives CrossWatch (P6 keeps it permanently).
- Copy 3 (offsite, automatic): the in-cluster `resticprofile` workload backs up the whole `/backups` tree at 01:00 daily into OVH Object Storage, so the `trakt/` subtree gets an offsite copy at the next run.

Integrity: both local copies SHA-256 `825b560fb53ad0e651169f0f2859c6f21da7ceec4f5625c04259000944ba425f`, 715542 bytes each.

## Roadmap deviation (human-approved, 2026-08-21) — P1 merged into P2

The roadmap originally specified P1 as a local, out-of-cluster PoC with "No manifests are written before this phase is green." This changed:

- No container runtime exists on the Mac (only an engine-less docker CLI in /usr/local/bin; no Docker Desktop / OrbStack / Podman / Colima). Nothing will be installed on the Mac.
- An out-of-band `kubectl run` throwaway pod was rejected: the repo non-negotiable forbids manual kubectl changes outside documented bootstrap/recovery/Just flows.
- P1 therefore MERGES INTO P2: a proper GitOps deploy into the media namespace, treated as a PoC. The roadmap P1 measurements (import counts, watched_at coverage, export round-trip, "browsable library vs sync dashboard" UI) are performed on the live instance. On failure: git revert + Flux prune rolls everything back.
- ISOLATION CONDITION (non-optional): the first round deploys ONLY CrossWatch itself — NO SIMKL, Plex, or Jellyfin provider. Nothing that can write into the real libraries is wired until the import and round-trip are green. P3/P4/P5 remain separate later steps.

## Open — human-only

- Does the Trakt API application still exist in the account? (Trakt web UI login required.) Decides whether a live Trakt sync is possible at all, or the ZIP is the only route. Not answered in P0; remains open. Do not delete the app — a new one cannot be created (VIP-only since 2026-07-30).

## Relations

- implements [[crosswatch-implementation]] (roadmap, P0 leg)
- relates_to [[resticprofile-backup]] (file-level backup plane, second copy target)
- relates_to [[k8s-workloads]] (P2 deploy target area)
