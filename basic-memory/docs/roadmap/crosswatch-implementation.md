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
- [observation, confirmed 2026-08-21] The Trakt API application is DISABLED — proven dead, not "maybe gone". The human verified the account: the app no longer functions. The event log's last successful scrobble is 2026-07-29T18:53Z; today is 2026-08-21 = 23 days of complete silence. This is not inactivity — 2026-07 was the MOST active month in the last 8 months (146 events, ~4.7/day; 2026-05: 34, 2026-06: 27, 2026-07: 146, 2026-08: 0). The app was effectively taken offline on 07-29/30 when Trakt made app creation VIP-only; the 2026-08-20 token-refresh error in the pod log was a CONSEQUENCE, not the start. The live Trakt API path is PERMANENTLY and PROVEN gone — the ZIP is the only route. This settles the P0 open question (now a fact, not a hypothesis).
- [observation] plex-trakt-sync (ghcr.io/taxel/plextraktsync 0.35.17) is therefore a dead workload
  kept alive only by its Plex websocket loop.

The long-term direction is Plex to Jellyfin. The watch-state history must survive both the Trakt
shutdown and that migration, in a store the user owns.

## Decision

- [decision] CrossWatch (github.com/cenodude/CrossWatch, AGPL-3.0) becomes the primary watch-state
  tracker AND the sync engine. Chosen over Floppy and Scrob.
- [decision, confirmed stronger 2026-08-21] Jellyfin is NOT the primary store — it is a player. The tracker owns the truth. Confirmed stronger: the Jellyfin library has ZERO own watch-state, so Jellyfin is not even a secondary source — it is a pure consumer with zero own knowledge of watch history.
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
2. Jellyfin integration — bulk backfill first (empty library, one-way write), two-way sync later (phase e).
3. Plex integration — one-way Plex -> CrossWatch READ pulled into the import round (Plex is the only source for the ~3-week Trakt gap; see P4), two-way write-back later, only after verification.
4. SIMKL mirror — offsite redundancy for the watch state.

Phase order (driven by the 2026-08-21 facts, supersedes the raw P-number sequence):
- a) Trakt ZIP import -> 5639 events, but only through 2026-07-29 (the live API is gone).
- b) Plex -> CrossWatch -> one-way read, filling the 23-day gap (Plex is the only source).
- c) VERIFICATION -> does CrossWatch now own the full truth, Trakt plus the gap?
- d) CrossWatch -> Jellyfin -> one-way upload into the empty Jellyfin (bulk backfill).
- e) only after (c) and (d) verify, any two-way sync.

Deliberately released (not migrated, human decision 2026-08-21): the Trakt `collection-*` data and `hidden-progress-watched.json`. Evidence: every collection-movies entry carries a Plex GUID (e.g. `plex: {"guid": "5f5c997b72fd990041661999"}`); collected_at dates span 2021-2023 with last_collected_at 2023-05-17; ~85 movies / 230 shows / ~4395 collected episodes. This is a 3-year-old stale, DERIVED snapshot of the Plex library generated by the old plex-trakt-sync scanning Plex - not human-curated. "What you own" lives live in Plex and Jellyfin, which are the truth source. hidden-progress-watched.json has 1 entry (Doctor Who hidden from progress, 2019) - a trivial UI preference. Zero information loss; the ZIP keeps it as a permanent archive (P6).

## Phases

### P0 — Trakt rescue (manual, human-only, BLOCKING)
**DONE 2026-08-21.** The Trakt account was the only copy of the history we did not control. Rescue complete; the measurement baseline is captured.

