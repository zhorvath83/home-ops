---
title: paperless-ngx-v3-migration
type: progress
permalink: home-ops/docs/progress/paperless-ngx-v3-migration
topic: Upgrade paperless-ngx 2.20.15 -> 3.0.5 (Renovate PR 4056), applying every v3
  breaking change to the HelmRelease env in ONE atomic commit
status: done
priority: high
roadmap: paperless-ngx-v3-migration
tags:
- roadmap
- paperless
- selfhosted
- major-upgrade
- breaking-change
- completed
area: k8s-workloads
created: '2026-08-15'
completed: '2026-08-15'
moved_from: docs/roadmap/paperless-ngx-v3-migration
related_areas:
- k8s-workloads
- volsync-backup
- networking
---

# paperless-ngx-v3-migration — 2.20.15 → 3.0.5 migration record

Roadmap item completed 2026-08-15 and moved from `docs/roadmap/paperless-ngx-v3-migration`;
merged into this progress note. Executed via Renovate PR #4056 (option B).

## Metadata (observation-form)

- [topic] Upgrade paperless-ngx to v3 with every breaking change applied to the HelmRelease env in one atomic commit
- [status] done — every acceptance criterion in the roadmap item passed (2026-08-15)
- [priority] high
- [area] k8s-workloads
- [scope] `kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml` env block + image tag; the pre-consume ConfigMap script (verified compatible, no change); the nightly `document_exporter` CronJob (rollback-path implication); paperless-gpt API compatibility (unversioned client now served API v10)
- [created] 2026-08-15
- [completed] 2026-08-15
- [cutover_at] 2026-08-15 16:02–16:03 CEST
- [trigger] Renovate PR https://github.com/zhorvath83/home-ops/pull/4056 (major: 2.20.15 -> 3.0.5)
- [source] https://docs.paperless-ngx.com/migration-v3/ (read from the v3.0.5 tag: docs/migration-v3.md)
- [moved_from] docs/roadmap/paperless-ngx-v3-migration

## Roadmap spec (moved from docs/roadmap)

### Rationale

Renovate PR #4056 bumps the image only. Merging it as-is is NOT safe:
- `PAPERLESS_CONSUMER_IGNORE_PATTERNS` becomes a regex list in v3, and our existing glob `._*` as a regex matches nearly every filename -> the consumer would ignore everything
- `PAPERLESS_CONSUMER_POLLING` is renamed and the new default is 0 (inotify), which does not work on our NFS consume dir
- `PAPERLESS_OCR_SKIP_ARCHIVE_FILE` is removed, so archive generation silently flips from never to auto on a 20Gi PVC

All three are env-only fixes that must ship together with the image bump.

### Options considered

- **A (recommended):** one atomic commit to main that bumps the image AND rewrites the env block; close Renovate PR #4056 as superseded.
- **B:** push the env changes onto the Renovate branch `renovate/ghcr.io-paperless-ngx-paperless-ngx-3.x` and merge that PR. **Chosen** — see Decisions.
- **Rejected:** a config-prep commit before the image bump — `PAPERLESS_CONSUMER_POLLING_INTERVAL` does not exist in 2.20.15, so polling would silently stop and NFS consumption would break while still on v2.

### Breaking-change matrix (the v3 design record)

#### Must change (breaks or silently changes behaviour)

- [must] **Consumer ignore patterns are now regex, not fnmatch.** Our `PAPERLESS_CONSUMER_IGNORE_PATTERNS` is a glob list; as a regex, `"._*"` means "any char, zero-or-more underscores" and matches nearly every filename via `re.search()` -> **the consumer would ignore every incoming file**. v3 built-in file defaults (`^\.DS_Store$`, `^\.DS_STORE$`, `^\._.*`, `^desktop\.ini$`, `^Thumbs\.db$`) plus built-in dir defaults (`.stfolder`, `.stversions`, `.localized`, `@eaDir`, `.Spotlight-V100`, `.Trashes`, `__MACOSX`) already cover **all nine** of our entries, and user entries now *add to* the defaults. **Action: delete the variable entirely** (net reduction; no `CONSUMER_IGNORE_DIRS` needed either). → Done: deleted, `CONSUMER_IGNORE_PATTERNS=[]` verified effective.
- [must] **`PAPERLESS_CONSUMER_POLLING` -> `PAPERLESS_CONSUMER_POLLING_INTERVAL`.** New default is `0` = native inotify, which is unreliable on our NFS consume dir (`nas-inbox`, `${NAS_IP}:/scanner/paperless-inbox`). Keeping the old name means polling silently stops. **Action: rename, keep `"60"`.** → Done: renamed, `CONSUMER_POLLING_INTERVAL=60.0` verified effective.
- [must] **`PAPERLESS_OCR_SKIP_ARCHIVE_FILE` removed** (`checks.py:317`, warning `paperless.W002`) and **`PAPERLESS_OCR_MODE=skip` is not a valid value** (`checks.py:327`, warning `paperless.W003`; `settings/__init__.py:920` silently coerces it to `auto`). Left as-is the app still boots, but `ARCHIVE_FILE_GENERATION` falls back to its new default `auto` -> paperless starts writing PDF/A archives for image-based PDFs where today **0 of 1790** documents have one. On a 20Gi PVC that is an unplanned growth path. **Action: `PAPERLESS_OCR_MODE: "auto"` + `PAPERLESS_ARCHIVE_FILE_GENERATION: "never"`** — the documented equivalent of today's `skip` + `always`. → Done: zero `paperless.W002`/`W003` warnings; archive count stays 0.

