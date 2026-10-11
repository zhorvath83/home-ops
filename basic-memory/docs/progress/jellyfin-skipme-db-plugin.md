---
title: jellyfin-skipme-db-plugin
type: progress
permalink: home-ops/docs/progress/jellyfin-skipme-db-plugin
---

> Merged note. The roadmap lived at `docs/roadmap/jellyfin-skipme-db-plugin`; on
> execution (2026-10-11) the roadmap content and the execution record were merged into this
> single note per the project's "Fully implemented roadmap items -> progress/" convention, and
> the roadmap note was deleted. The deployment-level outcome is also summarized in
> [[home-ops/docs/progress/jellyfin]] (session 2026-10-11).


# Jellyfin SkipMe.db plugin install

## Metadata (observation-form)

- [type] progress — merged roadmap + execution record (see below)
- [topic] SkipMe.db plugin (intro-skipper org crowd-sourced segment provider) on jellyfin 12.1
- [status] done — executed 2026-10-11, see the Execution record section below
- [priority] low - pure enhancement on top of the already-restored skip functionality
- [created] 2026-09-19
- [relates_to] [[home-ops/docs/progress/jellyfin]]
- [relates_to] [[home-ops/docs/roadmap/jellyfin-12-migration]]
- [relates_to] [[k8s-workloads]]

## Context - plugin facts (researched 2026-09-19)

Repo: https://github.com/intro-skipper/skipme.db-plugin (GPL-3.0, same org as Intro
Skipper). A media segment PROVIDER: it syncs crowd-sourced timestamps for intros,
recaps, previews, credits and commercials from the SkipMe.db API into a local SQLite
cache, matched via external IDs (TMDB/TVDB/IMDb/AniList) - no audio fingerprinting, no
fpcalc, zero local analysis cost. Opt-in feature to SHARE local Intro Skipper
timestamps back to the community (reads the Intro Skipper SQLite DB; requires valid
duration + at least one external ID; items start unchecked on every page load).

- Requirements: Jellyfin 12.0.0-rc2+ / compatible Jellyfin 12 build. Our server at
  review: 12.2 (image 12.2@sha256:c88026ec..., verified live 2026-10-11; was 12.1
  migrated 2026-09-19). Framework net10.0 - matches the 12.x server (.NET 10).
- Install: manual DLL only. No plugin catalog manifest is published (the repo has the
  jf-plugin-build build.yaml fields, so a manifest may appear later - watch for it);
  re-verified 2026-10-11 - still no manifest.json in the repo root.
- Latest release at research time: v0.2.4.0 (2026-09-19), single asset
  SkipMe.db-plugin-v0.2.4.0.zip (~63 KB), containing SkipMe.Db.Plugin.dll.
  At review (2026-10-11): latest is v0.2.5.0 (published 2026-09-20), single asset
  SkipMe.db-plugin-v0.2.5.0.zip (~64 KB) - the daily release cadence stopped right
  after the research; only one release in the 3 weeks since.
- build.yaml: name "SkipMe.db", guid b2a63e62-0ac5-4575-9ad2-2c7534ccb83d,
  targetAbi 12.0.0.0, owner "Intro Skipper".
- Sync task: "Sync SkipMe.db Segment Database" (Intro Skipper category), daily at 01:00
  local, min 4h between attempts; preserves cached data on cancel/limit-hit.
- Season 0 (Specials) disabled by default - must be enabled in the plugin skip settings.

## Position relative to Intro Skipper (updated 2026-10-11)

The human reinstalled Intro Skipper on 2026-09-19 (12.0.4.0, manual) and it worked on
the 12.1 server; at review the server is 12.2 and the catalog auto-update installed
12.0.5.0 on 2026-10-10 (startup log: "Plugin installed: Intro Skipper 12.0.5.0"),
with analysis tasks running fine - plugin loading AND the catalog auto-update path
are both proven on this cluster. The old Intro Skipper_12.0.4.0 directory remains in
/config/plugins next to 12.0.5.0; remove the leftover at execution. Consequences:

1. SkipMe.db is NOT the interim skip solution (that was the original framing) - it is a
   complementary crowd-sourced provider: instant segments at ZERO analysis cost for
   content the local analysis has not covered yet or where local detection finds
   nothing. Correction folded in at self-check (2026-09-19, intro-skipper wiki):
   Intro Skipper CAN detect the same segment types (intros, credits, previews,
   recaps, commercials, movies) via chapter/chromaprint/black-frame/silence
   methods - the complement is the zero-cost instant coverage, not a wider
   segment-type scope.
2. The measured ABI concern is dissolved: a targetAbi 12.0.0.0 plugin demonstrably loads
   on our server - proven on 12.1 by the clean reinstall (2026-09-19) and on 12.2 by
   the catalog auto-update to Intro Skipper 12.0.5.0 (2026-10-10), same org, same
   build pipeline. The earlier "12.0-track stays dark on 12.1" observation from
   the migration was evidently an install-state issue, not a hard ABI rejection
   (why that auto-updated install stayed dark is unverified; the reinstall fixed it,
   and the 2026-10-10 auto-update also loaded cleanly).
3. Coexistence: BOTH plugins register as Media segment providers; enable/priority is
   per library (Dashboard -> Libraries -> Manage library). Verify at execution how
   Jellyfin merges segments when both provide for the same item (provider priority
   list), and set priority deliberately - local Intro Skipper analysis is authoritative
   for content it has fingerprinted.
4. Live observation 2026-10-11: the Intro Skipper analysis task re-enqueues the same
   few files on every run (MobLand season 2 x4 at 09:27, 10:00 and 23:59) - a queue
   churn to spot-check at execution; if SkipMe.db covers such items, the D3 priority
   order is measurable exactly there.

## GitOps surfaces - nothing to change

The deployment already provides everything the plugin needs; no manifest edit is
expected (verify at execution that none is needed):

- /config is the config PVC ("jellyfin", VolSync-backed) - the DLL and the plugin's
  SQLite cache land there, so future snapshots capture them automatically.
- Egress: allow-world-egress CCNP via the egress.home.arpa/allow-world label - the
  SkipMe.db API sync and optional TVMaze lookups work without policy change.
- User 10001/fsGroup 10001 - a DLL copied into the PVC by the container user is
  readable by the server.

Live verification (2026-09-19, read-only kubectl + exec ls; re-verified 2026-10-11):
deployment jellyfin, pod label app.kubernetes.io/name=jellyfin, PVCs jellyfin (5Gi) +
jellyfin-metadata (10Gi), egress.home.arpa/allow-world=true on the pod - all confirmed
live. Image at re-verification: 12.2@sha256:c88026ec... /config/plugins now holds
Intro Skipper_12.0.4.0 (leftover) + Intro Skipper_12.0.5.0 (auto-update 2026-10-10),
Artwork_3.0.0.0, Fanart_15.0.0.0, configurations/ - owned by 10001:10001.
Directory-naming caveat: catalog installs land in <Name>_<Version> subdirs, while the
SkipMe.db README prescribes SkipMe.db/ without a version suffix - if the plugin does
not register after the copy, retry with SkipMe.db_0.2.4.0/.

## Decisions

- [decision] **D1 install method - recommendation: manual one-shot copy.** Matches the
  standing decision that plugin installation is a manual step (SkipMe.db additionally
  has no catalog manifest). kubectl cp/exec into the running pod needs the usual
  per-invocation cluster-approval. The init-container variant stays a documented
  follow-up if manual re-copies for new releases become annoying.
- [decision] **D2 sharing opt-in - human decides at execution, default OFF.** Sharing
  uploads timestamps (not media) upstream, keyed by external IDs. With Intro Skipper
  working again, our local analysis is a genuine contribution candidate, but the
  feature is opt-in by design; leave off unless the human turns it on.
