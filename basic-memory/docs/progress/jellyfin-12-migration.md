---
title: jellyfin-12-migration
type: roadmap
permalink: home-ops/docs/roadmap/jellyfin-12-migration
topic: Jellyfin 10.11.11 to 12.x major migration - one-way database schema migration
  that runs for minutes before the web server binds, under a Kubernetes liveness probe
  that kills the pod after ~180s; plus an Introskipper plugin ABI-track constraint
  that decides the target minor version
status: done
priority: medium
scope: Single-app major upgrade of the jellyfin HelmRelease in the media namespace
  (image digest bump 10.11.11 to 12.x) with probe rework BEFORE the bump, a fresh
  VolSync snapshot as the rollback path, manual plugin removal/reinstall around the
  migration, and a required post-migration full library scan. The migration itself
  is a controlled maintenance-window operation, not a Renovate automerge.
rationale: 12.x rewrites the database schema (LinkedChildren table, relational playlists/collections)
  and explicitly supports no rollback without a full data restore; first boot runs
  migrations for several minutes while the /health endpoint is not yet served, so
  the current liveness probe (initialDelay 30s + 5x30s failureThreshold = ~180s kill
  budget) will SIGTERM the pod mid-migration on a large-enough library. Jellyfin also
  removes the /emby and /mediabrowser route prefixes and disables legacy auth, and
  requires third-party plugins to be removed pre-migration and reinstalled rebuilt-for-12
  afterwards; the Introskipper plugin we rely on has no release that installs on a
  12.1 server today (targetAbi 12.0.0.0 only), which couples the target-minor decision
  to the plugin track.
options:
- Wait for Introskipper 12.1 track, then single-shot to 12.1 (recommended) - one migration,
  one library scan, latest server fixes incl. pre-migration backup integrity; 10.11.11
  keeps working until then, probe hardening lands now anyway
- Migrate to 12.0 now - keeps Introskipper (12.0-track v12.0.4.0 preserves completed
  10.11 analysis), at the cost of a second 12.0-to-12.1 minor hop later
- 'Stay on 10.11.11 indefinitely (rejected: 12.x carries security fixes, and the probe
  hardening is worth landing regardless)'
related_areas:
- k8s-workloads
- volsync-backup
- flux-gitops
---

# Jellyfin 10.11 -> 12.x migration

## Metadata (observation-form)