- [done] Trakt web UI export → `~/Downloads/trakt-json-export-zhorvath83.zip` (715542 bytes, SHA-256 `825b560fb53ad0e651169f0f2859c6f21da7ceec4f5625c04259000944ba425f`). `unzip -t` clean, 82 files.
- [done] Second copy in the file-level backup plane: `/Volumes/backups/trakt/trakt-json-export-zhorvath83.zip` (NAS 192.168.1.10:/backups, picked up by resticprofile at 01:00 → OVH Object Storage offsite). Subdir named after the SOURCE (trakt), not the consumer (crosswatch), because the archive outlives CrossWatch (P6 keeps it permanently). Both copies byte-identical (same SHA-256, 715542 bytes).
- [done, human-verified 2026-08-21] The Trakt API application is DISABLED (proven, not hypothesis). The live Trakt API path is permanently gone; the ZIP is the only route. Last successful scrobble 2026-07-29T18:53Z; the 23-day silence confirms it (see Why). This settles the "live Trakt sync possible?" question: it is NOT possible. Do not discard the app entry — a new one cannot be created (VIP-only since 2026-07-30).

Ground-truth baseline measured from the `watched-history-*.json` event log (what CrossWatch imports), cross-checked against Trakt's own `user-stats.json` — all matched exactly, so the export lost no events:

- Total watch-events: 5639 (movie 310 / episode 5329)
- Unique movies: 174, unique episodes: 4688, unique shows: 249
- watched_at coverage: 5639/5639 = 100%; range 2010-12-04 .. 2026-07-29
- ratings / watchlist / lists / comments: all 0 (those Trakt features were unused — empty datasets, nothing to migrate). The migration is watch-history ONLY.
- 46 ZIP files are not ingested by the trakt importer; none are watch-history data loss (per-title summaries are duplicates of the event log; `collection-*` is ownership data out of P0 scope, preserved in the ZIP archive).

