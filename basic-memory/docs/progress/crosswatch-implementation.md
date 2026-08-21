---
title: crosswatch-implementation
type: progress_note
permalink: home-ops/docs/progress/crosswatch-implementation
---

# CrossWatch implementation — execution progress

## Metadata (observation-form)

- [topic] P0 Trakt watch-history rescue: ZIP inventory, ground-truth measurement, second copy into the file-level backup plane
- [status] P0 DONE. Round-1 manifests committed (e9f6def29 + 72d106809, feat/crosswatch) - isolated PoC deploy, NOT yet pushed/reconciled. P0 open question RESOLVED (Trakt API app disabled, proven; see New facts 2026-08-21). P1 merged into P2 (in-cluster PoC); P4 one-way read pulled into the P2 import round.
- [branch] feat/crosswatch
- [area] k8s-workloads / media, resticprofile-backup
- [created] 2026-08-21
- [implements] [crosswatch-implementation roadmap](memory://home-ops/docs/roadmap/crosswatch-implementation) (P0 leg)

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

## Session 2026-08-21 - round-1 manifests (PoC deploy, NOT yet pushed/reconciled)

Committed on feat/crosswatch as `e9f6def29` (manifests) + `72d106809` (strip the no-op external-dns annotation); docs commit to follow.

Files (kubernetes/apps/media/crosswatch/): ks.yaml, app/{kustomization,helmrelease,httproute}.yaml. Registered in kubernetes/apps/media/kustomization.yaml. No ciliumnetworkpolicy.yaml round-1.

Posture (evidence-backed, not guessed):
- Image pinned `ghcr.io/cenodude/crosswatch:0.11.2@sha256:52ee71679284c55a712d9127e1e64e74b71f563c499f3e8b01e554219a88a337` (tag has NO `v` prefix; `v0.11.2` does not exist) with a renovate docker-datasource annotation.
- /config PVC via the shared VolSync component (local-hostpath, 5Gi, APP=crosswatch); no NFS. The volsync component brings its own Kopia-repo ExternalSecret, so ks.yaml dependsOn onepassword-connect.
- HTTPRoute envoy-internal ONLY, `crosswatch.${PUBLIC_DOMAIN}`. No external-dns annotation (removed in 72d106809 — the envoy-internal route is invisible to ExternalDNS, which only watches envoy-external via `--gateway-name=envoy-external`; LAN split DNS comes from k8s-gateway, which does not read the annotation).
- non-root 10001, readOnlyRootFilesystem, emptyDir /tmp (Starlette multipart spool), TCP probes matching the Dockerfile HEALTHCHECK (no HTTP path guessed).
- AD-023 posture: pod label `ingress.home.arpa/allow-gateway-internal: "true"` admits envoy-internal via the ingress-from-gateway-internal CCNP (port-agnostic - verified in kube-system/cilium/netpols/); NO egress label -> baseline allow-cluster-egress only (in-cluster, no internet). NO app-level CNP round-1 because there is no app-specific egress to express (importer does not call TMDB - verified in services/importer.py v0.11.2; app boots with zero providers - verified in cw_platform/config_base.py).
- TMDB question resolved: round-1 import needs NO TMDB egress. The roadmap's anticipated "custom-egress to SIMKL and TMDB" belongs to round 2+ (when providers are wired).
- No ExternalSecret, no provider credentials round-1.

Upload + P1 measurement path: the import is a 3-step API (services/importer.py v0.11.2) - GET /api/import/options -> POST /api/import/preview (multipart `file`, `source`, `target_instance`) -> GET /api/import/preview/{id} -> POST /api/import/commit. Reached from the Mac over the envoy-internal LAN route (curl https://crosswatch.${PUBLIC_DOMAIN}/...), NOT kubectl port-forward. Preview row count = P1 reference vs ground truth (5639 events: 310 movie / 5329 episode); commit -> CW local SQLite = final.

FOLLOW-UP (not forgotten): add `components/zeroscaler` to ks.yaml for sibling consistency once the import + round-trip is green.

Verify-at-PoC (check AFTER deploy, not pre-fabricated):
- (The HelmRelease `route:` block binds its backendRef to the chart-generated Service via `identifier: app`, so the Service-name / backendRef verify item is obsolete — the convention does the wiring, no manual Service name to confirm.) liveness HTTP path if switching off TCP; whether boot needs an egress (startup log -> minimal custom-egress CNP, never allow-world); /tmp writability under readOnlyRootFilesystem (preempted with emptyDir but confirm on a real upload).
- UID 1000 hypothesis (NOT changed pre-deploy; 10001 is the repo-dominant convention, chosen deliberately). The CrossWatch image builds its own user at UID 1000 (Dockerfile v0.11.2: `ARG APP_UID=1000`). Running at 10001 means that UID is not present in the container user database, so the Python uid-to-name lookup can fail. Failure modes to look for in the pod log: `pwd.getpwuid()` -> `KeyError: getpwuid(): uid not found`; or a write under the appuser home (owned by 1000 + readOnlyRootFilesystem) -> permission denied. If EITHER appears, the fix is one line: `runAsUser: 1000` (+ runAsGroup/fsGroup 1000), precedent: homepage, paperless, k8s-gateway, seerr. Let the log decide — do not pre-flip.
- Measurement interpretation (so a failure is not misread as a software bug): (a) memory limit is 512Mi and 5639 events go into SQLite — if the import OOMs, check the pod for OOMKilled; that is the LIMIT, not a CrossWatch bug (raise the limit, do not file a software issue). (b) There is NO app CNP round-1, only baseline cluster-egress — if the import calls TMDB, the network blocks it. Probably a non-issue: the Trakt export itself carries trakt/imdb/tmdb/tvdb IDs (seen in the collection + history payloads), so matching needs no external call (only posters do). BUT if "unmatched" rows appear, look at the NETWORK first, not the software.

Next: push + reconcile when the human greenlights; then run the import + measure against the P0 baseline.

## New facts 2026-08-21 (human-verified) — Trakt API disabled; Jellyfin has NO watch-state

- [Trakt, proven] The Trakt API application is DISABLED (human verified the account; proven, not hypothesis). The live Trakt API path is permanently gone; the ZIP is the only route. Last successful scrobble 2026-07-29T18:53Z; 23 days of complete silence (2026-07 was the MOST active month in 8 months, 146 events, ~4.7/day; 2026-08: 0). The app was taken offline on 07-29/30 when Trakt made app creation VIP-only; the 2026-08-20 token-refresh error was a consequence.
- [data gap] The Trakt import does NOT give the complete history. ~3 weeks — ~100+ events at the July pace — never reached Trakt. That data is NOT lost: plex-trakt-sync read FROM Plex and pushed TO Trakt, so Plex own watch-state is intact and is the ONLY source for the gap (it grows ~5 events/day).
- [consequence for phases] The Plex -> CrossWatch one-way READ is pulled FORWARD into the P2 import round, not after Jellyfin, because Plex is the only source for the 23-day gap. Direction (decision C) UNCHANGED; two-way write-back stays a later step.
- [Jellyfin, proven] The Jellyfin library has ZERO own watch-state (confirmed by the human). So the 23-day gap is entirely in Plex — one source, nothing to reconcile. The earlier open question "did the human use Jellyfin too?" is resolved: no.
- [P3 redefined] P3 is a BULK BACKFILL, not a sync test: mark ~174 movies + 4688 episodes watched in an EMPTY Jellyfin. Less risky (no before-state to lose; rollback = delete what we wrote). Jellyfin is a pure consumer, zero own knowledge.
- [phase order] a) Trakt ZIP import -> 5639 events, only through 2026-07-29. b) Plex -> CrossWatch -> one-way read, fill the 23-day gap. c) VERIFICATION: does CrossWatch own the full truth? d) CrossWatch -> Jellyfin -> one-way upload into the empty Jellyfin. e) only after (c)+(d) verify, any two-way sync.
- [P6] plex-trakt-sync is a PROVEN DEAD workload (no API app, no scrobble since 07-29); the withdrawal gate lost its meaning. Note only — do not act this round.

