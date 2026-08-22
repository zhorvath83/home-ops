---
title: crosswatch-implementation
type: progress_note
permalink: home-ops/docs/progress/crosswatch-implementation
tags:
- crosswatch
- media
- trakt
- jellyfin
- plex
- punchplay
- roadmap
- completed
---

> Merged note. The roadmap lived at `docs/roadmap/crosswatch-implementation` and the execution
> record at `docs/progress/crosswatch-implementation`; on completion both were merged into this
> single note per the project's "Fully implemented roadmap items → progress/" convention, and the
> roadmap note was deleted.

# CrossWatch implementation — completed

## Metadata (observation-form)

- [topic] Replace the dead Trakt sync with CrossWatch as the primary watch-state tracker — Trakt history rescue, in-cluster deploy, provider wiring
- [status] done
- [priority] high
- [area] k8s-workloads / media, resticprofile-backup
- [created] 2026-08-21
- [completed] 2026-08-22 — all phases declared complete by the human; per-leg evidence separated below into machine-verified vs human-declared
- [branch] feat/crosswatch (merged to main)
- [decided_by] human, 2026-08-21 (candidate comparison in [[trakt-watch-state-migration]])

## Why — the Trakt plane was proven dead, not merely at risk

- [observation] The stored Trakt OAuth token stopped refreshing: `Unauthorized - OAuth token refresh failed: invalid_grant - session not found`, logged 2026-08-20 11:29 and 14:55 in `/app/config/plextraktsync.log` of deployment `plex-trakt-sync` in namespace `media`.
- [observation] Trakt made new API application creation VIP-only on 2026-07-30; a replacement credential cannot be issued.
- [observation, human-verified 2026-08-21] The Trakt API application is DISABLED — proven dead, not "maybe gone". Last successful scrobble 2026-07-29T18:53Z. The 23-day silence is not inactivity: 2026-07 was the most active month in eight (2026-05: 34, 2026-06: 27, 2026-07: 146 ≈ 4.7/day, 2026-08: 0). The app was effectively taken offline on 07-29/30; the 2026-08-20 token-refresh error was a consequence, not the start. The ZIP export was therefore the ONLY route out.
- [observation] `plex-trakt-sync` (ghcr.io/taxel/plextraktsync 0.35.17) became a dead workload kept alive only by its Plex websocket loop.

The long-term direction is Plex → Jellyfin. The watch state had to survive both the Trakt shutdown and that migration, in a store the user owns.

## Decisions

- [decision] CrossWatch (github.com/cenodude/CrossWatch, AGPL-3.0) is the primary watch-state tracker AND the sync engine. Chosen over Floppy and Scrob.
- [decision, hardened 2026-08-21] Jellyfin is NOT the store — it is a player. The tracker owns the truth. Hardened because the Jellyfin library has ZERO own watch-state, so it is not even a secondary source: a pure consumer.
- [decision, superseded 2026-08-22] **PunchPlay replaces SIMKL as the offsite mirror.** The sync now goes to PunchPlay. The original P5 decision (SIMKL as a write-only mirror, explicitly not the source of truth) is superseded; the "never the source of truth" constraint carries over unchanged to PunchPlay. Side effect: the unresolved SIMKL credential-model contradiction (below) is moot — SIMKL is not wired.
- [decision] One-way direction first, everywhere. Write-back (two-way) only after the CrossWatch-side state is verified. The rationale is irreversibility, not config cost: a scrambled library cannot be un-scrambled, a toggle can be flipped back any time.

Rationale against the user's hard requirements: single container with its own SQLite store (no Redis, no Postgres — the only candidate needing neither), a first-class local tracker with history/ratings/watchlist/progress modules, two-way Jellyfin sync, a tested export path, and the cleanest maintenance profile in the field (6 open issues, 801 stars, daily pushes).

Rejected alternatives and the requirement each broke:

- Yamtrack — no Jellyfin write-back. Only `integrations/webhooks/jellyfin.py` exists; no jellyfin_client / jellyfin_sync module, no PlayedItems call anywhere in the tree.
- Floppy (Yamtrack fork) — viable, but needs Redis alongside SQLite, carries 55 open issues, and exports CSV rather than a standard interchange format.
- Scrob — strong Trakt-format export, but requires Postgres (or a supervisord-bundled Postgres in the omnibus image), which the user ruled out.
- SIMKL and WeTrakr as primary — closed SaaS with no export: rebuilding the Trakt trap.

## Verified deployment facts (v0.11.2)

- [fact] Image `ghcr.io/cenodude/crosswatch`. Release tag has NO `v` prefix — `0.11.2` exists, `v0.11.2` does not.
- [fact] Single container. Port 8787 (`WEB_PORT`). Volume `/config` (`RUNTIME_DIR`). SQLite under `/config`; no Redis, no external database.
- [fact] Runs as `appuser` built in the Dockerfile at `APP_UID=1000`.
- [fact] Health endpoint `GET /healthz` → `{"ok":true,"status":"ok"}`, unauthenticated. The Dockerfile HEALTHCHECK is only a TCP connect to 127.0.0.1:8787.
- [fact] Deployment contract (wiki: installation/docker-setup): `CONFIG_BASE=/config`, `WEB_HOST=0.0.0.0`, `WEB_PORT=8787`, `RUNTIME_DIR=/config`, `APP_UID/APP_GID=1000`, `APP_USER/APP_GROUP=appuser`, `APP_DIR=/app`, `TZ` (listed required), `RELOAD=no`, `CW_RESET_AUTH_ONCE=1`. "Always persist /config" — state lives in `config.json`, `state.json`, `statistics.json`. WARNING: do NOT set the container `user` property together with the `APP_*` vars.
- [fact] `CW_RESET_AUTH_ONCE=1` is the documented auth/session wipe-on-restart path. NOT set here — it would also wipe the admin the human created. Recorded as the known lockout-recovery path.

## Verified provider auth models

- [fact] Trakt: CrossWatch requires a USER-SUPPLIED client_id + client_secret (`providers/auth/_auth_TRAKT.py`, device_pin flow). No bundled credential. With new Trakt apps VIP-only and our token dead, the live Trakt API path was CLOSED — data had to arrive via the web-export ZIP importer.
- [fact] SIMKL: baked-in device-code client id (`providers/auth/_auth_SIMKL.py`, `DEFAULT_PIN_CLIENT_ID`, overridable via `CROSSWATCH_SIMKL_CLIENT_ID`). Moot — SIMKL was not wired (PunchPlay instead).
- [fact] Jellyfin: API key. Plex: account token / device PIN (`providers/auth/_auth_PLEX.py`, `PLEX_PIN_URL https://plex.tv/api/v2/pins`, self-generated client_id when none is set — no app registration, ~30s).
- [fact] Per-provider sync modules exist for CROSSWATCH itself, JELLYFIN, PLEX, SIMKL and TRAKT under `providers/sync/`, each with `_history` / `_ratings` / `_watchlist` / `_progress` submodules.
- [fact] Direction is a `mode` field on the SAME sync-pair, not a separate pair type: `cw_platform/orchestrator/_pairs.py:375` (`mode = pair.get("mode") or "one-way"`), `:469-492` branches two-way vs one-way on the same pair; `api/syncAPI.py:1918/1929` (PairIn/PairPatch.mode), `:2027` (default one-way), `:2102` (PUT /pairs/{id} mutates in place). A pair can be created one-way and later flipped by PATCHing `mode` — no re-wiring. Caveat: the per-pair scope key changes (one-way directional A-B vs two-way symmetric), so state keyed on the old scope does not carry over; the pair entity persists.

## P0 — Trakt rescue (done 2026-08-21)

The Trakt account held the only copy of the history we did not control.

- [done] Trakt web-UI export → `~/Downloads/trakt-json-export-zhorvath83.zip` — 715542 bytes, SHA-256 `825b560fb53ad0e651169f0f2859c6f21da7ceec4f5625c04259000944ba425f`. `unzip -t` clean, 82 files.
- [done] Second copy in the file-level backup plane: `/Volumes/backups/trakt/trakt-json-export-zhorvath83.zip` (NAS 192.168.1.10:/backups, SMB-mounted on the Mac). Byte-identical (same SHA-256, same size). The subdir is named after the SOURCE (`trakt`), not the consumer (`crosswatch`), because the archive outlives CrossWatch.
- [done] Third copy, automatic + offsite: the in-cluster `resticprofile` workload backs up the whole `/backups` tree at 01:00 daily into OVH Object Storage.