- [decision] **D3 coexistence priority - flipped to SkipMe.db PRIMARY (human,
  2026-10-11).** Initially set deliberately local-first (Intro Skipper first, SkipMe.db
  after) on the frame-exactness argument: local fingerprint analysis is exact for our
  file cuts, crowd timestamps are external-ID-matched and version-approximate, and
  priority only decides overlap. Revised the same day: the human's measured experience
  with the local analysis is missing segments on analyzed content, and measured
  experience beats theoretical exactness - so SkipMe.db now wins on overlap (917 covered
  episodes), Intro Skipper stays second and remains the sole provider on the ~64%
  crowd-uncovered items. Local-analysis tuning (Analysis Settings + Regenerate All
  Segment Timestamps + re-analysis) is the recorded follow-up for the missing-segment
  symptom on crowd-uncovered content. Reversible per-library in the UI anytime.

## What to do (phased)

### Phase 0 - install

1. Download and verify the asset:
   curl -LO https://github.com/intro-skipper/skipme.db-plugin/releases/download/v0.2.5.0/SkipMe.db-plugin-v0.2.5.0.zip
   (resolve the latest tag at execution time; at review the latest is v0.2.5.0 and the
   once-daily cadence has stalled - a single release since 2026-09-20). Unzip ->
   SkipMe.Db.Plugin.dll (~63 KB zip).
2. Copy into the running pod's PVC (cluster-approval required per policy):
   POD=$(kubectl -n media get pods -l app.kubernetes.io/name=jellyfin -o jsonpath='{.items[0].metadata.name}')
   kubectl -n media exec "$POD" -- mkdir -p /config/plugins/SkipMe.db
   kubectl -n media cp SkipMe.Db.Plugin.dll "$POD:/config/plugins/SkipMe.db/"
   (Container path mapping: the README's /var/lib/jellyfin/plugins is the bare-metal
   data dir; in the docker image the data dir is /config, so /config/plugins/SkipMe.db/.)
3. Restart the server (kubectl -n media rollout restart deployment/jellyfin; approval
   required) and read the startup log.
4. Verify: Dashboard -> Plugins lists SkipMe.db; startup log shows it loaded. Given the
   dissolved ABI concern, a load failure here is a bug to diagnose (plugin is days old,
   churn is high), not a dead end.

### Phase 1 - configure (UI, manual)

5. Enable the provider per library: Dashboard -> Libraries -> Manage library ->
   Media segment providers -> add SkipMe.db after Intro Skipper (D3).
6. Plugin skip settings (Dashboard -> Plugins -> SkipMe.db): choose segment types;
   enable Season 0/Specials only if wanted.
7. Run "Sync SkipMe.db Segment Database" manually once; check the plugin's SQLite
   cache is created and spot-check a known series shows intro/credit segments.

### Phase 2 - housekeeping

8. D2 sharing decision in the plugin settings (default: leave off).
9. Update [[home-ops/docs/progress/jellyfin]] with the outcome (installed version,
   load result, sync behavior, coexistence with Intro Skipper).

## Upgrade path

No catalog manifest today -> the Jellyfin UI cannot update or auto-update this plugin.
Upgrading = re-download the release zip + re-copy the DLL (Phase 0 steps 1-3). The sync
task and cached data do not depend on being on the latest plugin version - upgrade only
when a release fixes something we hit. Watch the repo for a published catalog manifest
(build.yaml suggests one may be generated eventually); if it appears, the UI install
path supersedes the manual copy.

## Rollback

Remove the plugin directory in the pod and restart:
kubectl -n media exec "$POD" -- rm -rf /config/plugins/SkipMe.db
(+ rollout restart). The plugin's SQLite cache goes with it (it is a read-only segment
provider; no library metadata is touched). The config PVC is VolSync-backed, so a
snapshot restore is never needed for this.