## Session 2026-08-21 — upstream contract + round-1 live verification

### Round-1 deploy verified live (read-only)
Pod 1/1 Running, 0 restart, IP 10.244.0.62. PVC crosswatch Bound, 5Gi, democratic-csi-local-hostpath. HTTPRoute Accepted=True ResolvedRefs=True. LAN DNS resolves crosswatch.${PUBLIC_DOMAIN} to the envoy-internal VIP (192.168.1.18). HTTPS GET / -> 200, TLS verify OK. The P2 deploy is live and healthy.

### Commits already on main (this session, verified)
- 1b512d0a0 feat(crosswatch): add Homepage dashboard annotations. Fulfills the media/CLAUDE.md guardrail "dashboard apps carry Homepage annotations" (enabled/name/group/icon per the jellyfin pattern). Icon crosswatch.svg verified to exist in the selfhst/icons set (HTTP 200, real 940-byte SVG, gradient id crosswatch_svg__a) — not a torn tile.
- 82af0f411 pod label `egress.home.arpa/allow-world: "true"`. WIDER than the roadmap P2 expectation ("custom-egress to the SIMKL and TMDB APIs"). Acceptable for the PoC; must narrow to a custom-egress CNP before the app holds Plex/Jellyfin/SIMKL credentials (see Follow-up).
- 8829522c1 / PR #4227 (merged a65cbbaaf) fix(crosswatch): probe /healthz + align UID with the image.
  - Probe: tcpSocket -> httpGet /healthz. Verified live: GET /healthz returns 200 {"ok":true,"status":"ok"} and is NOT auth-gated, while GET / 302s to /login. The httpGet probe proves the app SERVES, not just that the port is open.
  - runAsUser/runAsGroup/fsGroup 10001 -> 1000. The image builds appuser at APP_UID=1000. Verified result: the "id: cannot find name for user ID 10001" entrypoint warning is GONE; the entrypoint now logs "as appuser:appuser (1000:1000)". Pod 1/1 Ready, no probe error. The UID-1000 verify-at-PoC item is resolved (the symptom was present and non-fatal; now removed).
  - TZ is intentionally NOT in the manifest: the k8tz webhook injects it (verified TZ=Europe/Budapest on the live pod), even though the upstream wiki lists TZ as "required".