### Importer coverage vs actual ZIP contents

CrossWatch trakt-importer filename patterns (verified on v0.11.2, L95-104):

- `watched-history-*.json` → MATCH (`watched-history-1..23.json`, 23 files) — the event log
- `ratings*.json` → MATCH (4 files), all empty `[]`
- `watchlist*.json` → 0 match. Watchlist data lives in `lists-watchlist.json` (caught by `lists*`), empty `[]`
- `lists*.json` → MATCH (4 files), all empty `[]`
- `comments*.json` → MATCH (5 files), all empty `[]`

46 ZIP files are NOT ingested; none is watch-history loss:

- `watched-movies.json` / `watched-shows.json` / `watched-playback.json` — deduplicated per-title summaries of events already in `watched-history-*`.
- `collection-*.json` (20 files: 85 movies, 230 shows, ~4395 collected episodes) + `hidden-progress-watched.json` — ownership data, out of scope (see "Deliberately released"). Preserved in the ZIP archive.
- `user-*`, `hidden-*`, `network-*`, `likes-*`, `notes-*` — account metadata or empty `[]`.

### Ground-truth baseline (the import reference)

Measured from the `watched-history-*.json` event log, cross-checked against Trakt's own `user-stats.json`:

- Total watch-events: **5639** (23 files: 22×250 + 139)
- Movie events: 310 / unique movies: 174 (→ 136 rewatch events; playcount preserved at event level)
- Episode events: 5329 / unique episodes: 4688 / unique shows: 249
- `watched_at` coverage: 5639/5639 = **100%**; range 2010-12-04T02:00:00Z .. 2026-07-29T18:53:00Z
- action breakdown: scrobble 4642, watch 997
- ratings / watchlist / lists / comments: all **0** — those Trakt features were unused, so the migration is watch-history ONLY

Cross-check: movie events 310 = `movies.plays` 310; episode events 5329 = `episodes.plays` 5329; unique movies 174 = `movies.watched`; unique episodes 4688 = `episodes.watched`; unique shows 249 = `shows.watched`. All MATCH → the export lost no events. The earlier "3-episode gap" (5326 vs 5329) and "249 vs 248 shows" were drift in the `watched-shows.json` SUMMARY file, not the event log; the event log is authoritative.

### Deliberately released (human decision 2026-08-21)

The Trakt `collection-*` data and `hidden-progress-watched.json` were NOT migrated. Evidence: every `collection-movies` entry carries a Plex GUID (e.g. `plex: {"guid": "5f5c997b72fd990041661999"}`); `collected_at` spans 2021-2023 with `last_collected_at` 2023-05-17. This is a 3-year-old stale, DERIVED snapshot of the Plex library produced by the old plex-trakt-sync scanning Plex — not human-curated. "What you own" lives live in Plex and Jellyfin. `hidden-progress-watched.json` has 1 entry (Doctor Who hidden from progress, 2019) — a trivial UI preference. Zero information loss; the ZIP keeps both permanently.

### The data gap the ZIP cannot cover

The ZIP ends 2026-07-29T18:53Z. ~3 weeks — ~100+ events at the July pace — never reached Trakt. That data was NOT lost: plex-trakt-sync read FROM Plex and pushed TO Trakt, so Plex's own watch-state stayed intact and was the ONLY source for the gap. This is why the Plex → CrossWatch one-way read was pulled forward into the import round instead of running after Jellyfin.

## P1 → merged into P2 (human-approved 2026-08-21)

The roadmap originally specified P1 as a local out-of-cluster PoC with "no manifests before this phase is green". That was impossible and was dropped:

- No container runtime on the Mac (only an engine-less docker CLI in `/usr/local/bin`; no Docker Desktop / OrbStack / Podman / Colima), and nothing would be installed.
- An out-of-band `kubectl run` throwaway pod was rejected: the repo non-negotiable forbids manual kubectl changes outside documented bootstrap/recovery/Just flows.