## Verification checklist (success criteria)

- [x] DLL present at /config/plugins/SkipMe.db/ in the pod
- [x] Plugin loads (on 12.2) - startup log + Dashboard -> Plugins list SkipMe.db
- [x] SkipMe.db added as Media segment provider on the movie and TV libraries (initially
      after Intro Skipper; order flipped to SkipMe.db primary later the same day - see D3)
- [x] First manual sync task completed; cached segments visible for a known series
- [x] Gap-coverage spot-check: an episode NOT analyzed by Intro Skipper shows an intro
      segment from SkipMe.db
- [ ] Coexistence spot-check (playback level, pending human — next watch): an
      Intro-Skipper-analyzed episode still skips correctly
- [x] Sharing setting explicitly decided (default off)
- [x] Progress note [[home-ops/docs/progress/jellyfin]] updated with the outcome

## References

- Plugin repo: https://github.com/intro-skipper/skipme.db-plugin
- Latest release (at research): https://github.com/intro-skipper/skipme.db-plugin/releases/tag/v0.2.4.0
- Intro Skipper releases (tracks): https://github.com/intro-skipper/intro-skipper/releases
- Migration outcome this builds on: [[home-ops/docs/roadmap/jellyfin-12-migration]]
- Current deployment: [[home-ops/docs/progress/jellyfin]]
- Review verification 2026-10-11: live cluster (jellyfin 12.2 image, plugins dir,
  startup log) + GitHub release API (v0.2.5.0, single DLL zip asset)


## Execution record (2026-10-11)

- [status] DONE — installed, loaded, synced, provider-enabled, sharing OFF. One item pending
  human: playback-level coexistence spot-check (skip button on an Intro-Skipper-analyzed
  episode during the next watch).
- [verified] DLL copied via kubectl cp into /config/plugins/SkipMe.db/ of the running pod
  (uid 10001), sha256 d988b90f1900eb263fc4de06981b44536079cad122157104df533ee9b2eba72e.
  Leftover Intro Skipper_12.0.4.0 directory removed in the same step.
- [verified] Startup log: "Loaded plugin: SkipMe.db 0.2.5.0"; sync task registered (daily 01:00).
  No plugin errors. The DropDisabledItemSeasonId migration warning is 12.2 server behavior.
- [verified] First manual sync (run from UI by the human): "Starting SkipMe.db sync for 217
  movie(s) and 2621 episode(s)" -> "Stored segments for 1008 of 2838 item(s)" in 6s. SQLite
  cache at /config/data/introskipper/skipme-segments.db (+wal/shm), alongside the Intro
  Skipper DBs.
- [verified] Media Segment Scan attached SkipMe.db segments across movies, kids_movies, shows,
  docuseries, docufilms — including episodes the local analysis never covered (The Wire S04,
  Dark Matter 2024 S02, Tell Me Lies) — the measured gap-coverage value: ~36% of library items
  got skip segments at zero analysis cost.
- [decision] D3 REVISED the same day (2026-10-11, human): initially reaffirmed local-first
  after the rationale was restated, then the human named the dominant symptom - MISSING
  segments on locally analyzed content - and flipped the order: SkipMe.db is now the primary
  Media segment provider, Intro Skipper second (UI change by the human, per library). The
  local-first argument survives only as theory; measured experience won. Local-analysis
  tuning (Analysis Settings + Regenerate All Segment Timestamps + re-analysis) recorded as
  follow-up for the crowd-uncovered items.
- [decision] D2 sharing stays OFF (human, 2026-10-11); Share tab untouched.
- [verified] Coexistence server-side: Intro Skipper 12.0.5.0 loads, introskipper-v2.db actively
  written post-restart; both plugins registered as Media segment providers.
- [observation] No manifest change; plugin + cache live on the /config PVC (VolSync-covered).