Full detail in [crosswatch-implementation progress note](memory://home-ops/docs/progress/crosswatch-implementation).

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
- [redefined 2026-08-21] This is NOT a steady-state sync test. The Jellyfin library has ZERO own watch-state (confirmed by the human), so the operation is a BULK BACKFILL: mark ~174 movies + 4688 episodes as watched in an empty Jellyfin, starting from nothing.
- One-way CrossWatch -> Jellyfin write ONLY (decision C); two-way sync is a later step (phase e), only after the backfill is verified.
- Record whether the write-back carries the original date or only a binary played flag.
- [risk note 2026-08-21] This leg is LESS risky, not more: the Jellyfin library has no before-state to lose, so a botched upload has nothing to overwrite. Rollback = delete what we wrote. Do not over-caution here later.

### P4 — Plex integration

- [priority change 2026-08-21] P4 ONE-WAY READ leg is pulled FORWARD into the same round as P2 (the Trakt import), no longer after Jellyfin (P3). The Trakt ZIP ends 2026-07-29T18:53Z and does NOT span the last ~3 weeks: the API app was taken offline on 07-29/30, so ~100+ events (at the July pace of ~4.7/day) never reached Trakt. That gap is NOT lost — plex-trakt-sync read FROM Plex and pushed TO Trakt, so Plex own watch-state is intact and is the ONLY source for the gap (it grows ~5 events/day). The Plex -> CrossWatch one-way read must therefore run in the import round to make CrossWatch complete. The one-way direction (decision C below) is UNCHANGED; two-way write-back stays a later step, after verification.

- Configure the Plex provider while Plex is still in service (device-PIN flow, providers/auth/_auth_PLEX.py v0.11.2; PLEX_PIN_URL https://plex.tv/api/v2/pins, self-generated client_id when none is set - no app registration, ~30s).
- [decision 2026-08-21] FIRST round is ONE-WAY Plex -> CrossWatch. Write-back (two-way) is enabled ONLY after the CrossWatch-side state is verified. Rationale is NOT config cost (that is trivial) but IRREVERSIBILITY: if the Plex leg runs two-way while 5639 events pour in from the Trakt import, the import overwrites the Plex library watch state. The toggle can be flipped back any time; a scrambled library cannot.
- [finding 2026-08-21, source-verified on v0.11.2] Direction is a `mode` field on the SAME sync-pair, not a separate pair type: cw_platform/orchestrator/_pairs.py:375 (`mode = pair.get("mode") or "one-way"`); _pairs.py:469-492 branches `two-way` vs one-way on the same pair; api/syncAPI.py:1918/1929 (PairIn/PairPatch.mode), :2027 (default one-way), :2102 (PUT /pairs/{id} mutates in place). So the pair can be created one-way and later flipped to two-way by PATCHing `mode` - no re-wiring. Caveat: the per-pair scope key changes (one-way directional A-B vs two-way symmetric), so state keyed on the old scope does not carry over; the pair entity persists.

### P5 — SIMKL mirror

- Authorise SIMKL through the built-in device-code flow.
- Configure it as a mirror target for history and ratings.
- Explicitly not the source of truth. If SIMKL and CrossWatch disagree, CrossWatch wins.
- [decision 2026-08-21, human] P5 stays UNCHANGED. Concern raised and recorded (not to be re-litigated): SIMKL is a closed SaaS with no export - a write-only redundancy leg you cannot restore FROM (the roadmap itself calls this "rebuilding the Trakt trap"). The real redundancy is VolSync on /config + the scheduled export + the immutable Trakt ZIP archive; SIMKL is a one-way mirror only. The human understood this and decided P5 remains as written.

### P6 — Retire plex-trakt-sync

- Only after P1 through P5 are verified.
- [justification update 2026-08-21] plex-trakt-sync is a PROVEN DEAD workload, not "wait until the replacement works": no API app exists (disabled, proven) and no scrobble since 2026-07-29. The withdrawal gate (wait for P1-P5) lost its original meaning — there is nothing left for plex-trakt-sync to sync TO. No urgency to withdraw it (it is inert), but the justification is now dead-workload status, not replacement readiness. Note only — do not act on it this round.
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

## Upstream guidance (wiki.crosswatch.app, verified 2026-08-21)

Manufacturer best-practices and the provider/sync model read from the official wiki. These confirm or rewrite decisions in this roadmap — the manufacturer's word, not our preference. Operational details (deployment env, /healthz, CW_RESET_AUTH_ONCE) live in the progress note.

### Direction and removal — confirms decision C
- Default direction is "Media server -> tracker (one-way)" — exactly our (C) decision (Plex -> CrossWatch one-way). Manufacturer recommendation, not our preference.
- "Do not switch to tracker -> media server unless you have a clear reason."
- Removal modes: `source_deletes` is the DEFAULT and the safe mode; `mirror` removes from the Destination everything absent in the Source — dangerous.
- "Two-way sync and mirror removals can spread bad matches and unwanted deletes."

### Steady-state architecture — REWRITES the roadmap resting state
- "History: perform a one-way seed once. Then disable History and use scrobbling."
- The roadmap spoke throughout of continuous two-way history-sync. The manufacturer specifies a DIFFERENT steady state: history-sync is a ONE-TIME seed; History is then DISABLED on the pair, and scrobbling carries new events from there. Two-way history-sync is a migration tool, not the resting mode. Affects P3 and phase e.
- Verify the local-tracker scrobble-sink question (see Open questions) before building on this architecture.

### Dry run is a mandatory first step at P3
- "Use Dry run before enabling writes." The safest config is "one-way, one feature, dry run on", media server source + tracker destination.
- For the Jellyfin bulk backfill (P3), Dry run is NOT optional — it is the required first step: it validates the match plan before any write into the empty library.
- "Only sync data into a media server when the item already exists in that library" — the manufacturer's own caveat, which confirms (does not retire) the open question of whether the Jellyfin library holds the same content as Plex.

### Pair model — architectural backing for "tracker owns the truth"
- The CrossWatch local tracker is SOURCE and DESTINATION for all four features, fully two-way. The "tracker owns the truth" decision is therefore ARCHITECTURALLY supported, not merely intent.
- Per-pair controls: sync direction, per-feature enablement (Watchlist/Ratings/History/Progress), Dry run, source vs mirror delete mode, and separate write-gates for additions and removals.

### Recovery tools (exist; lower the risk of P3/P4 writes)
- "Rebuild sync state" and "Retry provider items" are the documented recovery tools.
- Reset triggers include an "unexpected large remove plan" — a guardrail against a runaway delete.

### Provider matrix — our data shape avoids the limits
- JELLYFIN: History OK (movies, episodes); Ratings DISABLED; "No native watchlist; Playlist is episode-only." Credential: server connection + access token. We need only History, and our ratings and watchlist are both zero, so our data exactly avoids every Jellyfin limitation.
- PLEX: History OK, Ratings OK, Watchlist OK, Progress OK. Credential: device PIN. "Uses Plex Discover. Progress removal can be limited."
- SIMKL: History OK; Ratings title-level only ("No season or episode ratings"); Progress only via Progress Manager. Credential per wiki: OAuth client id + secret + access token. This CONTRADICTS the code-read in "Verified provider auth models" (built-in DEFAULT_PIN_CLIENT_ID device-code, overridable via CROSSWATCH_SIMKL_CLIENT_ID) — see Open questions. Not resolved this round.
- TRAKT: "History writes can also add to Trakt Collections." Moot for us — the Trakt road is shut.
- Experimental providers: Floppy, Nuvio, Kodi, Stremio, PunchPlay, Scrob.
- Jellyfin/Emby metadata is TMDb, so Jellyfin matching NEEDS TMDB — the allow-world egress label is justified for the matching path (narrow it to custom-egress later; see Follow-up in the progress note).

### Scrobbling — and an open question
- Watcher (polling) sources: Emby, Jellyfin, Plex, Kodi, Scrob. Polling is OUTGOING, so no inbound connection to CrossWatch is needed — better for our network posture.
- Webhook sources: Emby, Jellyfin, Plex — BUT the Plex webhook needs Plex Pass and the Emby webhook needs Emby Premiere. Watcher does NOT need Plex Pass.
- Progress reporting (Watcher only): 25% steps.
- The wiki scrobbling "tracker targets" list (MDBList, PunchPlay, Scrob, SIMKL, Trakt) does NOT include the CrossWatch local tracker — see Open questions.

## Open questions

- [resolved 2026-08-21, human-verified] Does the Trakt API application still exist in the account? ANSWER: no — the app is disabled (proven). The ZIP is the only route; a live Trakt sync is not possible.
- [resolved 2026-08-21, human-verified] Did the human use JELLYFIN as well as Plex during the 23-day Trakt gap? ANSWER: no — the Jellyfin library has ZERO own watch-state (confirmed). Plex is the single source for the 23-day gap; there is nothing to reconcile across players.
- [open, human-only, measured at PoC] Does the Jellyfin library hold the SAME content as the Plex library? If not, some of the ~4862 items do not exist in Jellyfin and cannot be marked watched. This is a matching question, not decidable in advance. DO NOT GUESS.
- Is the CrossWatch local tracker a browsable library in the UI, or primarily a sync dashboard?
  Answer in P1. The user asked for a tracker surface, not only a store.
- Does the CrossWatch Jellyfin write-back preserve original watch dates? Answer in P3.
- [open, upstream-contradiction, P5] SIMKL credential model: the wiki says SIMKL needs an OAuth client id + secret + access token, contradicting the code-read in "Verified provider auth models" (built-in DEFAULT_PIN_CLIENT_ID device-code, overridable via CROSSWATCH_SIMKL_CLIENT_ID). Resolve before P5. Not resolved this round.
- [open, must-verify-before-building] Can the CrossWatch LOCAL tracker be a scrobble sink? The wiki scrobbling tracker-targets list (MDBList, PunchPlay, Scrob, SIMKL, Trakt) omits the CrossWatch local tracker. If it cannot be a scrobble sink, then "seed once, then use scrobbling" means scrobbling INTO AN EXTERNAL tracker, which contradicts the local tracker owning the truth. The pair-model makes the local tracker a two-way sync endpoint, but scrobble-sink capability is a separate question. VERIFY before building on the seed-then-scrobble architecture; do NOT decide either way yet.

## Relations

- relates_to [[trakt-watch-state-migration]]
- part_of [[k8s-workloads]]
- depends_on [[jellyfin]]
