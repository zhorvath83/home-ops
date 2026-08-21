---
title: crosswatch-implementation
type: note
permalink: home-ops/docs/roadmap/crosswatch-implementation
tags:
- roadmap
- media
- crosswatch
- trakt
- jellyfin
---

# CrossWatch implementation — roadmap

## Metadata (observation-form)

- [topic] Replace the dead Trakt sync with CrossWatch as the primary watch-state tracker
- [status] planned
- [priority] high
- [area] k8s-workloads / media
- [created] 2026-08-21
- [decided_by] human, 2026-08-21 (candidate comparison in [[trakt-watch-state-migration]])

## Why

The Trakt sync plane is already dead, not merely at risk:

- [observation] The stored Trakt OAuth token no longer refreshes. Live evidence from the running
  pod: `Unauthorized - OAuth token refresh failed: invalid_grant - session not found`, logged at
  2026-08-20 11:29 and 14:55 in /app/config/plextraktsync.log of deployment plex-trakt-sync
  in namespace media.
- [observation] Trakt made new API application creation VIP-only on 2026-07-30, and several
  developers report existing applications disappearing. A replacement credential cannot be issued.
- [observation] plex-trakt-sync (ghcr.io/taxel/plextraktsync 0.35.17) is therefore a dead workload
  kept alive only by its Plex websocket loop.

The long-term direction is Plex to Jellyfin. The watch-state history must survive both the Trakt
shutdown and that migration, in a store the user owns.

## Decision

- [decision] CrossWatch (github.com/cenodude/CrossWatch, AGPL-3.0) becomes the primary watch-state
  tracker AND the sync engine. Chosen over Floppy and Scrob.
- [decision] Jellyfin is NOT the primary store — it is a player. The tracker owns the truth.
- [decision] SIMKL is wired as an offsite mirror of the watch state, for redundancy only, never as
  the source of truth.

Rationale, against the user's hard requirements: single container with its own SQLite store (no
Redis, no Postgres — the only candidate that needs neither), a first-class local tracker with
history, ratings, watchlist and progress modules, two-way Jellyfin sync, a tested export path, and
the cleanest maintenance profile in the field (6 open issues, 801 stars, daily pushes).

Rejected alternatives and the requirement each one broke:

- Yamtrack — no Jellyfin write-back. Only integrations/webhooks/jellyfin.py exists; there is no
  jellyfin_client / jellyfin_sync module and no PlayedItems call anywhere in the tree.
- Floppy (Yamtrack fork) — viable, but needs Redis alongside SQLite and carries 55 open issues.
  Export is CSV rather than a standard interchange format.
- Scrob — strong Trakt-format export, but requires Postgres (or a supervisord-bundled Postgres in
  the omnibus image), which the user ruled out.
- SIMKL and WeTrakr as primary — closed SaaS with no export: rebuilding the Trakt trap.

## Verified deployment facts

- [fact] Image ghcr.io/cenodude/crosswatch. Latest release v0.11.2, published 2026-08-20.
- [fact] Single container. Port 8787 (env WEB_PORT). Volume /config (env RUNTIME_DIR).
- [fact] Runs as a non-root user created in the Dockerfile (appuser, APP_UID).
- [fact] Dockerfile HEALTHCHECK is a TCP connect to 127.0.0.1:8787.
- [fact] No Redis, no external database. Storage is SQLite under /config.

## Verified provider auth models — these shape the plan

- [fact] Trakt: CrossWatch requires a USER-SUPPLIED client_id and client_secret
  (providers/auth/_auth_TRAKT.py, device_pin flow). No bundled credential. Since new Trakt apps are
  VIP-only and our token is dead, the live Trakt API path is CLOSED for us. Trakt data must arrive
  via the web export ZIP importer instead.
- [fact] SIMKL: CrossWatch ships a baked-in device-code client id
  (providers/auth/_auth_SIMKL.py, DEFAULT_PIN_CLIENT_ID, overridable via the
  CROSSWATCH_SIMKL_CLIENT_ID env var). No app registration needed — the SIMKL leg is frictionless.
