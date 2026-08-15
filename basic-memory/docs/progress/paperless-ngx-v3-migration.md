---
title: paperless-ngx-v3-migration
type: progress-note
permalink: home-ops/docs/progress/paperless-ngx-v3-migration
topic: Execution record for the paperless-ngx 2.20.15 -> 3.0.5 upgrade
status: done
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

## End-to-end consumption verified (2026-08-15 16:12)

- [verified] A real scan (`Horvath_Zoltan 26.07 hó NAV utalandó 08.12.pdf`) dropped into the NAS inbox was detected by the polling watcher, passed the stability check, and consumed as **document 1853 in 4.07s**. This closes the end-to-end consumption criterion — the polling rename and the ignore-pattern removal both hold against a real file with spaces and accented characters in the name.
- [verified] The pre-consume script ran live and exited 0, with all stages reached: encryption check ("PDF is not encrypted"), blank detection (page 1 ink=9.88539, kept), attachment scan, lossless optimization. `DOCUMENT_WORKING_PATH` compatibility with v3 is now proven at runtime, not just by source reading.
- [verified] `PAPERLESS_FILENAME_FORMAT` still applies (`2026/none/2026-08-12_horvath_zoltan-2607-ho-nav-utalando-0812_0001853.pdf`) and `PAPERLESS_DATE_ORDER=YMD` parsed `created` = 2026-08-12 from the filename.
- [verified] The new document has `archive_filename = None`; the corpus is now 1791 documents with **0 archives**. `ARCHIVE_FILE_GENERATION=never` holds on a freshly consumed document, not just on the pre-existing corpus.

## New finding — the v2 classifier model did not survive the upgrade

- [finding] During the first consumption v3 logged `ClassifierModelCorruptError`: *"Unrecoverable error while loading document classification model, deleting model file"*. The v2-era `/data/local/data/classification_model.pickle` is not readable by v3 and was **deleted**; the file is confirmed gone.
- [finding] Because `PAPERLESS_TRAIN_TASK_CRON: "disable"` is set for resource reasons, the periodic training task will never regenerate it. The model was a stale v2 artifact that v2 still loaded read-only, so classifier-based auto-matching worked until the upgrade and is now silently off.
- [finding] Measured blast radius: **3 of 84 correspondents** use `MATCH_AUTO` (Földhivatal, Kiszámoló Egyesület, OVH Hosting Limited Enterprise). **0 of 29 tags** and **0 of 17 document types** use it. Rule-based matching (regex/literal/fuzzy) is unaffected, as is everything paperless-gpt does.
- [finding] This is NOT in the upstream migration guide — it surfaced only because a real document was consumed after the cutover. Any v3 upgrade carrying an old pickle will hit it.
- [option] One-off `python3 manage.py document_create_classifier` regenerates a v3-format model and restores auto-matching for those 3 correspondents; it will go stale again since training stays disabled.
- [option] Switch those 3 correspondents to a rule-based matching algorithm in the UI — removes the dependency on a model that is deliberately never trained.
- [option] Accept the loss; 3 correspondents is small and rule-based matching still covers the rest.

## Still open

- [open] paperless-gpt **write** path remains untested. Document 1853 carries only the `Inbox` tag; paperless-gpt watches for `AUTO_TAG=AI-processing`, which currently has 0 documents, and no paperless Workflow exists to apply it (the trigger is manual). Tagging 1853 with `AI-processing` would exercise the PATCH path against API v10.
- [open] Browser login through the public hostname (allauth client-IP / rate-limit change).
- [open] Settle commit: re-enable the backup CronJob.

## Settled (2026-08-15, with human)

- [decision] Classifier: the human switched the 3 affected correspondents in the UI instead of retraining. Verified: `MATCH_AUTO` is now empty. **Caveat recorded** — all three ended on `matching_algorithm = None` with an empty `match` string, so they are not rule-matched either; they are now assigned manually only. The classifier dependency is gone as intended, but if automatic assignment is still wanted, each needs a regex/literal algorithm **plus** a match pattern.
- [decision] Startup probe stays at `failureThreshold: 20`. The whole init chain took ~25s so it is never active today, but it is free insurance for the next long migration or index rebuild. Liveness/readiness stay at 5.
- [verified] Browser check by the human: the UI and login through the public hostname work — the allauth client-IP / login rate-limit concern did not materialise, so no `PAPERLESS_ALLAUTH_TRUSTED_PROXY_COUNT` / `PAPERLESS_ALLAUTH_TRUSTED_CLIENT_IP_HEADER` is needed.
- [commit] `80ad23765` — export CronJob back to `suspend: false`. From the next 00:30 run the export is written in v3 format and the v2-format export is gone; the VolSync + Kopia restore stays the rollback path.

## Final status

- [status] done — every acceptance criterion in the roadmap item passed.
- [open] paperless-gpt **write** path (PATCH against API v10) is the one criterion never exercised: it needs a document tagged `AI-processing`, which is a manual trigger in this setup. Not blocking; the read path is verified and a failure would be visible in the paperless-gpt log the first time it processes a document.
