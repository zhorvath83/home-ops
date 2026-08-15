---
title: paperless-ngx-v3-migration
type: roadmap
permalink: home-ops/docs/roadmap/paperless-ngx-v3-migration
topic: Upgrade paperless-ngx 2.20.15 -> 3.0.5 (Renovate PR 4056), applying every v3 breaking change to the HelmRelease env in ONE atomic commit, because two of them silently break consumption and one silently changes storage behaviour.
status: proposed
priority: high
scope: kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml env block + image
  tag; the pre-consume ConfigMap script (verified compatible, no change); the nightly
  document_exporter CronJob (rollback-path implication); paperless-gpt API compatibility
  (unversioned client now served API v10).
rationale: 'Renovate PR #4056 bumps the image only. Merging it as-is is NOT safe:
  PAPERLESS_CONSUMER_IGNORE_PATTERNS becomes a regex list in v3, and our existing
  glob "._*" as a regex matches nearly every filename -> the consumer would ignore
  everything; PAPERLESS_CONSUMER_POLLING is renamed and the new default is 0 (inotify),
  which does not work on our NFS consume dir; and PAPERLESS_OCR_SKIP_ARCHIVE_FILE
  is removed, so archive generation silently flips from never to auto on a 20Gi PVC.
  All three are env-only fixes that must ship together with the image bump.'
related_areas:
- k8s-workloads
- volsync-backup
- networking
options:
- 'A (recommended): one atomic commit to main that bumps the image AND rewrites the
  env block; close Renovate PR #4056 as superseded.'
- 'B: push the env changes onto the Renovate branch renovate/ghcr.io-paperless-ngx-paperless-ngx-3.x
  and merge that PR.'
- 'Rejected: a config-prep commit before the image bump — PAPERLESS_CONSUMER_POLLING_INTERVAL
  does not exist in 2.20.15, so polling would silently stop and NFS consumption would
  break while still on v2.'
tags:
- roadmap
- paperless
- selfhosted
- major-upgrade
- breaking-change
- proposed
---

# paperless-ngx-v3-migration — 2.20.15 -> 3.0.5 breaking-change sweep

## Metadata (observation-form, schema validation)

- [topic] Upgrade paperless-ngx to v3 with every breaking change applied to the HelmRelease env in one atomic commit
- [status] proposed
- [priority] high
- [area] k8s-workloads
- [created] 2026-08-15
- [trigger] Renovate PR https://github.com/zhorvath83/home-ops/pull/4056 (major: 2.20.15 -> 3.0.5)
- [source] https://docs.paperless-ngx.com/migration-v3/ (read from the v3.0.5 tag: docs/migration-v3.md)

## Verification basis (how this item was built)

- Every claim below is checked against the **v3.0.5 source tree**, not against the rendered docs page (docs.paperless-ngx.com returns 403 to the fetcher): `src/paperless/settings/__init__.py`, `src/paperless/checks.py`, `src/documents/consumer.py`, `docs/configuration.md`, `docs/api.md`, `docker/rootfs/etc/s6-overlay/s6-rc.d/`.
- Live read-only state was measured on the running 2.20.15 pod (no mutation, no Secret reads): 1790 documents, all `storage_type=unencrypted`, 0 documents with an archive file, 7 saved views, 17 notes, 1 custom field, 0 mail rules, ApplicationConfiguration entirely NULL (so env vars govern, the DB-side OCR migration is a no-op for us).
- `/data/local/data` = 130M, `/data/local/media` = 288M on a 20Gi PVC.

## Breaking-change matrix (migration doc item -> our exposure -> action)

### Must change (breaks or silently changes behaviour)