- [fact] Jellyfin: API key. Plex: account token.
- [fact] Per-provider sync modules exist for CROSSWATCH itself, JELLYFIN, PLEX, SIMKL and TRAKT
  under providers/sync/, each with _history / _ratings / _watchlist / _progress submodules.

## Scope

Four legs, in dependency order:

1. Trakt rescue — get the history out of Trakt and into CrossWatch (web export ZIP path).
2. Jellyfin integration — two-way sync, the long-term player.
3. Plex integration — two-way sync while Plex is still in use.
4. SIMKL mirror — offsite redundancy for the watch state.

## Phases

### P0 — Trakt rescue (manual, human-only, BLOCKING)
**DONE 2026-08-21.** The Trakt account was the only copy of the history we did not control. Rescue complete; the measurement baseline is captured.

- [done] Trakt web UI export → `~/Downloads/trakt-json-export-zhorvath83.zip` (715542 bytes, SHA-256 `825b560fb53ad0e651169f0f2859c6f21da7ceec4f5625c04259000944ba425f`). `unzip -t` clean, 82 files.
- [done] Second copy in the file-level backup plane: `/Volumes/backups/trakt/trakt-json-export-zhorvath83.zip` (NAS 192.168.1.10:/backups, picked up by resticprofile at 01:00 → OVH Object Storage offsite). Subdir named after the SOURCE (trakt), not the consumer (crosswatch), because the archive outlives CrossWatch (P6 keeps it permanently). Both copies byte-identical (same SHA-256, 715542 bytes).
- [pending, human-only] Check whether the Trakt API application still exists in the account. Do not delete it — a new one cannot be created (VIP-only since 2026-07-30). NOT answered in P0; remains open. This is the only open item blocking the "live Trakt sync possible?" decision.

Ground-truth baseline measured from the `watched-history-*.json` event log (what CrossWatch imports), cross-checked against Trakt's own `user-stats.json` — all matched exactly, so the export lost no events:

- Total watch-events: 5639 (movie 310 / episode 5329)
- Unique movies: 174, unique episodes: 4688, unique shows: 249
- watched_at coverage: 5639/5639 = 100%; range 2010-12-04 .. 2026-07-29
- ratings / watchlist / lists / comments: all 0 (those Trakt features were unused — empty datasets, nothing to migrate). The migration is watch-history ONLY.
- 46 ZIP files are not ingested by the trakt importer; none are watch-history data loss (per-title summaries are duplicates of the event log; `collection-*` is ownership data out of P0 scope, preserved in the ZIP archive).

Full detail in [[crosswatch-implementation]] progress note.

### P1 — Proof of concept (MERGED INTO P2, human-approved 2026-08-21)
**MERGED INTO P2 (human-approved 2026-08-21).** The original plan — run CrossWatch locally out-of-cluster with "No manifests are written before this phase is green" — is superseded:

- No container runtime on the Mac (only an engine-less docker CLI in /usr/local/bin; no Docker Desktop / OrbStack / Podman / Colima). Nothing is installed on the Mac.
- An out-of-band `kubectl run` throwaway pod was rejected: the repo non-negotiable forbids manual kubectl changes outside documented bootstrap/recovery/Just flows.

P1 therefore runs ON the live in-cluster instance (see P2), treated as a PoC. The P1 measurements are performed there:

- Import the real Trakt export ZIP; record movie count, episode count, how many carry the original watched_at date, ratings count, watchlist count, and what failed to match — compared against the P0 ground-truth baseline (5639 events: 310 movie / 5329 episode; 174 / 4688 / 249 unique; 100% watched_at). Imported episode count must be within a stated tolerance of 4688.
- Exercise the export path (services/export.py, the backups API) and confirm a round trip: export, wipe, re-import, same counts.
- Inspect the UI and record whether it is a browsable library or primarily a sync dashboard.

On failure: git revert + Flux prune rolls everything back. ISOLATION CONDITION (non-optional, first round): ONLY CrossWatch itself deploys — NO SIMKL, Plex, or Jellyfin provider. Nothing that can write into the real libraries is wired until the import and round-trip are green. P3/P4/P5 remain separate later steps.
### P2 — Deploy to the cluster

