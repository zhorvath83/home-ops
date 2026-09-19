---
title: jellyfin-skipme-db-plugin
type: roadmap
permalink: home-ops/docs/roadmap/jellyfin-skipme-db-plugin
topic: Complementary installation of the SkipMe.db Jellyfin plugin (crowd-sourced
  intro/credit segment provider from the intro-skipper org) on the 12.1 jellyfin,
  alongside the reinstalled working Intro Skipper
status: planned
priority: low
scope: No manifest change expected. A one-time manual DLL copy into the jellyfin config
  PVC (/config/plugins/SkipMe.db/), a pod restart, library-level segment-provider
  enablement, and a first sync-task verification. Rollback is deleting the plugin
  directory.
rationale: Intro Skipper was reinstalled by the human on 2026-09-19 and works on the
  12.1 server (12.0-track), so local skip functionality is already restored. SkipMe.db
  adds crowd-sourced timestamps (intros, recaps, previews, credits, commercials, including
  movies) for content the local fingerprint analysis has not covered, at zero analysis
  cost, and can opt-in share our Intro Skipper timestamps back to the community. It
  ships no plugin catalog manifest, so manual DLL install is the only documented path
  - this matches the standing decision that plugin installation is a manual step outside
  GitOps.
options:
- Manual one-shot DLL copy into the config PVC via kubectl cp (recommended) - matches
  the manual-plugin-install decision; zero manifest change; upgrade = re-copy
- Init container downloading the pinned release zip at pod start - declarative and
  self-updating, but machinery for a one-time ~63 KB copy; reconsider only if release
  churn makes manual re-copies annoying
- Git-tracked DLL mounted read-only into the container - rejected, binary in git,
  and it collides with Jellyfin's own plugin-directory management under /config/plugins
related_areas:
- k8s-workloads
- volsync-backup
---

# Jellyfin SkipMe.db plugin install

## Metadata (observation-form)

- [type] roadmap
- [topic] SkipMe.db plugin (intro-skipper org crowd-sourced segment provider) on jellyfin 12.1
- [status] planned - researched 2026-09-19 against the plugin repo, build.yaml, the release
  API and the live jellyfin-12-migration outcome; reframed the same day when the human
  reinstalled Intro Skipper and it works on 12.1; facts self-checked the same day
  against primary sources (raw README, build.yaml, release API, live cluster) with one
  correction folded in (Intro Skipper segment-type scope)
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

- Requirements: Jellyfin 12.0.0-rc2+ / compatible Jellyfin 12 build. Our server: 12.1
  (image 12.1@sha256:c0166b09..., migrated 2026-09-19). Framework net10.0 - matches the
  12.x server (.NET 10).
- Install: manual DLL only. No plugin catalog manifest is published (the repo has the
  jf-plugin-build build.yaml fields, so a manifest may appear later - watch for it).
- Latest release at research time: v0.2.4.0 (2026-09-19), single asset
  SkipMe.db-plugin-v0.2.4.0.zip (~63 KB), containing SkipMe.Db.Plugin.dll.
- build.yaml: name "SkipMe.db", guid b2a63e62-0ac5-4575-9ad2-2c7534ccb83d,
  targetAbi 12.0.0.0, owner "Intro Skipper".
- Sync task: "Sync SkipMe.db Segment Database" (Intro Skipper category), daily at 01:00
  local, min 4h between attempts; preserves cached data on cancel/limit-hit.
- Season 0 (Specials) disabled by default - must be enabled in the plugin skip settings.

## Position relative to Intro Skipper (updated 2026-09-19)

The human reinstalled Intro Skipper on 2026-09-19 and it works on the 12.1 server
(12.0-track; newest stable v12.0.4.0, prerelease v12.0.4.27 - no 12.1-track exists,
none needed). Consequences:

1. SkipMe.db is NOT the interim skip solution (that was the original framing) - it is a
   complementary crowd-sourced provider: instant segments at ZERO analysis cost for
   content the local analysis has not covered yet or where local detection finds
   nothing. Correction folded in at self-check (2026-09-19, intro-skipper wiki):
   Intro Skipper CAN detect the same segment types (intros, credits, previews,
   recaps, commercials, movies) via chapter/chromaprint/black-frame/silence
   methods - the complement is the zero-cost instant coverage, not a wider
   segment-type scope.
2. The measured ABI concern is dissolved: a targetAbi 12.0.0.0 plugin demonstrably loads
   on our 12.1 server after a clean install (Intro Skipper is the proof, same org,
   same build pipeline). The earlier "12.0-track stays dark on 12.1" observation from
   the migration was evidently an install-state issue, not a hard ABI rejection
   (why the auto-updated install stayed dark is unverified; the reinstall fixed it).
3. Coexistence: BOTH plugins register as Media segment providers; enable/priority is
   per library (Dashboard -> Libraries -> Manage library). Verify at execution how
   Jellyfin merges segments when both provide for the same item (provider priority
   list), and set priority deliberately - local Intro Skipper analysis is authoritative
   for content it has fingerprinted.

## GitOps surfaces - nothing to change

The deployment already provides everything the plugin needs; no manifest edit is
expected (verify at execution that none is needed):

- /config is the config PVC ("jellyfin", VolSync-backed) - the DLL and the plugin's
  SQLite cache land there, so future snapshots capture them automatically.
- Egress: allow-world-egress CCNP via the egress.home.arpa/allow-world label - the
  SkipMe.db API sync and optional TVMaze lookups work without policy change.
- User 10001/fsGroup 10001 - a DLL copied into the PVC by the container user is
  readable by the server.

Live verification (2026-09-19, read-only kubectl + exec ls): deployment jellyfin, pod
label app.kubernetes.io/name=jellyfin, PVCs jellyfin (5Gi) + jellyfin-metadata (10Gi),
egress.home.arpa/allow-world=true on the pod, image 12.1@sha256:c0166b09... - all
confirmed live. /config/plugins currently holds Intro Skipper_12.0.4.0 (the human's
reinstall), Artwork_3.0.0.0, Fanart_15.0.0.0, configurations/ - owned by 10001:10001.
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
- [decision] **D3 coexistence priority - verify then set deliberately.** On the
  libraries, keep Intro Skipper as the first Media segment provider and add SkipMe.db
  after it, unless the live UI shows a reason to reorder.

## What to do (phased)

### Phase 0 - install

1. Download and verify the asset:
   curl -LO https://github.com/intro-skipper/skipme.db-plugin/releases/download/v0.2.4.0/SkipMe.db-plugin-v0.2.4.0.zip
   (resolve the latest tag at execution time; release cadence is daily). Unzip ->
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

- [ ] DLL present at /config/plugins/SkipMe.db/ in the pod
- [ ] Plugin loads on 12.1 - Dashboard -> Plugins lists SkipMe.db
- [ ] SkipMe.db added as Media segment provider after Intro Skipper on the movie and
      TV libraries
- [ ] First manual sync task completed; cached segments visible for a known series
- [ ] Gap-coverage spot-check: an episode NOT analyzed by Intro Skipper shows an intro
      segment from SkipMe.db
- [ ] Coexistence spot-check: an Intro-Skipper-analyzed episode still skips correctly
- [ ] Sharing setting explicitly decided (default off)
- [ ] Progress note [[home-ops/docs/progress/jellyfin]] updated with the outcome

## References

- Plugin repo: https://github.com/intro-skipper/skipme.db-plugin
- Latest release (at research): https://github.com/intro-skipper/skipme.db-plugin/releases/tag/v0.2.4.0
- Intro Skipper releases (tracks): https://github.com/intro-skipper/intro-skipper/releases
- Migration outcome this builds on: [[home-ops/docs/roadmap/jellyfin-12-migration]]
- Current deployment: [[home-ops/docs/progress/jellyfin]]