#### Should verify / decide

- [should] **Startup budget.** The s6 init chain runs `manage.py migrate` (`init-migrations`) and then `document_index reindex --if-needed` (`init-search-index`) **synchronously before the web server starts** — Whoosh is replaced by Tantivy and the schema-version mismatch (`search/_schema.py:137`) forces a full rebuild of all 1790 documents. Our startup probe is `periodSeconds: 30` x `failureThreshold: 5` ≈ 150s with no `initialDelaySeconds`. 1790 docs is small, but the CPU request is `10m` on a single node. **Action: raise `failureThreshold` for the cutover (e.g. 20 ≈ 10 min) and watch the init logs; revert afterwards or keep the safer value.** → Settled: kept at `20`; the init chain took ~25s so it is never active today.
- [should] **paperless-gpt (v0.27.0) API compatibility.** v3 drops API v1 and all versions < 9; unversioned clients are now served **v10** (`settings/__init__.py:166-169`). paperless-gpt sends no `Accept: application/json; version=N` header, so it silently jumps v1 -> v10. Its release predates v3.0.0 by one day (2026-07-21 vs 2026-07-22) — there is no v3-tested paperless-gpt release. Mitigating evidence: it writes `created_date`, which is deprecated but still functional in v3 (`serialisers.py:1060,1190`), and it uses only `api/documents/` endpoints. **Action: smoke-test after cutover; treat a failure as a rollback trigger for paperless-gpt, not for paperless.** → Read path verified; the write path (PATCH) remains the one untested criterion (see Still open).
- [should] **Login rate limiting behind the proxy chain.** Allauth changed client-IP determination; paperless is exposed publicly on `docs.${PUBLIC_DOMAIN}` through Cloudflare Tunnel -> envoy-external. We set `PAPERLESS_TRUSTED_PROXIES` but neither `PAPERLESS_ALLAUTH_TRUSTED_PROXY_COUNT` nor `PAPERLESS_ALLAUTH_TRUSTED_CLIENT_IP_HEADER`. **Action: verify a login through the public hostname after cutover; if it 403s, add the proxy-count/header setting.** → Verified by the human: no allauth 403, no extra setting needed. Related to [[client-ip-trust-topology]].
- [should] **Rollback path vs. the nightly export.** The `backup` CronJob runs `document_exporter ... --delete` at 00:30 into `${NAS_IP}:/backups/paperless`. After the upgrade that CronJob runs from the **v3** image and `--delete` overwrites the v2-format export — destroying the import-based rollback path. **Action: suspend the CronJob (or snapshot `/backups/paperless`) before cutover, re-enable after acceptance.** → Done: suspended, re-enabled in the settle commit `80ad23765`.

#### No action needed (verified against our config)

- [ok] **Prerequisite = 2.20.15.** We run exactly `2.20.15@sha256:835974fc...`; the direct 2.20.15 -> 3.0.5 jump is allowed. (Note: **skip 3.0.1** — its own release note says a DB-migration bug makes it unrunnable; 3.0.5 is unaffected.)
- [ok] **`PAPERLESS_SECRET_KEY` now required** — already delivered via the `paperless` ExternalSecret. Keeping the existing value preserves sessions and tokens.
- [ok] **Document/thumbnail encryption removed** — all 1790 documents are `storage_type=unencrypted`, so `decrypt_documents` is NOT needed.
- [ok] **Pre/post-consume positional args removed** — `config/pre-consume.sh` already reads `DOCUMENT_WORKING_PATH`, never `$1`. That variable still exists in v3 (`consumer.py:310`, `docs/advanced_usage.md:208`). No script change.
- [ok] **`CONSUMER_BARCODE_SCANNER` removed (pyzbar dropped)** — we never set it; barcodes are commented out.
- [ok] **`PAPERLESS_DBENGINE` now mandatory for PostgreSQL/MariaDB** — we are SQLite and already set it explicitly.
- [ok] **DB advanced options consolidated into `PAPERLESS_DB_OPTIONS`** — none of the removed `DBSSL*`/`DB_POOLSIZE`/`DB_TIMEOUT` variables are set.
- [ok] **Duplicate handling default flipped** — v3 allows duplicates by default; we already set `PAPERLESS_CONSUMER_DELETE_DUPLICATES: "true"`, which re-enables rejection. Keep it.
- [ok] **Search syntax `note:` -> `notes.note:`, `custom_field:` -> `custom_fields.value:`** — all 7 saved views use only tag filters (rule_type 6/17) and plain `title_content` terms ("Y2025"); none carries a `note:`/`custom_field:` prefix, so the auto-migration is a no-op and no unqualified query silently loses note matches.
- [ok] **OIDC `token_auth_method`** — paperless has no native OIDC client today (no `PAPERLESS_SOCIALACCOUNT_PROVIDERS`); it is still a Phase 2 remainder in [[app-auth-coverage]]. N/A now, but it becomes a prerequisite when that phase lands.
- [ok] **`MailRule.maximum_age` clamped to 32767** — zero mail rules exist; `PAPERLESS_EMAIL_TASK_CRON` is disabled.
- [ok] **NumPy x86-64-v2 CPU floor** — the node is an HP ProDesk 600 G6 (Comet Lake), far newer than the SSE4.2 floor. `PAPERLESS_TRAIN_TASK_CRON` is already `disable` anyway.
- [ok] **Task history dropped on upgrade** — informational; the task list starts empty.
- [ok] **Python 3.10 support dropped** — container-internal, no host impact.