- [must] **Consumer ignore patterns are now regex, not fnmatch.** Our `PAPERLESS_CONSUMER_IGNORE_PATTERNS` is a glob list; as a regex, `"._*"` means "any char, zero-or-more underscores" and matches nearly every filename via `re.search()` -> **the consumer would ignore every incoming file**. v3 built-in file defaults (`^\\.DS_Store$`, `^\\.DS_STORE$`, `^\\._.*`, `^desktop\\.ini$`, `^Thumbs\\.db$`) plus built-in dir defaults (`.stfolder`, `.stversions`, `.localized`, `@eaDir`, `.Spotlight-V100`, `.Trashes`, `__MACOSX`) already cover **all nine** of our entries, and user entries now *add to* the defaults. **Action: delete the variable entirely** (net reduction; no `CONSUMER_IGNORE_DIRS` needed either).
- [must] **`PAPERLESS_CONSUMER_POLLING` -> `PAPERLESS_CONSUMER_POLLING_INTERVAL`.** New default is `0` = native inotify, which is unreliable on our NFS consume dir (`nas-inbox`, `${NAS_IP}:/scanner/paperless-inbox`). Keeping the old name means polling silently stops. **Action: rename, keep `"60"`.**
- [must] **`PAPERLESS_OCR_SKIP_ARCHIVE_FILE` removed** (`checks.py:317`, warning `paperless.W002`) and **`PAPERLESS_OCR_MODE=skip` is not a valid value** (`checks.py:327`, warning `paperless.W003`; `settings/__init__.py:920` silently coerces it to `auto`). Left as-is the app still boots, but `ARCHIVE_FILE_GENERATION` falls back to its new default `auto` -> paperless starts writing PDF/A archives for image-based PDFs where today **0 of 1790** documents have one. On a 20Gi PVC that is an unplanned growth path. **Action: `PAPERLESS_OCR_MODE: "auto"` + `PAPERLESS_ARCHIVE_FILE_GENERATION: "never"`** — the documented equivalent of today's `skip` + `always`.

### Should verify / decide

- [should] **Startup budget.** The s6 init chain runs `manage.py migrate` (`init-migrations`) and then `document_index reindex --if-needed` (`init-search-index`) **synchronously before the web server starts** — Whoosh is replaced by Tantivy and the schema-version mismatch (`search/_schema.py:137`) forces a full rebuild of all 1790 documents. Our startup probe is `periodSeconds: 30` x `failureThreshold: 5` ≈ 150s with no `initialDelaySeconds`. 1790 docs is small, but the CPU request is `10m` on a single node. **Action: raise `failureThreshold` for the cutover (e.g. 20 ≈ 10 min) and watch the init logs; revert afterwards or keep the safer value.**
- [should] **paperless-gpt (v0.27.0) API compatibility.** v3 drops API v1 and all versions < 9; unversioned clients are now served **v10** (`settings/__init__.py:166-169`). paperless-gpt sends no `Accept: application/json; version=N` header, so it silently jumps v1 -> v10. Its release predates v3.0.0 by one day (2026-07-21 vs 2026-07-22) — there is no v3-tested paperless-gpt release. Mitigating evidence: it writes `created_date`, which is deprecated but still functional in v3 (`serialisers.py:1060,1190`), and it uses only `api/documents/` endpoints. **Action: smoke-test after cutover (list by tag, download, PATCH title/tags/correspondent/created_date); treat a failure as a rollback trigger for paperless-gpt, not for paperless.**
- [should] **Login rate limiting behind the proxy chain.** Allauth changed client-IP determination; paperless is exposed publicly on `docs.${PUBLIC_DOMAIN}` through Cloudflare Tunnel -> envoy-external. We set `PAPERLESS_TRUSTED_PROXIES` but neither `PAPERLESS_ALLAUTH_TRUSTED_PROXY_COUNT` nor `PAPERLESS_ALLAUTH_TRUSTED_CLIENT_IP_HEADER`. **Action: verify a login through the public hostname after cutover; if it 403s, add the proxy-count/header setting.** Related to [[client-ip-trust-topology]].
- [should] **Rollback path vs. the nightly export.** The `backup` CronJob runs `document_exporter ... --delete` at 00:30 into `${NAS_IP}:/backups/paperless`. After the upgrade that CronJob runs from the **v3** image and `--delete` overwrites the v2-format export — destroying the import-based rollback path. **Action: suspend the CronJob (or snapshot `/backups/paperless`) before cutover, re-enable after acceptance.**

### No action needed (verified against our config)

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

### Optional cleanup (not required)

- [cleanup] `PAPERLESS_EXPORT_DIR` is not a recognized setting in v3 (zero hits across `src/` and `docs/`); the CronJob passes `/data/nas/export` positionally. Harmless no-op that can be dropped from both containers.
- [cleanup] Consider `PAPERLESS_CONSUMER_STABILITY_DELAY` (new, default 5.0s) if scanner writes over NFS ever get consumed half-written.

## What to do

### Phase 1 — pre-flight (before touching anything)

1. `just volsync snapshot paperless selfhosted` and confirm the snapshot with `just volsync list-snapshots paperless selfhosted`.
2. Suspend the nightly export CronJob so the v3 exporter cannot `--delete` the v2-format export.
3. Record the current `X-Api-Version` / behaviour of paperless-gpt as the smoke-test baseline.

### Phase 2 — one atomic commit (image + env together)

Edit `kubernetes/apps/selfhosted/paperless/app/helmrelease.yaml`:

- image tag `2.20.15@sha256:...` -> `3.0.5@sha256:...` (both the `app` container and, via the `&image` anchor, the backup CronJob)
- delete `PAPERLESS_CONSUMER_IGNORE_PATTERNS`
- `PAPERLESS_CONSUMER_POLLING: "60"` -> `PAPERLESS_CONSUMER_POLLING_INTERVAL: "60"`
- `PAPERLESS_OCR_MODE: "skip"` -> `"auto"`
- delete `PAPERLESS_OCR_SKIP_ARCHIVE_FILE: "always"`, add `PAPERLESS_ARCHIVE_FILE_GENERATION: "never"`
- raise the startup probe `failureThreshold` for the migration + Tantivy rebuild

Then close Renovate PR #4056 as superseded (option A) or push these onto its branch (option B).

### Phase 3 — cutover + verification

Reconcile, watch the init chain (`init-migrations` -> `init-search-index`), then run the acceptance criteria below.

### Phase 4 — settle

Re-enable the export CronJob, verify the first v3 export completes, revert the temporary probe value if desired, and update `docs/areas/k8s-workloads`.

## Acceptance criteria

- Pod reaches Ready without a CrashLoop; the init log shows migrations applied and the Tantivy index rebuilt.
- Startup logs contain **no** `paperless.W002` / `paperless.W003` warnings (proves the OCR/archive env rewrite is complete).
- A full-text search from the UI returns results (Tantivy index populated, 1790 docs).
- A file dropped into `/scanner/paperless-inbox` on the NAS is consumed within ~60s (proves `CONSUMER_POLLING_INTERVAL` + the ignore-pattern removal).
- A password-protected and a blank-page PDF still process correctly (pre-consume script on `DOCUMENT_WORKING_PATH`).
- `Document.objects.exclude(archive_filename=None).count()` stays **0** after consuming a new document (proves `ARCHIVE_FILE_GENERATION=never`).
- Login through `https://docs.${PUBLIC_DOMAIN}` succeeds (no allauth 403).
- paperless-gpt tags/renames a new document end-to-end (API v10 compatibility).
- The next `document_exporter` CronJob run completes successfully against `/backups/paperless`.

## Risks / what could break (blast radius per change)

- **Ignore-pattern regex:** worst case, silent total consumption stop with no error — the failure looks like "the scanner folder just never empties". Mitigated by deleting the variable and by the inbox acceptance test.
- **Polling rename:** same silent-stop failure mode on NFS. Same test covers it.
- **Archive generation:** unplanned PVC growth on a 20Gi volume; not an outage, but it changes the storage profile and the VolSync backup size. Mitigated by the explicit `never`.
- **Tantivy rebuild:** if it exceeds the startup budget, the kubelet kills the pod mid-rebuild and it loops. Mitigated by the raised `failureThreshold`; the rebuild is idempotent and restartable.
- **Zeroscaler interaction:** the `zeroscaler` component scales the Deployment to 0 whenever the `nfs_probe` `probe_success` external metric drops. An NFS blip during the migration would scale the pod away mid-migrate. The `migration_lock` flock makes a restart safe, but consider watching the probe during cutover.
- **Rollback:** `just volsync restore paperless 0 selfhosted` (wipes the PVC and restores the Kopia snapshot) plus reverting the commit. This is the ONLY reliable rollback — the SQLite schema is migrated forward in place and paperless has no downgrade migrations. The export-based path is secondary and only survives if Phase 1 step 2 was done.

## Explicitly out of scope

- Native OIDC for paperless -> [[app-auth-coverage]] Phase 2.
- The `paperless-gpt` `PAPERLESS_PUBLIC_URL` pointing at `documents.${PUBLIC_DOMAIN}` while the paperless route is `docs.${PUBLIC_DOMAIN}` — a pre-existing inconsistency, unrelated to v3.
- v3's new opt-in features (Paperless AI / LLM index, remote OCR via Azure AI, document file versions, sharelink bundles, the parser plugin framework). None are enabled by this upgrade.
- Enabling archive generation as a deliberate product choice — that is a separate decision, not a migration step.

## Related

- relates_to [[k8s-workloads]] — paperless is a selfhosted app with the canonical shape; the env block is the only thing this item touches.
- relates_to [[volsync-backup]] — the pre-cutover snapshot is the rollback path; the archive-generation decision changes the backed-up volume size.
- relates_to [[client-ip-trust-topology]] — the allauth client-IP change lands on the same external proxy chain.
- relates_to [[app-auth-coverage]] — paperless is a Phase 2 remainder; the v3 OIDC `token_auth_method` note becomes a prerequisite there.