### Auth model (operational)
CrossWatch requires login (the /login page: username/password/totp/remember; title "Sign in | CrossWatch"; links to wiki.crosswatch.app). A first-run open window existed for the first few minutes after boot (during which GET / -> 200 and the trakt preview API answered 200), then shut; after that GET / 302s to /login and all /api/* return 401 except /healthz. The first-run setup was completed by the human (a local admin was created). The import credential is the human's; not pursued this round.

### Deployment contract (wiki: installation/docker-setup) — env list
CONFIG_BASE=/config, WEB_HOST=0.0.0.0, WEB_PORT=8787, RUNTIME_DIR=/config, APP_UID=1000, APP_GID=1000, APP_USER=appuser, APP_GROUP=appuser, APP_DIR=/app, TZ (required), RELOAD=no, CW_RESET_AUTH_ONCE=1 (auth/session wipe on restart). Health endpoint: GET /healthz -> {"ok":true,"status":"ok"}. "Always persist /config" — state lives in config.json, state.json, statistics.json. WARNING: do NOT set the container `user` property together with the APP_* vars.

### CW_RESET_AUTH_ONCE — documented auth-recovery path
CW_RESET_AUTH_ONCE=1 is the documented way to wipe auth/session on restart. We did NOT set it: it would also wipe the admin the human just created. Recorded here as the known recovery path for a future lockout, not used now.

### Follow-up
- Revert/add `components/zeroscaler` to ks.yaml for sibling consistency once the import is green (carried from the prior round-1 note).
- Narrow the allow-world pod label to a custom-egress CNP (SIMKL + TMDB, plus in-cluster to jellyfin/plex) before the app holds provider credentials.
- Measure the export round-trip (roadmap acceptance criteria) — NOT done yet; the P1 import measurement is still auth-blocked pending the credential decision.
- CrossWatch admin credential long term: an ExternalSecret backed by onepassword-connect is the repo standard; currently ad-hoc (human-created local admin). Decide and wire before steady state.

## Open — human-only

- [resolved 2026-08-21, human-verified] Does the Trakt API application still exist in the account? ANSWER: no — the app is disabled (proven). The ZIP is the only route; a live Trakt sync is not possible. Recorded for traceability. Do not delete the app entry — a new one cannot be created (VIP-only since 2026-07-30).
- [open, human-only, measured at PoC] Does the Jellyfin library hold the SAME content as the Plex library? If not, some of the ~4862 items do not exist in Jellyfin and cannot be marked watched. Matching question, not decidable in advance. DO NOT GUESS.

## Relations

- implements [crosswatch-implementation roadmap](memory://home-ops/docs/roadmap/crosswatch-implementation) (P0 leg)
- relates_to [[resticprofile-backup]] (file-level backup plane, second copy target)
- relates_to [[k8s-workloads]] (P2 deploy target area)