- [type] roadmap
- [topic] Jellyfin 10.11.11 -> 12.x major migration in the media namespace
- [status] done - executed 2026-09-19 (research 2026-09-18) against the 12.0/12.1 release notes, the jellyfin.org announcement, the XDA breakage summary, and the live intro-skipper manifest/issues. D1 RESOLVED 2026-09-18: target 12.1. D2 (probe strategy) has a recommendation executable early as prep on 10.11.11. Plan re-reviewed objectively 2026-09-18: 4 corrections folded in (GitOps-safe emergency stop, Jellyfin's own pre-migration DB backup as first-line recovery, /health-during-migration assumption flagged, transcode verification added). Timing RESOLVED 2026-09-18 (human): migrate NOW, plugin-free - Introskipper stays dark until its 12.1 track ships (monthly follow-up check of releases/manifest). Phase 0 prep (D2 startup probe) executing the same day.
- [priority] medium
- [created] 2026-09-18
- [relates_to] [[home-ops/docs/progress/jellyfin]]
- [relates_to] [[k8s-workloads]]

## Context - current deployment facts

App: kubernetes/apps/media/jellyfin (app-template 5.1.0, ks.yaml components gpu + volsync).

- Image: ghcr.io/jellyfin/jellyfin:10.11.11 digest-pinned - exactly the preferred
  starting point for 12.x per the release notes (10.10.7+ or 10.11.x supported,
  older installs need a 10.10.7 hop first).
- Probes: liveness AND readiness are httpGet /health:8096, initialDelaySeconds 30,
  periodSeconds 30, timeoutSeconds 5, failureThreshold 5; startup probe DISABLED
  (sonarr pattern). Hard kill budget before the first SIGTERM: 30s + 5x30s = ~180s.
- Storage: config PVC jellyfin (5Gi, VolSync-backed - this is the rollback surface);
  jellyfin-metadata PVC (10Gi, deliberately NOT backed up - library artwork +
  Introskipper fingerprint DB); NFS /media; /cache and /tmp emptyDir.
- Plugins (manual UI installs): Introskipper (10.11 track v1.10.11.x, manifest
  https://intro-skipper.org/manifest.json) and File Transformation
  (https://www.iamparadox.dev/jellyfin/plugins/manifest.json).
- reloader.stakater.com/auto: "true" - a probe/values change auto-restarts the pod.
- Renovate: image is digest-pinned and every automerge rule in .renovate/autoMerge.json5
  is false, so a 12.x bump arrives as a reviewable PR. Hazard: that PR must not be
  merged before this roadmap executes.

## What changes in 12.x (research summary, 2026-09-18)

Version scheme: 10.11.x was the last "10"-prefixed branch; 12.0 = what would have
been 10.12. Tag 12.1 verified present on ghcr.io (12.1.20260915 build); 12.0 was not
in the recent-tags list - verify its digest at execution time if D1 picks 12.0.

One-way migration:

- Database schema rewrite (LinkedChildren table replaces serialized child lists;
  OwnerId/PrimaryVersionId become GUID FKs; ExtraIds dropped). No rollback without a
  full data restore. 12.1 additionally improves pre-migration backup integrity and
  cleans invalid data BEFORE migrations run - a reason to prefer 12.1 as target.
- First boot runs migrations: duplicate artist/people merge, orphaned extras removal,
  owner-relationship repair, clean-name/sort-name/series-key recompute, plus a
  path-based check across ALL library items. Official wording: "will take a while",
  "do not stop the server while migrations are running". The server appears idle -
  and /health is not served yet.
- New --mode startup flag (MediaServer | MigrateSystem | SeedSystem): MigrateSystem
  runs migrations and exits without starting the server - a container-friendly
  escape hatch (usable as a one-shot Job alternative, see D2).
- REQUIRED post-migration step: full library scan (auto-grouped alternate versions
  are cleared by the upgrade and restored only by the scan). First scan is
  significantly longer than normal.

Breaking behavior changes to pre-check or accept:

- Usernames become case-insensitive; migration FAILS if two users differ only by
  capitalization. Check before upgrading (we have a small user list - quick UI check).
- Global subtitle settings gone (per-library now); .ogg is audio-only; sorting uses
  CleanName so order may shift; artwork no longer upscaled.
- /emby/* and /mediabrowser/* route prefixes REMOVED and legacy auth disabled by
  default - very old third-party clients break. Our exposure: native Jellyfin
  clients on the internal route; check any elderly client in the household.
- GET /QuickConnect/Initiate -> POST (QuickConnect clients).

Plugins: server targets .NET 10, plugin ABI changed; official instruction is to
REMOVE all third-party plugins before migrating and re-add rebuilt versions after.
If the unstable plugin repo was ever configured, revert to the stable manifest URL.

## The two hard constraints

### C1 - the liveness probe kills a long migration (the human's flagged risk)

Migrations run before the web server binds, so /health does not answer during them.
Current budget is ~180s; the docs say minutes. Consequence: kubelet SIGTERMs the
container mid-migration, the pod restarts, and the migration re-runs against a
half-migrated database - exactly the "restarting at the wrong moment" failure the
XDA article warns about, delivered automatically by the probe controller.

Fix (D2 recommendation, lands as prep BEFORE any image change): enable the startup
probe and size it for migration duration:

    startup:
      enabled: true
      custom: true
      spec:
        httpGet: {path: /health, port: 8096}
        periodSeconds: 30
        failureThreshold: 60   # ~30 min budget; kubelet will not kill before it

Kubernetes semantics do the rest: while the startup probe has not succeeded,
liveness and readiness are not run, so the existing ~180s liveness budget is
suspended for the whole startup phase.

Stated assumption (review 2026-09-18): "/health is not served while migrations run"
follows from the docs ("the server appears idle") but was not verified against a
live 12.1 instance. The fix is robust to either truth: if /health answers early,
the startup probe simply succeeds immediately and nothing else changes. After startup succeeds, normal liveness
guards a hung server again. Expected side effects of the change: one reloader-driven
restart on 10.11.11 (cheap), and during the actual migration the HTTPRoute stays
NotReady (homepage down, internal clients down) - acceptable in a maintenance window.

Alternative (surfaced, not recommended as primary): scale the deployment to 0 and
run a one-shot pod/Job with the same mounts + --mode MigrateSystem, wait for
completion, then bump the image. Structurally cleanest (no probe can interfere), but
it duplicates the mount/securityContext surface outside GitOps; keep as fallback if
a library turns out to need hours.

### C2 - Introskipper has no 12.1-compatible release (measured 2026-09-18)

- intro-skipper manifest repo tracks: 10.8/10.9/10.10/10.11/12.0/12 only - NO 12.1
  track. All 12.0-track versions target ABI 12.0.0.0.
- intro-skipper issue #999 (closed 2026-09-15): plugin does not work on Jellyfin
  12.1 - "the manifest only targets ABI 12.0.0.0". The suggested interim is the raw
  12.0-track manifest URL; the maintainer's close note says switch back to the
  version-aware intro-skipper.org manifest. No 12.1-track release exists as of today.
- The 12.0-track latest stable v12.0.4.0 explicitly "preserves completed 10.11
  analysis when upgrading to 12.0" - the fingerprint DB on the jellyfin-metadata PVC
  survives the upgrade path intact.
- Known 12.0-track bug to watch: issue #1001 - Dashboard Restart fails with
  Introskipper 12.0.4.0 installed (restarting via the UI; a pod restart is unaffected).
- File Transformation plugin (iamparadox): 12.x compatibility unverified - decide at
  execution time whether to re-add or drop.

This constraint IS D1: 12.1 target = no Introskipper (until a 12.1 track ships);
12.0 target = Introskipper works, but a second minor hop to 12.1 comes later.

## Decisions

- [decision] **D1 target minor - RESOLVED 2026-09-18: 12.1** (human decision).
  Consequence accepted: Introskipper is NOT installable on the migrated server until
  intro-skipper ships a 12.1-compatible track (manifest repo has 12.0 only, all
  targetAbi 12.0.0.0; issue #999). The fingerprint DB survives untouched on the
  jellyfin-metadata PVC; whether a future 12.1-track plugin can read the 10.11-era
  analysis is unverified - treat restoring Introskipper as a post-migration
  follow-up (monthly check of the intro-skipper releases/manifest), not a blocker.
  12.1's pre-migration backup-integrity fix and invalid-data cleanup apply.
- [decision] **D2 probe strategy - recommendation only, no real alternative.**
  Enable the startup probe (spec above) as a standalone prep commit on 10.11.11,
  BEFORE any image change. The --mode MigrateSystem Job stays a documented fallback.
- [decision] **D3 maintenance window - human picks.** Any quiet evening; the route
  is internal-only, blast radius is household streaming + any *arr library-refresh
  notifications. Duration estimate: migration minutes (unbounded by startup probe)
  + first full library scan "significantly longer than normal" (background task -
  media playable while it runs, with the caveat that some items appear missing until
  the scan restores alternate versions).
- [decision] **D4 Renovate guard - recommendation.** Until execution, a Renovate PR
  bumping the jellyfin image to 12.x may appear (review-gated already). Either just
  close it, or add a temporary packageRule with allowedVersions < 12 for
  ghcr.io/jellyfin/jellyfin so it does not keep resurfacing.

## What to do (phased)

Phase 0 - prep, anytime, on 10.11.11 (no migration risk):

1. Startup-probe commit (D2): probes.startup enabled per the spec above; pre-commit
   + flux-local test; merge; reloader restarts the pod; verify it settles 1/1.
2. Username case-conflict check in the UI (D1 gate precondition, trivial for our
   user count).
3. Check open Renovate PRs for a jellyfin 12.x bump; handle per D4.
4. Probe the current VolSync snapshot state: just volsync list-snapshots jellyfin media.

Phase 1 - backup (window start):

5. On-demand snapshot: just volsync snapshot jellyfin media - verify it appears in
   just volsync list-snapshots jellyfin media. This snapshot is THE rollback point.
   Also check config-PVC headroom before proceeding: the 5Gi PVC must hold jellyfin.db
   roughly twice during migration (schema rewrite + 12.1's own pre-migration backup
   written into the data dir); if PVC usage is already high, grow the PVC first.

Phase 2 - plugin removal (UI, manual):

6. Remove Introskipper and File Transformation; restart via pod (not the Dashboard,
   per issue #1001); confirm the server starts clean. (Official 12.0 instruction:
   remove third-party plugins before migrating.)

Phase 3 - image bump (the migration):

7. Edit kubernetes/apps/media/jellyfin/app/helmrelease.yaml image tag to the chosen
   12.x tag+digest (resolve the digest at execution; verify the tag exists on ghcr).
   Commit, push, Flux reconciles.
8. Watch: kubectl -n media get pod -w. Expect NO /health answers for minutes. Do NOT
   restart anything while migrations run; the startup probe holds the pod alive for
   ~30 min. If it still gets killed (probe budget exhausted), STOP - do not let it
   CrashLoop. Emergency stop must be GitOps-safe, not a bare kubectl scale (out-of-band
   change; Flux would fight it): either `flux suspend helmrelease -n media jellyfin`
   or a values change (controllers.jellyfin.replicas: 0) committed through Git. Then
   investigate logs, and check Jellyfin's own pre-migration backup (12.1 writes one
   into the data dir under /config) BEFORE reaching for the VolSync restore - see
   Rollback. Window rule: no other changes touch the jellyfin HelmRelease while the
   migration runs (reloader auto-restart would kill a mid-migration pod).

Phase 4 - post-migration:

9. Verify pod Ready, /health 200, web UI loads (hard-refresh if the web client looks
   wrong - cached assets are the top post-12 anomaly).
10. Trigger the REQUIRED full library scan; expect it long; alternate versions come
    back as it progresses. Spot-check a multi-version movie and a series.
11. Re-add plugins: Introskipper from https://intro-skipper.org/manifest.json (the
    version-aware URL serves the right track for the chosen server minor);
    v12.0.4.0+ preserves the completed 10.11 analysis. File Transformation only if
    its 12.x compat is confirmed by then (else drop, note as follow-up).
12. Verify Introskipper fingerprint data intact (Intro Skipper menu shows analyzed
    state) and the metadata still lands on jellyfin-metadata.

Phase 5 - closeout:

13. Update docs/progress/jellyfin (or a fresh progress note) with the outcome;
    update BM docs/areas/k8s-workloads app inventory; note any 12.x behavioral
    changes observed (sorting, subtitles per-library, artwork sizing).

## Rollback

Rollback = image revert to 10.11.11 digest + config PVC restore from the Phase-1
snapshot (just volsync restore jellyfin <previous-N> media - position verified from
list-snapshots). The schema change is one-way, so the restore is the ONLY way back. Recovery
ordering after a failed/half migration: (1) Jellyfin's own pre-migration backup
written by 12.1 into /config (data dir) - fastest, already in place when the
failure happened; (2) only if that is unusable, the Phase-1 VolSync snapshot
restore, which also loses any config drift made since the snapshot.
The jellyfin-metadata PVC is untouched by a restore (fingerprints/artwork persist -
the risk is only that a plugin track mismatch makes them unreadable, not lost).

## Verification checklist (success criteria)

- [ ] Startup probe rendered on the Deployment and pod survives a >3 min simulated
      slow start (the probe config is live BEFORE any image change)
- [ ] Fresh VolSync snapshot exists and is verifiable before the bump
- [ ] Migration completes without a pod restart (kubectl describe pod restartCount
      unchanged through the migration window)
- [ ] /health 200, UI loads, full library scan completed, alternate versions restored
- [ ] Hardware transcode spot-check (QSV/VAAPI) on a real stream - 12.x jumps to
      FFmpeg 8.1; the DRA GPU claim wiring is unchanged but unproven on 12.x
- [ ] Introskipper reinstalled on the 12.x track with preserved analysis data
- [ ] Progress note + area-reference updated

## References

- Release v12.0 notes: https://github.com/jellyfin/jellyfin/releases/tag/v12.0
- Release v12.1 notes: https://github.com/jellyfin/jellyfin/releases/tag/v12.1
- Announcement: https://jellyfin.org/posts/jellyfin-release-12.0/
- XDA breakage summary: https://www.xda-developers.com/jellyfin-12-will-break-some-home-servers/
- Introskipper 12.1 ABI issue: https://github.com/intro-skipper/intro-skipper/issues/999
- Introskipper dashboard-restart issue: https://github.com/intro-skipper/intro-skipper/issues/1001
- Introskipper manifest repo (tracks): https://github.com/intro-skipper/manifest
- Current deployment: [[home-ops/docs/progress/jellyfin]]

## Execution outcome (2026-09-19)

Executed in a single attended maintenance window, end to end.

- [observation] Phase 0 prep: startup probe landed via PR #4390 (squash e109bddc2) - httpGet /health:8096, periodSeconds 30, failureThreshold 60 (~30 min slow-start budget). CI green (flux-local test+diff, gitleaks); forced reconcile; reloader restart verified 1/1 Running 0 restarts.
- [observation] Username case-conflict gate: jellyfin.db Users table holds a single user (zhorvath83) - conflict impossible.
- [observation] Rollback point: manual VolSync snapshot 6b663a849493f3e793a567698b2168e4 @ 2026-09-19 04:16:19Z (79.3 MiB), verified in the Kopia list. Unused; kept.
- [observation] The migration itself: image bumped to 12.1@sha256:c0166b09f7068e7738d006d86a71ad58b981e4ecf1bf0a24fbba2498ecfe8715 (amd64 manifest digest, resolved via docker manifest inspect), commit be3c07022 direct on main. Server completed startup in ~19s ("Startup complete 0:00:18.8") - migrations (RepairAlternateVersionLinks, MigrateRatingLevels, StripEmbeddedLinkedChildren over 3014 items, db optimize) ran far under the 30 min budget. Pod 1/1 Running, 0 restarts through the whole window; /health 200 via readiness probe.
- [observation] DEVIATION (human decision 2026-09-19): third-party plugins were NOT removed pre-migration. Old Introskipper 1.10.11.24 failed ABI load and was auto-disabled; the server auto-updated it to 12.0-track 12.0.4.0, which also stays dark on 12.1 (targetAbi 12.0.0.0, issue #999). File Transformation vanished from /config/plugins during the migration -> dropped per roadmap step 11.
- [observation] Post-migration repair: the 10.11 encoding.xml failed to load on 12.1 (empty EncoderPreset value rejected) and hardware acceleration fell back to 'none'. Human rebuilt the config in the UI (old config discarded by decision): QSV, device /dev/dri/renderD128, hw decoding H264/HEVC/MPEG2/VC1/VP8/VP9 + 10bit variants (no AV1, no RExt 12bit - UHD 630 Gen9.5 limits), hw encoding on, HEVC encode allowed, AV1 encode off, low-power VDENC off (HuC firmware unverified on Talos).
- [observation] Verification: full library scan triggered from UI, completed 28s (07:29:59Z). Web UI + multi-version movie + series spot-check OK (human, hard-refresh). QSV transcode verified live on "The Way (2010)" forced to 2 Mbps: h264_qsv decode -> vpp_qsv scale -> hevc_qsv encode via vaapi child device (iHD), ffmpeg exit 0.
- [follow-up] Monthly check of intro-skipper releases/manifest for a 12.1-track build - RESOLVED 2026-09-19 (human): Intro Skipper reinstalled on the 12.0-track and works on the 12.1 server; no 12.1-track needed. Fingerprint DB intact on jellyfin-metadata PVC. Successor enhancement tracked in [[home-ops/docs/roadmap/jellyfin-skipme-db-plugin]].
- [follow-up] File Transformation re-add decision (12.x compat unverified).
- [follow-up] Kopia maintenance: "too many index blobs (3407)" warning during list-snapshots - run just volsync kopia-maintenance and check the KopiaMaintenance schedule.