P1 therefore ran ON the in-cluster instance, treated as a PoC, under a non-optional ISOLATION CONDITION for round 1: only CrossWatch itself deployed — no provider that can write into a real library — until the import was green. Rollback path: git revert + Flux prune.

## P2 — in-cluster deploy (done, live-verified)

`kubernetes/apps/media/crosswatch/`: `ks.yaml` + `app/{kustomization,helmrelease}.yaml`. Registered in `kubernetes/apps/media/kustomization.yaml`. The HTTPRoute was later inlined into the HelmRelease `route:` block (6439c593d), so there is no separate `httproute.yaml`.

Final deployed shape:

- Image pinned `ghcr.io/cenodude/crosswatch:0.11.2@sha256:52ee71679284c55a712d9127e1e64e74b71f563c499f3e8b01e554219a88a337` with a renovate docker-datasource annotation.
- `/config` PVC via the shared `components/volsync` (local-hostpath, 5Gi, `APP=crosswatch`); no NFS. The volsync component brings its own Kopia-repo ExternalSecret, hence `ks.yaml` `dependsOn` onepassword-connect + democratic-csi.
- Route: `crosswatch.${PUBLIC_DOMAIN}` on **envoy-internal only** (LAN). No external-dns annotation — the envoy-internal route is invisible to ExternalDNS (which watches `--gateway-name=envoy-external`), and LAN split DNS comes from k8s-gateway, which does not read the annotation. Homepage annotations on the route (`gethomepage.dev/*`, icon `crosswatch.svg`, verified to exist in the selfhst set as a real 940-byte SVG).
- Hardening: `runAsNonRoot`, UID/GID/fsGroup **1000**, `readOnlyRootFilesystem`, all capabilities dropped, `seccompProfile: RuntimeDefault`, no service-account token, emptyDir `/tmp` (Starlette spools multipart uploads there).
- Probes: liveness/readiness/startup all `httpGet /healthz` — proves the app SERVES, not just that the port is open. `tcpSocket` was the round-1 placeholder, replaced in 8829522c1.
- `TZ` is intentionally NOT in the manifest: the k8tz webhook injects it (verified `TZ=Europe/Budapest` on the live pod), even though the upstream wiki lists TZ as required.
- Memory limit 768Mi (raised from 512Mi in c5806eef7 during the import round; the pre-deploy note had flagged 512Mi as the likely ceiling for a 5639-event SQLite import).
- Network posture: pod label `ingress.home.arpa/allow-gateway-internal: "true"` (admitted by the port-agnostic `ingress-from-gateway-internal` CCNP, AD-023) plus `egress.home.arpa/allow-world: "true"`. No app-level CiliumNetworkPolicy. The allow-world label is WIDER than the original P2 plan ("custom-egress to the SIMKL and TMDB APIs") — justified because Jellyfin/Emby metadata is TMDb, so the Jellyfin matching path needs TMDB. See "Carried forward".
- No ExternalSecret: provider credentials and the admin account live inside the app's own `/config` state, entered through the UI. See "Carried forward".

Resolved pre-deploy hypotheses (evidence, so they are not re-litigated):

- **UID**: the image builds `appuser` at `APP_UID=1000`, but the repo-dominant convention is 10001. Deployed at 10001 first; the entrypoint logged `id: cannot find name for user ID 10001`. Fixed to 1000 in 8829522c1 / PR #4227 (merged a65cbbaaf) — the warning is gone and the entrypoint logs `as appuser:appuser (1000:1000)`.
- **TMDB egress at import time**: not needed. The importer does not call TMDB (`services/importer.py` v0.11.2), and the app boots with zero providers (`cw_platform/config_base.py`). The Trakt export itself carries trakt/imdb/tmdb/tvdb IDs, so matching needs no external call — only posters do.
- **Service name / backendRef**: obsolete question. The HelmRelease `route:` block binds `backendRefs` to the chart-generated Service via `identifier: app`.