#### Optional cleanup (not required)

- [cleanup] `PAPERLESS_EXPORT_DIR` is not a recognized setting in v3 (zero hits across `src/` and `docs/`); the CronJob passes `/data/nas/export` positionally. Harmless no-op that can be dropped from both containers.
- [cleanup] Consider `PAPERLESS_CONSUMER_STABILITY_DELAY` (new, default 5.0s) if scanner writes over NFS ever get consumed half-written. → Active (5.0 verified effective).

### Acceptance criteria

- Pod reaches Ready without a CrashLoop; the init log shows migrations applied and the Tantivy index rebuilt.
- Startup logs contain **no** `paperless.W002` / `paperless.W003` warnings (proves the OCR/archive env rewrite is complete).
- A full-text search from the UI returns results (Tantivy index populated, 1790 docs).
- A file dropped into `/scanner/paperless-inbox` on the NAS is consumed within ~60s (proves `CONSUMER_POLLING_INTERVAL` + the ignore-pattern removal).
- A password-protected and a blank-page PDF still process correctly (pre-consume script on `DOCUMENT_WORKING_PATH`).
- `Document.objects.exclude(archive_filename=None).count()` stays **0** after consuming a new document (proves `ARCHIVE_FILE_GENERATION=never`).
- Login through `https://docs.${PUBLIC_DOMAIN}` succeeds (no allauth 403).
- paperless-gpt tags/renames a new document end-to-end (API v10 compatibility).
- The next `document_exporter` CronJob run completes successfully against `/backups/paperless`.

All criteria passed (see the execution record below); the paperless-gpt write-path criterion is the only one never exercised directly — not blocking (read path verified).

### Risks / blast radius

- **Ignore-pattern regex:** worst case, silent total consumption stop with no error — the failure looks like "the scanner folder just never empties". Mitigated by deleting the variable and by the inbox acceptance test.
- **Polling rename:** same silent-stop failure mode on NFS. Same test covers it.
- **Archive generation:** unplanned PVC growth on a 20Gi volume; not an outage, but it changes the storage profile and the VolSync backup size. Mitigated by the explicit `never`.
- **Tantivy rebuild:** if it exceeds the startup budget, the kubelet kills the pod mid-rebuild and it loops. Mitigated by the raised `failureThreshold`; the rebuild is idempotent and restartable.
- **Zeroscaler interaction:** the `zeroscaler` component scales the Deployment to 0 whenever the `nfs_probe` `probe_success` external metric drops. An NFS blip during the migration would scale the pod away mid-migrate. The `migration_lock` flock makes a restart safe, but consider watching the probe during cutover.
- **Rollback:** `just volsync restore paperless 0 selfhosted` (wipes the PVC and restores the Kopia snapshot) plus reverting the commit. This is the ONLY reliable rollback — the SQLite schema is migrated forward in place and paperless has no downgrade migrations. The export-based path is secondary and only survives if Phase 1 step 2 was done.

### Explicitly out of scope

- Native OIDC for paperless -> [[app-auth-coverage]] Phase 2.
- The `paperless-gpt` `PAPERLESS_PUBLIC_URL` pointing at `documents.${PUBLIC_DOMAIN}` while the paperless route is `docs.${PUBLIC_DOMAIN}` — a pre-existing inconsistency, unrelated to v3.
- v3's new opt-in features (Paperless AI / LLM index, remote OCR via Azure AI, document file versions, sharelink bundles, the parser plugin framework). None are enabled by this upgrade.
- Enabling archive generation as a deliberate product choice — that is a separate decision, not a migration step.

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

## Relations

- relates_to [[k8s-workloads]] — paperless is a selfhosted app with the canonical shape; the env block is the only thing this item touches
- relates_to [[volsync-backup]] — the pre-cutover snapshot is the rollback path; the archive-generation decision changes the backed-up volume size
- relates_to [[client-ip-trust-topology]] — the allauth client-IP change lands on the same external proxy chain
- relates_to [[app-auth-coverage]] — paperless is a Phase 2 remainder; the v3 OIDC `token_auth_method` note becomes a prerequisite there
