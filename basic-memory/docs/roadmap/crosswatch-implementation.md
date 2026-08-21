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

Nothing else may start before this is done. The Trakt account is the only copy of the history that
we do not control.

- Trakt web UI, Settings then Data, "Export now". Download the ZIP.
- Store it outside the cluster AND drop a copy into the file-level backup plane
  (/backups tree, picked up by resticprofile into OVH Object Storage).
- Check in the Trakt account whether the API application still exists. Do not delete it — a new one
  cannot be created. Record the answer here.

### P1 — Proof of concept, outside the cluster (GATE)

No manifests are written before this phase is green.

- Run ghcr.io/cenodude/crosswatch v0.11.2 locally with a throwaway /config volume.
- Import the real Trakt export ZIP.
- Measure and record: movie count, episode count, how many carry the original watched_at date,
  ratings count, watchlist count, and what failed to match.
- Exercise the export path (services/export.py, the backups API) and confirm a round trip:
  export, wipe, re-import, same counts.
- Inspect the UI and record whether it is a browsable library or primarily a sync dashboard.

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