Import API path (3 steps, `services/importer.py` v0.11.2): `GET /api/import/options` → `POST /api/import/preview` (multipart `file`, `source`, `target_instance`) → `GET /api/import/preview/{id}` → `POST /api/import/commit`. Reached from the Mac over the envoy-internal LAN route, not `kubectl port-forward`.

Auth model (operational): CrossWatch requires login (`/login`: username/password/totp/remember). A first-run open window existed for the first minutes after boot; after it closed, `GET /` 302s to `/login` and every `/api/*` returns 401 except `/healthz`. The human completed first-run setup and created a local admin.

## P3 / P4 / P5 — provider legs (human-declared complete 2026-08-22)

Declared done by the human on 2026-08-22. No measurement numbers were reported, so the counts below are the reference baseline, not a measured result — anything needing exact figures must be re-measured in the UI.

- **Trakt ZIP import — done.** Reference: 5639 events (310 movie / 5329 episode; 174 / 4688 / 249 unique). Imported counts and the unmatched-row count were not recorded.
- **Plex → CrossWatch one-way read — done.** This is the leg that fills the 23-day gap the ZIP cannot cover; Plex was the only source for it. Direction stayed one-way as decided.
- **Jellyfin — wired in.** Redefined during planning from "sync test" to BULK BACKFILL: the Jellyfin library had zero own watch-state, so this marks ~174 movies + 4688 episodes watched in an empty library. Lower risk, not higher: no before-state to lose, rollback = delete what we wrote. Not recorded: the dry-run match plan, how many items actually matched, and whether the write-back carried the original date or only a played flag.
- **PunchPlay instead of SIMKL — the mirror leg.** The sync goes to PunchPlay; SIMKL was never wired. PunchPlay appears in the upstream wiki both as an experimental provider and in the scrobbling tracker-targets list. Mirror-only status is unchanged: if PunchPlay and CrossWatch disagree, CrossWatch wins.

The concern recorded against the original SIMKL plan applies to any closed mirror and is NOT re-litigated: a write-only mirror you cannot restore FROM is not redundancy. The real redundancy here is VolSync on `/config` + the export path + the immutable Trakt ZIP archive.

## P6 — retire plex-trakt-sync (partially done)

- `plex-trakt-sync` is scaled to **0/0** in namespace `media` (verified 2026-08-22) — inert.
- Its manifests are still in the repo at `kubernetes/apps/media/plex-trakt-sync` (ks.yaml, app manifests, ExternalSecret, CiliumNetworkPolicy, configmap, PVC). The full removal was not part of this closure — see "Carried forward".
- Justification note: the workload is PROVEN DEAD (no API app, no scrobble since 2026-07-29), so the original withdrawal gate ("wait until the replacement works") lost its meaning. There is no urgency — it is inert — but the reason to remove it is dead-workload status, not replacement readiness.
- The Trakt export ZIP is kept as a permanent archive regardless.

## Live verification 2026-08-22 (read-only, machine-verified)

- Pod `crosswatch-67c4875b74-gtqsr` **1/1 Running**, 0 restarts, 21h uptime, IP 10.244.0.9, node k8s-cp0.
- Flux `Kustomization/crosswatch` **Ready** (`refs/heads/main@sha1:8ee1142f`); `HelmRelease/crosswatch` **Ready** (app-template 5.1.0, release `.v5`).
- PVC `crosswatch` **Bound**, 5Gi, `democratic-csi-local-hostpath`.
- VolSync `ReplicationSource/crosswatch`: last sync **2026-08-22T19:04:07Z**, duration 4m7s — the `/config` backup leg runs.
- `deployment.apps/plex-trakt-sync` **0/0** — inert.

Earlier round-1 verification (2026-08-21): HTTPRoute Accepted=True / ResolvedRefs=True, LAN DNS resolves `crosswatch.${PUBLIC_DOMAIN}` to the envoy-internal VIP 192.168.1.18, HTTPS GET / → 200 with TLS verify OK, `GET /healthz` → 200 unauthenticated.

## Acceptance criteria — final status

