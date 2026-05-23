---
title: resticprofile-backup
type: area_reference
permalink: home-ops/docs/areas/resticprofile-backup
area: resticprofile-backup
status: current
confidence: high
verified_at: '2026-05-22'
summary: File-level backups of the shared NAS /backups tree run from a single in-cluster
  resticprofile workload. It reads /backups from the OMV NFS server (${d}{NAS_IP}),
  pushes encrypted Restic snapshots to OVH Object Storage on a 01:00 daily cadence,
  weekly check (Mon 05:00) and forget+prune (Tue 05:00). Backrest is the read-only
  browse + restore UI for that same Restic repo. Both apps share one Secret (resticprofile-secret)
  rendered by an ExternalSecret. Health is reported to Healthchecks.io via webhooks
  emitted from inside resticprofile send-before/send-after hooks.
verified_against:
- kubernetes/apps/default/resticprofile/ks.yaml
- kubernetes/apps/default/resticprofile/app/helmrelease.yaml
- kubernetes/apps/default/resticprofile/app/externalsecret.yaml
- kubernetes/apps/default/resticprofile/app/config/profiles.yaml
- kubernetes/apps/default/resticprofile/app/ocirepository.yaml
- kubernetes/apps/default/resticprofile/readme.md
- kubernetes/apps/default/backrest/ks.yaml
- kubernetes/apps/default/backrest/app/helmrelease.yaml
- kubernetes/apps/default/CLAUDE.md
drift_risk: The whole plane is intentionally one workload — there is no app-by-app
  segmentation. The shared NAS at ${d}{NAS_IP} with the /backups export is the source-of-truth
  for everything; if it's offline at 01:00 the daily backup silently produces an empty
  snapshot (no errors from Restic, just the previous tree). RESTIC_PASSWORD and the
  OVH credentials live in the same 1Password resticprofile + ovh items as plain shared
  secrets — a rotation rotates ALL apps using this plane. The resticprofile container
  runs as the bjw-s default nobody user (65532) but the Flux Kustomization passes
  APP_UID/APP_GID=0 via postBuild — the substitution is unused by the chart, so the
  contradiction is cosmetic, but a future change that wires APP_UID into a securityContext
  would silently grant root.
tags:
- area-reference
- resticprofile-backup
- backup
- platform
---

# resticprofile-backup — current state

## Metadata (observation-form, schema validation)

- [area] resticprofile-backup
- [status] current
- [confidence] high
- [verified_at] 2026-05-19

## Summary

The cluster runs a **second** backup plane in parallel with VolSync. While VolSync handles PVC-level snapshots per app, `resticprofile` covers **file-level** backups of the shared NAS `/backups` tree on the OMV NFS server (`${NAS_IP}`). The same Restic repo is browseable and restorable through **Backrest**, a separate workload that shares the credentials Secret with resticprofile.

`resticprofile` is one HelmRelease in `default` (chart `resticprofile` via OCIRepository), running a single replicated Deployment that bootstraps with `resticprofile schedule --all` then `exec`s into `supercronic /resticprofile/crontab`. The schedule is hardcoded in the embedded `profiles.yaml`:

- `backup` at `01:00` daily — sources `/backups` (mounted read-only from NFS)
- `check` on `Mon 05:00` with `read-data-subset: 100%` (full data integrity check)
- `forget` on `Tue 05:00` with retention `keep-hourly=1`, `keep-daily=7`, `keep-weekly=4`, `keep-monthly=12` and `prune: true`
- restore target hardcoded to /mnt/nfs-tmp/resticprofile-restore/backups (a writable NFS share at ${NAS_IP}:/tmp)

Every scheduled command emits Healthchecks.io webhooks: `send-before $URL/start`, `send-after $URL` on success, `send-after-fail $URL/fail` with the captured stderr — separately for the `backup` profile and the weekly `check` profile (two webhook env vars, `HEALTHCHECK_BACKUPS_WEBHOOK` and `HEALTHCHECK_BACKUPS_CHECK_WEBHOOK`).

The repo is reached as `RESTIC_REPOSITORY=s3:https://<ovh_s3_endpoint>/<RESTIC_S3_BUCKET>` using the **same** OVH Cloud Project user as VolSync (both planes share the `HomeOps/ovh` 1Password item, since the OVH S3 policy is bucket-scoped). The credentials Secret `resticprofile-secret` is rendered by an ExternalSecret that pulls from 1P items `resticprofile` (RESTIC_PASSWORD, RESTIC_S3_BUCKET, two webhook URLs) and `ovh` (S3 endpoint + access keys).

