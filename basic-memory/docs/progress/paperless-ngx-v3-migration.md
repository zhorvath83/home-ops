---
title: paperless-ngx-v3-migration
type: progress-note
permalink: home-ops/docs/progress/paperless-ngx-v3-migration
topic: Execution record for the paperless-ngx 2.20.15 -> 3.0.5 upgrade
status: in-progress
priority: high
roadmap: paperless-ngx-v3-migration
tags:
- progress
- paperless
- major-upgrade
---

# paperless-ngx-v3-migration — execution progress

## Metadata (observation-form)

- [topic] Execution state for the paperless-ngx-v3-migration roadmap item
- [status] in-progress — all automated acceptance criteria passed; two human-dependent checks and the settle commit remain
- [roadmap] [[paperless-ngx-v3-migration]] (docs/roadmap)
- [priority] high
- [cutover_at] 2026-08-15 16:02–16:03 CEST

## Decisions (with human, 2026-08-15)

- [decision] Delivery: option B — the env changes were pushed onto the Renovate branch `renovate/ghcr.io-paperless-ngx-paperless-ngx-3.x` and merged as PR 4056 (squash). A separate prep commit was rejected: `PAPERLESS_CONSUMER_POLLING_INTERVAL` does not exist in 2.20.15, so introducing it before the image bump would have silently stopped NFS polling while still on v2.
- [decision] Archive generation: `never` — preserve the exact v2 behaviour (0 of 1790 documents have an archive). No PVC growth, no VolSync size change.
- [decision] paperless-gpt keeps running through the cutover; verified by smoke-test afterwards rather than pre-emptively scaled down.
- [decision] The human confirmed a fresh document export and a current VolSync snapshot existed before cutover, so Phase 1 step 1 was satisfied without taking a new snapshot.

## What shipped

- [commit] `e5557fd12` on the Renovate branch -> squashed to main as `1780363d0` (PR 4056).
- [file] `kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml`:
  - image `2.20.15@sha256:835974fc...` -> `3.0.5@sha256:69a4e06e...` (shared `&image` anchor, so the backup CronJob follows)
  - deleted `PAPERLESS_CONSUMER_IGNORE_PATTERNS` (all 9 globs are covered by the v3 built-in defaults; as regex the old `._*` would have matched nearly every filename)
  - `PAPERLESS_CONSUMER_POLLING: "60"` -> `PAPERLESS_CONSUMER_POLLING_INTERVAL: "60"`
  - `PAPERLESS_OCR_MODE: "skip"` -> `"auto"`; `PAPERLESS_OCR_SKIP_ARCHIVE_FILE: "always"` -> `PAPERLESS_ARCHIVE_FILE_GENERATION: "never"`
  - app startup probe `failureThreshold` 5 -> 20 (one-off migration + tantivy rebuild budget)
  - backup CronJob `suspend: false` -> `true` (temporary; the v3 exporter's `--delete` would overwrite the v2-format export)
- [commit] `399ed75e2` — the roadmap note (docs commit on main).

## Verified after cutover (evidence)

- [verified] Pod `paperless-74666f7f5-mls86` runs `3.0.5@sha256:69a4e06e...`, both containers ready, **0 restarts**. The widened startup probe was never needed — the whole init chain took ~25s.
- [verified] Migrations applied cleanly: `documents.0015_document_version_index_and_more`, `0017_migrate_fulltext_query_field_prefixes` (the saved-view rewrite), `0022_add_perf_indexes`. SHA-256 checksums recomputed for 1792 documents in ~2s.
- [verified] **Zero `paperless.W002` / `paperless.W003` warnings** in the startup log — proof that no removed v2 OCR variable is left in the environment.
- [verified] Effective settings read from `django.conf.settings`: `OCR_MODE=auto`, `ARCHIVE_FILE_GENERATION=never`, `CONSUMER_POLLING_INTERVAL=60.0`, `CONSUMER_STABILITY_DELAY=5.0`, `CONSUMER_IGNORE_PATTERNS=[]`, `CONSUMER_IGNORE_DIRS=[]`.
- [verified] Consumer log: `Watching /data/nas/inbox using polling (interval: 60.0s)` — the rename took effect and inotify was NOT selected on the NFS mount.
- [verified] The v3 `ConsumerFilter` was exercised directly with the real settings: `scan_2026-08-15.pdf`, `Szamla 2026.pdf`, `arvizturo_tukorfurogep.pdf` -> CONSUME; `.DS_Store`, `._resource`, `desktop.ini`, `Thumbs.db`, `.stfolder/`, `@eaDir/`, `.stversions/`, `__MACOSX/` -> IGNORE. This is the direct disproof of the regex-footgun regression, stronger than a single file drop.
- [verified] Tantivy index rebuilt at 16:03 (18M, `.index_settings.json` written, `needs_rebuild()` now False). Searches return hits: `szamla` -> 1067, `2025` -> 440, `Y2025` -> 36; autocomplete works; the new `notes.note:` syntax parses without error.
- [verified] `Document.objects.count()` = 1790, `exclude(archive_filename=None).count()` = **0** — the archive behaviour is unchanged.
- [verified] paperless-gpt (v0.27.0, unversioned client now served **API v10**): its `/api/tags/?name__iexact=AI-OCR` background poll errored only during the 16:02:02–16:02:52 restart window (connection refused / no route to host) and has been clean since 16:03:21. The read path works against v10.
- [verified] All PR CI checks green before merge (Flux Local Diff helmrelease + kustomization, Flux Local Test, Gitleaks, Labeler).

## Open (human-dependent)

- [open] End-to-end consumption on a **real scan**: drop a document into the NAS inbox and confirm it is consumed within ~60s and that paperless-gpt tags/renames it (this exercises the API **write** path — PATCH title/tags/correspondent/`created_date` — which the log-only check above does not cover).
- [open] Login through `https://docs.${PUBLIC_DOMAIN}` in a browser: allauth changed how it derives the client IP for login rate limiting. If it returns 403, add `PAPERLESS_ALLAUTH_TRUSTED_PROXY_COUNT` and/or `PAPERLESS_ALLAUTH_TRUSTED_CLIENT_IP_HEADER` (`PAPERLESS_TRUSTED_PROXIES` alone may not suffice behind Tunnel -> Envoy).
- [open] Settle commit once the two above pass: revert the backup CronJob to `suspend: false`, decide whether to keep `failureThreshold: 20`, and update `docs/areas/k8s-workloads`.

## Follow-ups (not blocking)

- [followup] `PAPERLESS_EXPORT_DIR` is not a recognized setting in v3 (zero hits in `src/` and `docs/`); it survives only as the `&exportDir` anchor that the backup container reuses. Harmless, droppable if the anchor is inlined.
- [followup] paperless-gpt's `PAPERLESS_PUBLIC_URL` points at `documents.${PUBLIC_DOMAIN}` while the paperless route is `docs.${PUBLIC_DOMAIN}` — pre-existing, unrelated to v3.
- [followup] Consider pinning paperless-gpt to an explicit `Accept: application/json; version=N` once upstream supports it; today it silently rides the server default and will move again on the next API bump.

## Rollback (still available)

- `just volsync restore paperless 0 selfhosted` (wipes the PVC, restores the Kopia snapshot) + revert `1780363d0`. This is the only reliable path — the SQLite schema was migrated forward in place and paperless ships no downgrade migrations.
- The export-based secondary path is intact **only while the backup CronJob stays suspended**.

## Related

- implements [[paperless-ngx-v3-migration]] (docs/roadmap)
- relates_to [[k8s-workloads]]
- relates_to [[volsync-backup]]