| Criterion | Status | Evidence |
|---|---|---|
| Trakt ZIP in ≥2 locations outside Trakt, one in the file-level backup plane | met | `~/Downloads` + `/Volumes/backups/trakt/`, identical SHA-256; resticprofile carries it offsite |
| Import counts recorded, imported episodes within tolerance of the ZIP | **not recorded** | import declared done by the human; no numbers captured — re-measure in the UI if needed |
| Export round-trip reproduces the same counts after wipe + re-import | **not done** | never exercised |
| Flux Kustomization + HelmRelease Ready | met | both Ready 2026-08-22 |
| A title marked watched in Jellyfin appears in CrossWatch within one sync interval, and the reverse | **partially** | Jellyfin is wired; steady state is one-way by decision, and the upstream steady state is seed-once-then-scrobble, so the two-way phrasing of this criterion was superseded |
| Same for Plex while Plex is in service | met (one-way) | Plex → CrossWatch read done; write-back deliberately not enabled |
| Mirror shows the history after the first run | met, changed target | PunchPlay instead of SIMKL |
| VolSync produces a restorable snapshot of `/config` | sync verified, restore untested | ReplicationSource synced 2026-08-22T19:04:07Z; no restore drill |
| plex-trakt-sync fully removed, nothing references it | **not done** | scaled to 0/0; manifests still in the repo |

## Upstream guidance (wiki.crosswatch.app, verified 2026-08-21)

The manufacturer's word, kept because it governs the steady state.

**Direction and removal** — confirms the one-way decision. Default direction is "media server → tracker (one-way)". "Do not switch to tracker → media server unless you have a clear reason." Removal modes: `source_deletes` is the DEFAULT and safe mode; `mirror` removes from the Destination everything absent in the Source — dangerous. "Two-way sync and mirror removals can spread bad matches and unwanted deletes."

**Steady-state architecture — this REWROTE the plan.** "History: perform a one-way seed once. Then disable History and use scrobbling." The roadmap had assumed continuous two-way history-sync; the manufacturer specifies history-sync as a ONE-TIME seed, History then DISABLED on the pair, with scrobbling carrying new events. Two-way history-sync is a migration tool, not the resting mode.

**Dry run before writes.** "Use Dry run before enabling writes." Safest config: one-way, one feature, dry run on, media server as source. "Only sync data into a media server when the item already exists in that library."

**Pair model** — architectural backing for "tracker owns the truth": the CrossWatch local tracker is SOURCE and DESTINATION for all four features, fully two-way. Per-pair controls: direction, per-feature enablement (Watchlist/Ratings/History/Progress), dry run, source vs mirror delete mode, separate write-gates for additions and removals.

**Recovery tools** — "Rebuild sync state" and "Retry provider items". Reset triggers include an "unexpected large remove plan", a guardrail against a runaway delete.

**Provider matrix** — our data shape avoids the limits. JELLYFIN: History OK (movies, episodes); Ratings DISABLED; "no native watchlist; Playlist is episode-only" — we need only History, and ratings/watchlist are both zero. PLEX: History/Ratings/Watchlist/Progress all OK; uses Plex Discover; progress removal can be limited. SIMKL: History OK, ratings title-level only (moot — not wired). TRAKT: "History writes can also add to Trakt Collections" — moot, the Trakt road is shut. Experimental providers: Floppy, Nuvio, Kodi, Stremio, PunchPlay, Scrob. Jellyfin/Emby metadata is TMDb, so Jellyfin matching NEEDS TMDB egress.

**Scrobbling.** Watcher (polling) sources: Emby, Jellyfin, Plex, Kodi, Scrob — polling is OUTGOING, so no inbound connection to CrossWatch is needed, which suits our network posture. Webhook sources: Emby, Jellyfin, Plex, but the Plex webhook needs Plex Pass and the Emby webhook needs Emby Premiere; Watcher does not. Progress reporting (Watcher only): 25% steps. The wiki's scrobbling tracker-targets list is MDBList, PunchPlay, Scrob, SIMKL, Trakt.

## Risks (as accepted at closure)