**Backrest** is the read-only browse and restore UI. It reads the same Restic repo (same `resticprofile-secret`, same env vars) and is exposed via Gateway API on `${PUBLIC_DOMAIN}`-prefixed hostname from both `envoy-external` and `envoy-internal`. Backrest also wires the shared `/backups` NFS export read-only and a writable `/restore` mount at `${NAS_IP}:/tmp/resticprofile-restore`, so restored content drops back onto the NAS rather than a PVC.

App-level export jobs into `/backups/<app>` are out of scope for this area — they live in the per-app subtrees (Paperless is the canonical example referenced in `kubernetes/CLAUDE.md` and `kubernetes/apps/default/CLAUDE.md`). Their snapshots end up here because resticprofile picks up everything under `/backups` at backup time.

## Components

- [component] resticprofile workload — HelmRelease in `default`, chart `resticprofile` via OCIRepository, bjw-s app-template, image `ghcr.io/zhorvath83/resticprofile:0.32.0` (digest-pinned), runs as UID/GID 65532 with RuntimeDefault seccomp, `readOnlyRootFilesystem: true`, drops ALL caps, no service or route (kubernetes/apps/default/resticprofile/app/helmrelease.yaml)
- [component] resticprofile Flux Kustomization — depends on `onepassword-connect` + `democratic-csi`, passes `APP_UID=0`/`APP_GID=0` via `postBuild.substitute` (no consumer in the chart values — substitution is cosmetic) (kubernetes/apps/default/resticprofile/ks.yaml)
- [component] resticprofile ExternalSecret — emits Secret `resticprofile-secret` with `RESTIC_PASSWORD`, `RESTIC_REPOSITORY=s3:https://<ovh_s3_endpoint>/<RESTIC_S3_BUCKET>`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, plus the two Healthchecks.io webhooks; pulls from 1P items `resticprofile` and `ovh`, refresh 12h (kubernetes/apps/default/resticprofile/app/externalsecret.yaml)
- [component] resticprofile profiles.yaml — single `backups` profile, scheduler `crontab:-:/resticprofile/crontab` (resticprofile generates the crontab in-place at startup), `compression: auto`, `initialize: true`, sources `/backups` (kubernetes/apps/default/resticprofile/app/config/profiles.yaml)
- [component] resticprofile mounts — emptyDir on `/resticprofile` (state) and `/tmp`, ConfigMap mount of `profiles.yaml` at `/resticprofile/profiles.yaml` (read-only, mode 0444), NFS mount `${NAS_IP}:/tmp` at `/mnt/nfs-tmp` (rw, used for logs + restore target), NFS mount `${NAS_IP}:/backups` at `/backups` (RO, the backup source) (kubernetes/apps/default/resticprofile/app/helmrelease.yaml:91-122)
- [component] backrest workload — HelmRelease in `default`, chart `backrest` via OCIRepository, bjw-s app-template, image `garethgeorge/backrest:v1.13.0` (digest-pinned), runs as UID/GID 10001 (kubernetes/apps/default/backrest/app/helmrelease.yaml)
- [component] backrest Flux Kustomization — depends on `onepassword-connect` + `democratic-csi`, attaches the `components/volsync` component with `APP=backrest` for its own PVC backup (kubernetes/apps/default/backrest/ks.yaml)
- [component] backrest credential reuse — env vars `RESTIC_PASSWORD`, `RESTIC_REPOSITORY`, AWS S3 creds all reference the same `resticprofile-secret` (kubernetes/apps/default/backrest/app/helmrelease.yaml:38-66)
- [component] backrest data — PVC `backrest` (managed by VolSync since the ks.yaml wires the volsync component) for the Backrest internal database, plus NFS RO of `/backups` and NFS RW of `${NAS_IP}:/tmp/resticprofile-restore` mounted at `/restore` (kubernetes/apps/default/backrest/app/helmrelease.yaml:118-135)
- [component] backrest exposure — HTTPRoute at `${PUBLIC_DOMAIN}`-prefixed hostname on both `envoy-external` and `envoy-internal`, Homepage annotations under group `Infrastructure` (kubernetes/apps/default/backrest/app/helmrelease.yaml:98-116)
- [component] Healthchecks.io reporting — `send-before` HEAD `{URL}/start`, `send-after` HEAD `{URL}`, `send-after-fail` POST `{URL}/fail` with the failing command's stderr; one webhook per profile (backups, backups-check)