- Namespace media, alongside jellyfin and plex.
- bjw-s app-template HelmRelease, minimal spec per the kubernetes guide.
- Image pinned to a release tag plus digest, with a renovate annotation.
- PVC for /config on local-hostpath. Not NFS.
- VolSync component wired through ks.yaml for the /config PVC.
- HTTPRoute on envoy-internal only. LAN-only: the app holds credentials for Plex, Jellyfin and
  SIMKL, and there is no reason to publish it.
- ExternalSecret via the onepassword-connect ClusterSecretStore for the Jellyfin API key, the Plex
  token and the SIMKL tokens.
- CiliumNetworkPolicy: custom-egress to the SIMKL and TMDB APIs, plus in-cluster egress to jellyfin
  and plex.

### P3 — Jellyfin integration

- Configure the Jellyfin provider with a scoped API key.
- Enable two-way history sync; verify a title marked watched in CrossWatch appears watched in
  Jellyfin, and vice versa.
- Record whether the write-back carries the original date or only a binary played flag.

### P4 — Plex integration

- Configure the Plex provider while Plex is still in service.
- Two-way sync, so the transition period does not diverge.

### P5 — SIMKL mirror

- Authorise SIMKL through the built-in device-code flow.
- Configure it as a mirror target for history and ratings.
- Explicitly not the source of truth. If SIMKL and CrossWatch disagree, CrossWatch wins.

### P6 — Retire plex-trakt-sync

- Only after P1 through P5 are verified.
- Remove kubernetes/apps/media/plex-trakt-sync in full: ks.yaml, app manifests, ExternalSecret,
  CiliumNetworkPolicy, the configmap and the PVC.
- Keep the Trakt export ZIP as a permanent archive.

## Risks

- [risk] HIGH — the CrossWatch local database backend is very new. The cw_platform/local_db tree
  first appeared on 2026-08-04, and the v-pre-db tag marks the state before it. The software is
  pre-1.0 (v0.11.2). We would be trusting the entire watch-state archive to a storage backend that
  is roughly two weeks old. Mitigation: VolSync on the /config PVC, a scheduled export into the
  file-level backup plane, and the immutable Trakt ZIP archive as the floor.
- [risk] MEDIUM — bus factor of one maintainer. Mitigation: AGPL, and the export path keeps exit
  open. CrossWatch also speaks Floppy and Scrob, so a later move is a sync job rather than a
  migration project.
- [risk] MEDIUM — Trakt could delete the account's API application, or the account itself, at any
  time. Mitigation: P0 is blocking and must be done first.
- [risk] LOW — the Trakt export ZIP is not proven to carry play counts. Episode-level watched_at,
  ratings and watchlist are evidenced; play count is not. Accept the loss if P1 confirms it.
- [risk] LOW — Jellyfin write-back may set only a played flag without the original date. The dates
  live in the tracker, which is the intended design, so this is cosmetic.

## Acceptance criteria

- The Trakt export ZIP exists in at least two locations outside the Trakt account, one of them in
  the file-level backup plane.
- P1 numbers are recorded here, and the imported episode count is within a stated tolerance of the
  ZIP's episode count.
- The export round trip reproduces the same counts after a wipe and re-import.
- CrossWatch reconciles in the cluster: the Flux Kustomization is Ready and the HelmRelease is
  Ready.
- A title marked watched in Jellyfin appears in CrossWatch within one sync interval, and the
  reverse also holds.
- The same holds for Plex while Plex is in service.
- SIMKL shows the history after the first mirror run.
- VolSync produces a restorable snapshot of the /config PVC.
- plex-trakt-sync is fully removed and nothing else references it.

## Open questions

- Does the Trakt API application still exist in the account? Decides whether a live Trakt sync is
  possible at all, or whether the ZIP is the only route. Answer in P0.
- Is the CrossWatch local tracker a browsable library in the UI, or primarily a sync dashboard?
  Answer in P1. The user asked for a tracker surface, not only a store.
- Does the CrossWatch Jellyfin write-back preserve original watch dates? Answer in P3.

## Relations

- relates_to [[trakt-watch-state-migration]]
- part_of [[k8s-workloads]]
- depends_on [[jellyfin]]