- [risk] HIGH — the CrossWatch local database backend is very new: `cw_platform/local_db` first appeared 2026-08-04, and `v-pre-db` marks the state before it. The whole watch-state archive rests on a pre-1.0 (v0.11.2) storage backend a few weeks old. Mitigation: VolSync on `/config`, the export path, and the immutable Trakt ZIP as the floor.
- [risk] MEDIUM — bus factor of one maintainer. Mitigation: AGPL plus an export path; CrossWatch also speaks Floppy and Scrob, so a later move is a sync job, not a migration project.
- [risk] LOW — the ZIP is not proven to carry play counts. Episode-level `watched_at` is evidenced; play count is not (though 136 movie rewatch events survive at event level).
- [risk] LOW — Jellyfin write-back may set only a played flag without the original date. The dates live in the tracker by design, so this is cosmetic.

## Carried forward (NOT part of this closure)

- `plex-trakt-sync` manifest removal from `kubernetes/apps/media/plex-trakt-sync` — the workload is at 0/0 but the GitOps state still declares it.
- Narrow `egress.home.arpa/allow-world` to a custom-egress CiliumNetworkPolicy (TMDB + PunchPlay, plus in-cluster to jellyfin/plex). The app now holds provider credentials, which was the trigger condition stated for this narrowing.
- CrossWatch admin credential: currently an ad-hoc human-created local admin. The repo standard is an ExternalSecret backed by onepassword-connect.
- `components/zeroscaler` in `ks.yaml` for sibling consistency — deliberately omitted round-1 to keep the pod warm during the import.
- Export round-trip measurement (wipe + re-import, same counts) — never exercised.
- VolSync restore drill for the `/config` PVC — sync verified, restore not.
- `docs/areas/k8s-workloads` does not mention crosswatch; the app inventory is stale with respect to this deploy.

## Open questions — final state

- [resolved, human-verified 2026-08-21] Does the Trakt API application still exist? No — disabled, proven. Do NOT delete the app entry: a new one cannot be created (VIP-only since 2026-07-30).
- [resolved, human-verified 2026-08-21] Did the human use Jellyfin during the 23-day Trakt gap? No — the Jellyfin library has ZERO own watch-state. Plex was the single source; nothing to reconcile across players.
- [moot 2026-08-22] SIMKL credential model (wiki says OAuth id+secret+token, the code shows a built-in device-code client id). SIMKL was not wired — PunchPlay replaced it.
- [open, unmeasured] Does the Jellyfin library hold the SAME content as the Plex library? If not, some of the ~4862 items do not exist in Jellyfin and cannot be marked watched. The backfill ran, but the match/unmatched counts were not recorded. Do not guess a number.
- [open, unverified] Can the CrossWatch LOCAL tracker be a scrobble sink? The wiki's scrobbling tracker-targets list omits it. If it cannot, then "seed once, then scrobble" means scrobbling into an EXTERNAL tracker, which sits awkwardly with "the local tracker owns the truth". PunchPlay IS in that list, so the mirror leg can receive scrobbles; the local-tracker question itself stays unverified.
- [open, unrecorded] Is the CrossWatch local tracker a browsable library in the UI, or primarily a sync dashboard? The user asked for a tracker surface, not only a store; this was never written down.
- [open, unrecorded] Does the Jellyfin write-back preserve original watch dates, or only set a played flag?

## Commit trail

- `bb77659f2` docs — P0 Trakt export ground truth
- `e9f6def29` feat — isolated round-1 PoC deploy manifests
- `72d106809` chore — drop the dead external-dns annotation from the httproute
- `e48b69114` docs — Trakt-API-disabled fact, Jellyfin backfill, phase order
- `6439c593d` refactor — inline the HTTPRoute into the HelmRelease `route:` block
- `089e61391` docs — mark the Service-name verify item obsolete after route inlining
- `1b512d0a0` feat — Homepage dashboard annotations
- `82af0f411` — pod label `egress.home.arpa/allow-world`
- `8829522c1` / PR #4227 (merged `a65cbbaaf`) fix — probe `/healthz`, align UID with the image
- `cb0d505b9` docs — upstream wiki contract + round-1 live verification
- `c5806eef7` — memory limit 512Mi → 768Mi

## Relations

- relates_to [[trakt-watch-state-migration]]
- part_of [[k8s-workloads]]
- depends_on [[jellyfin]]
- relates_to [[resticprofile-backup]]