## Claims (verified against repo)

- [claim] "Resticprofile and Backrest are two separate apps in namespace `default`; resticprofile generates the backups, Backrest is the read-only browse + restore UI; they share the credential Secret `resticprofile-secret`" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/externalsecret.yaml + kubernetes/apps/default/backrest/app/helmrelease.yaml:38-66, verified: 2026-05-19)
- [claim] "The backup source is the OMV NFS export `${NAS_IP}:/backups`, mounted **read-only** in resticprofile. The restore target is `${NAS_IP}:/tmp/resticprofile-restore/backups`, a writable NFS share also used by Backrest at `/restore`" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/helmrelease.yaml:110-122 + config/profiles.yaml:77-78 + backrest/app/helmrelease.yaml:122-128, verified: 2026-05-19)
- [claim] "The Restic repository URL is `s3:https://<ovh_s3_endpoint>/<RESTIC_S3_BUCKET>` — the OVH S3 endpoint comes from the same `HomeOps/ovh` 1Password item used by VolSync; `RESTIC_S3_BUCKET` comes from the per-app `HomeOps/resticprofile` 1Password item" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/externalsecret.yaml:18-23, verified: 2026-05-19)
- [claim] "Inside the resticprofile Pod the container runs `resticprofile schedule --all` once at startup (re-emits the crontab) then `exec`s into `supercronic /resticprofile/crontab` — a single long-lived PID 1 that runs the cron loop" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/helmrelease.yaml:33-37, verified: 2026-05-19)
- [claim] "Single `backups` profile in `profiles.yaml`: `backup` at `01:00` daily, `check` on `Mon 05:00` with `read-data-subset: 100%`, `forget` on `Tue 05:00` with retention hourly=1 daily=7 weekly=4 monthly=12 and `prune: true`, `restore` target hardcoded to `/mnt/nfs-tmp/resticprofile-restore/backups`" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/config/profiles.yaml:11-79, verified: 2026-05-19)
- [claim] "Each scheduled profile emits three Healthchecks.io webhooks: `send-before {URL}/start`, `send-after {URL}` on success, `send-after-fail {URL}/fail` POST with the failing command's stderr — `HEALTHCHECK_BACKUPS_WEBHOOK` for backup, `HEALTHCHECK_BACKUPS_CHECK_WEBHOOK` for check" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/config/profiles.yaml:30-42,51-63 + externalsecret.yaml:22-23, verified: 2026-05-19)
- [claim] "Resticprofile container runs as UID/GID 65532 (nobody) with `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, drops ALL caps, RuntimeDefault seccomp, `automountServiceAccountToken: false`, `enableServiceLinks: false`. The Flux Kustomization passes `APP_UID=0` / `APP_GID=0` via `postBuild.substitute` but the chart values do not consume them — the substitution is cosmetic" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/helmrelease.yaml:13-23 + ks.yaml:18-22, verified: 2026-05-19)
- [claim] "Backrest's own Backrest internal DB is itself backed up by VolSync — `kubernetes/apps/default/backrest/ks.yaml` attaches `components/volsync` with `APP=backrest`" (evidence: repo, ref: kubernetes/apps/default/backrest/ks.yaml:11-22, verified: 2026-05-19)
- [claim] "Backrest is exposed on a `${PUBLIC_DOMAIN}`-prefixed hostname from both `envoy-external` and `envoy-internal` Gateways; has Homepage annotations under group `Infrastructure`" (evidence: repo, ref: kubernetes/apps/default/backrest/app/helmrelease.yaml:98-116, verified: 2026-05-19)
- [claim] "Both workloads depend on `onepassword-connect` (for the shared Secret) and `democratic-csi` (Backrest has its own PVC; resticprofile pulls in democratic-csi indirectly through the dependency)" (evidence: repo, ref: kubernetes/apps/default/resticprofile/ks.yaml:11-15 + backrest/ks.yaml:13-17, verified: 2026-05-19)
- [claim] "Resticprofile uses `restic-lock-retry-after: 5m`, `restic-stale-lock-age: 24h`, and `force-inactive-lock: true` to recover from leftover locks; each profile also uses `schedule-lock-mode: default` with `schedule-lock-wait: 1h` so the cron triggers wait up to an hour rather than skipping" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/config/profiles.yaml:5-19,46-50,68-70, verified: 2026-05-19)
- [claim] "Resticprofile per-run logs go to NFS at `/mnt/nfs-tmp/resticprofile-logs/` (one file per profile) — the OMV NAS keeps the logs even after Pod restarts" (evidence: repo, ref: kubernetes/apps/default/resticprofile/app/config/profiles.yaml:23,47,68, verified: 2026-05-19)
- [claim] "App-level export jobs into `/backups/<app>` are out of scope for this area; the example pattern (Paperless) lives in its own per-app subtree and writes into the shared NFS tree that resticprofile then sweeps. The repo-level rule is in `kubernetes/apps/default/CLAUDE.md`" (evidence: repo, ref: kubernetes/apps/default/CLAUDE.md:25-27, verified: 2026-05-19)
- [claim] "Restoring a snapshot is documented as the resticprofile CLI inside the Pod: `resticprofile profiles` (list), `resticprofile <profile>.snapshots`, `resticprofile <profile>.restore <snapshot_ID>` — no just recipe wraps this" (evidence: repo, ref: kubernetes/apps/default/resticprofile/readme.md, verified: 2026-05-19)

## Drift Risk

- [drift] The whole file-level backup plane is one workload — no app-by-app segmentation. If one app misbehaves and dumps junk into `/backups`, the next nightly snapshot grows accordingly and Restic dedup may or may not help. The retention sweep (keep-hourly=1) is aggressive for hourly granularity; an accidentally-deleted file is recoverable only if you notice within 24h.
- [drift] If the OMV NAS (at `${NAS_IP}`) is offline at `01:00`, the daily backup still **runs**, but the source `/backups` mount will be stale or empty. Restic itself does not detect this and a successful run will be reported to Healthchecks.io. There is no health gate on NFS availability before the cron fires.
- [drift] `RESTIC_PASSWORD` and the OVH credentials are shared globals — rotating either invalidates ALL apps reading from `resticprofile-secret` (resticprofile + Backrest) and locks out historical access to the repository if the password is lost. No per-snapshot password isolation is possible with Restic.
- [drift] The Flux Kustomization for resticprofile substitutes `APP_UID=0` / `APP_GID=0`, which is **not** wired into any chart value today. The contradiction with the helmrelease's UID 65532 is cosmetic at the moment, but if a future change copies a sibling app's pattern of plumbing `APP_UID` into `securityContext` it would silently grant root in the resticprofile Pod.
- [drift] Backrest re-uses the same Restic repo with the same password — it has full read/write access to the repository, not just read-only browse. A compromised Backrest session can `forget` and `prune` historical snapshots; the Gateway exposure model relies on Cloudflare Access to keep it out of the public path.
- [drift] The `/mnt/nfs-tmp/resticprofile-restore/backups` directory is a single shared path used both as the resticprofile restore target and as the Backrest `/restore` mount. Concurrent restores from the two surfaces can collide silently.
- [drift] Restic OCIRepository tags and image digests (`ghcr.io/zhorvath83/resticprofile:0.32.0` plus the digest; `garethgeorge/backrest:v1.13.0` plus the digest) are Renovate-tracked through digest pinning, but a Renovate bump that updates only the tag without re-pulling the digest would break image resolution.

## Open Questions / Gaps

- [gap] No verification was run against the live cluster, NFS server, or OVH bucket in this pass — claims are repo-evidence only.
- [gap] The bucket that backs this plane is not named in the repo — `RESTIC_S3_BUCKET` is supplied from 1P. Confirming the OVH-side bucket name and that it appears in `provision/ovh` `S3_BUCKET_NAMES` is left to the ovh-storage cross-check.
- [gap] No restore SLO is captured — the only documented restore path is the resticprofile CLI inside the Pod, with no time-bound. Backrest is the suggested human path but its restore flow is not described in repo.
- [gap] The intentional pattern of "critical apps write a curated export to /backups/<app> in addition to PVC snapshots" (Paperless reference) was not enumerated here; a follow-up under k8s-workloads should list every app that maintains a /backups/<app> export so this plane's coverage is auditable.
- [gap] The relationship between Healthchecks.io project, the two webhooks, and the on-call alerting channel was not traced; only the in-cluster wiring is documented.

## Relations

- depends_on [[external-secrets]]
- depends_on [[ovh-storage]]
- relates_to [[volsync-backup]]
- relates_to [[k8s-workloads]]
- part_of [[home-ops-platform]]
