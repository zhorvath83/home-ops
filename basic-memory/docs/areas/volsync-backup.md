---
title: volsync-backup
type: area_reference
permalink: home-ops/docs/areas/volsync-backup
area: volsync-backup
status: current
confidence: high
verified_at: '2026-05-22'
summary: Cluster PVC backups use VolSync with the Kopia mover, targeting OVH Object
  Storage. The platform under kubernetes/apps/volsync-system/ deploys the VolSync
  operator (perfectra1n fork), Kopia repository-server browser UI, KopiaMaintenance
  CR, a cluster-wide MutatingAdmissionPolicy that injects a 0-300s jitter initContainer
  into every volsync-src-* Job, and PrometheusRules. Per-app wiring is a Kustomize
  component at kubernetes/components/volsync/ parameterized by APP-style variables
  — it produces an ExternalSecret, PVC bootstrap from a ReplicationDestination, an
  hourly ReplicationSource, and a permanently-rendered-but-idle bootstrap RD with
  IfNotPresent SSA. Operational flows are just volsync recipes.
verified_against:
- kubernetes/apps/volsync-system/kustomization.yaml
- kubernetes/apps/volsync-system/namespace.yaml
- kubernetes/apps/volsync-system/CLAUDE.md
- kubernetes/apps/volsync-system/volsync/ks.yaml
- kubernetes/apps/volsync-system/volsync/app/helmrelease.yaml
- kubernetes/apps/volsync-system/volsync/app/ocirepository.yaml
- kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml
- kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml
- kubernetes/apps/volsync-system/volsync/maintenance/kopiamaintenance.yaml
- kubernetes/apps/volsync-system/volsync/maintenance/externalsecret.yaml
- kubernetes/apps/volsync-system/kopia/ks.yaml
- kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml
- kubernetes/apps/volsync-system/kopia/app/externalsecret.yaml
- kubernetes/components/volsync/kustomization.yaml
- kubernetes/components/volsync/externalsecret.yaml
- kubernetes/components/volsync/pvc.yaml
- kubernetes/components/volsync/replicationsource.yaml
- kubernetes/components/volsync/replicationdestination.yaml
- kubernetes/volsync/mod.just
drift_risk: VolSync runs the perfectra1n fork of the operator and its mover images
  (ghcr.io/perfectra1n/volsync), pinned via Helm chart fullnameOverride —
  upstream resource names are required for the chart but the image is forked. Kopia
  Server runs read-only with enableActions disabled; do not enable actions without
  revisiting the security model. The component contract (APP, APP-bootstrap, APP-volsync-secret)
  is referenced by just volsync recipes and by app-level Flux Kustomizations through
  variable substitution; renames break both. Bootstrap RDs carry the IfNotPresent
  SSA label so Flux applies them once and never overwrites — fresh fetches from Kopia
  require deleting both the PVC AND the bootstrap RD (documented in the platform CLAUDE.md).
tags:
- area-reference
- volsync-backup
- backup
- platform
---

# volsync-backup — current state

## Metadata (observation-form, schema validation)

- [area] volsync-backup
- [status] current
- [confidence] high
- [verified_at] 2026-05-19

## Summary

PVC-level cluster backups are handled by VolSync + Kopia + OVH Object Storage. The platform side under `kubernetes/apps/volsync-system/` provides three sub-Kustomizations — `volsync` (the operator, depends on `snapshot-controller`), `volsync-maintenance` (the KopiaMaintenance CR + its ExternalSecret, depends on `onepassword-connect` + `volsync`), and `kopia` (the Kopia repository-server browser UI, depends on `onepassword-connect` + `volsync`). Operator and movers all use the **perfectra1n fork** image `ghcr.io/perfectra1n/volsync` across kopia/restic/rsync/rsync-tls/syncthing variants; `fullnameOverride: volsync` keeps upstream resource names so app components keep working.

A cluster-wide MutatingAdmissionPolicy (`volsync-mover-jitter`) injects a `busybox` initContainer that sleeps 0-300s into every Job whose name starts with `volsync-src-` and whose `app.kubernetes.io/created-by` label is `volsync`, smoothing the herd-effect of the hourly schedules. PrometheusRules fire `VolSyncComponentAbsent` (target down 15m, critical) and `VolSyncVolumeOutOfSync` (any volume out of sync 15m, critical).

Per-app wiring is a Kustomize **component** at `kubernetes/components/volsync/`, parameterized by the variables `${APP}`, `${VOLSYNC_*}`, and `${APP_UID/APP_GID}` (replaced by Flux's Kustomization `postBuild.substitute` at apply time). The component renders four resources: an ExternalSecret that emits a `${APP}-volsync-secret` carrying the Kopia repository URL + password + S3 credentials (pulled from 1P items `volsync-template` and `ovh`), a PVC `${APP}` whose `dataSourceRef` is the bootstrap RD, a ReplicationSource `${APP}` running on `VOLSYNC_SCHEDULE` (default hourly), and a bootstrap ReplicationDestination `${APP}-bootstrap` rendered with `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` and trigger `manual: restore-once` — Flux applies it once at first reconcile and never re-templates it.

Operational flows are wrapped by `just volsync` recipes: `snapshot` and `snapshot-all` (manual trigger), `restore` (full app teardown + wipe Job + Direct-method RD + Flux resume), `list-snapshots` (Kopia CLI inside the kopia Deployment), `kopia-maintenance` (manual trigger of `kopia-daily-maintenance` CR with status polling), `last-snapshots` (Python report on all RSes for a given date with Budapest-local times), and `state suspend|resume` (cluster-wide pause of the operator + HelmRelease + scale-to-zero of the Deployment).

## Components

- [component] VolSync operator — HelmRelease in `volsync-system`, chart from `OCIRepository/volsync`, `fullnameOverride: volsync` (perfectra1n fork wiring), all mover images shared via the `*image` YAML anchor (`ghcr.io/perfectra1n/volsync` for kopia/restic/rclone/rsync/rsync-tls/syncthing), `manageCRDs: true`, `metrics.disableAuth: true`, runs as UID/GID 1000 with RuntimeDefault seccomp (kubernetes/apps/volsync-system/volsync/app/helmrelease.yaml)
- [component] volsync Kustomization — depends on `snapshot-controller` in `kube-system` (kubernetes/apps/volsync-system/volsync/ks.yaml:11-13)
- [component] volsync-maintenance Kustomization — depends on `onepassword-connect` + `volsync`; deploys `KopiaMaintenance/kopia-daily-maintenance` running at `0 12 * * *` against repository alias `volsync-secret` + its ExternalSecret (volsync/maintenance/kopiamaintenance.yaml + externalsecret.yaml)
- [component] kopia browser — HelmRelease using bjw-s app-template, image `ghcr.io/home-operations/kopia` (digest-pinned), runs read-only (`readOnlyRootFilesystem: true`, drops ALL caps), serves `--without-password` web UI on `${PUBLIC_DOMAIN}`-prefixed hostname via both `envoy-external` and `envoy-internal` Gateways, persists `/config/repository.config` from `kopia-secret`, cache/logs/tmp on emptyDir (kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml)
- [component] kopia ExternalSecret — emits Secret `kopia-secret` with both `KOPIA_PASSWORD` env and a templated `repository.config` JSON pointing at the same OVH S3 bucket with `enableActions: false`; pulls from 1P items `volsync-template` and `ovh` (kubernetes/apps/volsync-system/kopia/app/externalsecret.yaml)
- [component] cluster-wide jitter MutatingAdmissionPolicy — `volsync-mover-jitter` matches `batch/v1` Jobs on CREATE/UPDATE where `metadata.name` starts with `volsync-src-` AND label `app.kubernetes.io/created-by == "volsync"`, injects a `busybox` initContainer that runs `sleep \$(shuf -i 0-300 -n 1)`; binding is via `MutatingAdmissionPolicyBinding` of the same name, `failurePolicy: Fail`, `reinvocationPolicy: IfNeeded` (kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml)
- [component] PrometheusRule — group `volsync.rules` with alerts `VolSyncComponentAbsent` (target down 15m, critical) and `VolSyncVolumeOutOfSync` (`volsync_volume_out_of_sync == 1` for 15m, critical) (kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml)
- [component] Per-app component — `kubernetes/components/volsync/` is a Kustomize `Component` with four resources: externalsecret, pvc, replicationsource, replicationdestination
- [component] Per-app ExternalSecret — emits `${APP}-volsync-secret` with keys `KOPIA_REPOSITORY=s3://{KOPIA_S3_BUCKET}`, `KOPIA_PASSWORD`, AWS S3 creds (pulled from 1P `volsync-template` + `ovh`), refresh 12h (components/volsync/externalsecret.yaml)
- [component] Per-app ReplicationSource — name `${APP}`, schedule `${VOLSYNC_SCHEDULE:=0 * * * *}` (hourly default), Kopia mover with `copyMethod: Snapshot`, `compression: zstd-fastest`, `parallelism: 2`, cacheCapacity 1Gi on `democratic-csi-local-hostpath`, mover security context `runAsUser/Group/fsGroup = ${APP_UID/GID:=10001}`, retain hourly=24 daily=7 weekly=2 monthly=1 (components/volsync/replicationsource.yaml)
- [component] Per-app bootstrap PVC — name `${VOLSYNC_CLAIM:=${APP}}` with `dataSourceRef` pointing at `ReplicationDestination/${APP}-bootstrap` on `democratic-csi-local-hostpath` (components/volsync/pvc.yaml)
- [component] Per-app bootstrap ReplicationDestination — name `${APP}-bootstrap`, label `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` (Flux applies once), trigger `manual: restore-once`, `enableFileDeletion: true`, `cleanupCachePVC + cleanupTempPVC: true`, `sourceIdentity.sourceName: ${APP}` (components/volsync/replicationdestination.yaml)
- [component] Just recipes — `snapshot`, `snapshot-all`, `restore`, `list-snapshots`, `kopia-maintenance`, `last-snapshots`, `state suspend|resume` (kubernetes/volsync/mod.just)
- [component] alertmanager alerts component — pulled in via `kubernetes/apps/volsync-system/kustomization.yaml` (Flux type:alertmanager Provider → in-cluster Alertmanager for reconciliation alerts)

## Claims (verified against repo)

- [claim] "VolSync runs the `perfectra1n/volsync` fork across all mover variants (kopia/restic/rclone/rsync/rsync-tls/syncthing), with `fullnameOverride: volsync` to keep upstream resource names" (evidence: repo, ref: kubernetes/apps/volsync-system/volsync/app/helmrelease.yaml:13-22, verified: 2026-05-19)
- [claim] "The VolSync platform is split into three sub-Kustomizations under `kubernetes/apps/volsync-system/kustomization.yaml`: `volsync` (operator, depends on snapshot-controller), `kopia` (browser UI, depends on onepassword-connect + volsync), and `volsync-maintenance` (depends on onepassword-connect + volsync)" (evidence: repo, ref: kubernetes/apps/volsync-system/kustomization.yaml + volsync/ks.yaml + kopia/ks.yaml, verified: 2026-05-19)
- [claim] "A cluster-wide `MutatingAdmissionPolicy/volsync-mover-jitter` injects a busybox initContainer running `sleep \$(shuf -i 0-300 -n 1)` into every `batch/v1` Job whose name starts with `volsync-src-` and label `app.kubernetes.io/created-by == volsync`. `failurePolicy: Fail`, `reinvocationPolicy: IfNeeded`" (evidence: repo, ref: kubernetes/apps/volsync-system/volsync/app/mutatingadmissionpolicy.yaml, verified: 2026-05-19)
- [claim] "The cluster has exactly two VolSync PrometheusRule alerts: `VolSyncComponentAbsent` (job=volsync-metrics absent for 15m) and `VolSyncVolumeOutOfSync` (`volsync_volume_out_of_sync == 1` for 15m); both critical" (evidence: repo, ref: kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml, verified: 2026-05-19)
- [claim] "Kopia repository server runs as the browser UI only — `enableActions: false` in `repository.config`, `--without-password` for the web UI, read-only root filesystem, drops all caps, runs as UID/GID 2000. Exposed via Gateway API on a `${PUBLIC_DOMAIN}`-prefixed hostname from both `envoy-external` and `envoy-internal` parents" (evidence: repo, ref: kubernetes/apps/volsync-system/kopia/app/helmrelease.yaml:13-97 + externalsecret.yaml:28-33, verified: 2026-05-19)
- [claim] "KopiaMaintenance `kopia-daily-maintenance` runs daily at `0 12 * * *` against repository alias `volsync-secret` (the maintenance ExternalSecret target name)" (evidence: repo, ref: kubernetes/apps/volsync-system/volsync/maintenance/kopiamaintenance.yaml + externalsecret.yaml, verified: 2026-05-19)
- [claim] "Per-app wiring is the Kustomize `Component` at `kubernetes/components/volsync/` — four resources rendered from `${APP}`/`${VOLSYNC_*}` substitution variables: `${APP}-volsync` ExternalSecret, PVC `${VOLSYNC_CLAIM:=${APP}}`, ReplicationSource `${APP}`, ReplicationDestination `${APP}-bootstrap`" (evidence: repo, ref: kubernetes/components/volsync/kustomization.yaml + the four resource files, verified: 2026-05-19)
- [claim] "Per-app ExternalSecret pulls from two 1Password items: `volsync-template` (KOPIA_S3_BUCKET, KOPIA_PASSWORD) and `ovh` (ovh_s3_access_key/secret_key/endpoint), emitting Secret `${APP}-volsync-secret` with KOPIA_REPOSITORY=`s3://{KOPIA_S3_BUCKET}` plus the AWS creds; refresh 12h" (evidence: repo, ref: kubernetes/components/volsync/externalsecret.yaml, verified: 2026-05-19)
- [claim] "Per-app ReplicationSource defaults: schedule `0 * * * *` (hourly), Kopia mover `copyMethod: Snapshot`, `compression: zstd-fastest`, `parallelism: 2`, cacheCapacity 1Gi on `democratic-csi-local-hostpath`, retain hourly=24 daily=7 weekly=2 monthly=1" (evidence: repo, ref: kubernetes/components/volsync/replicationsource.yaml, verified: 2026-05-19)
- [claim] "Per-app bootstrap ReplicationDestination is rendered with `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` and `spec.trigger.manual: restore-once` — Flux applies it ONCE at first reconcile and never overwrites; `enableFileDeletion: true`, `cleanupCachePVC + cleanupTempPVC: true`" (evidence: repo, ref: kubernetes/components/volsync/replicationdestination.yaml, verified: 2026-05-19)
- [claim] "Mover security context for both source and destination defaults to `runAsUser/Group/fsGroup = ${APP_UID:=10001}/${APP_GID:=10001}`; apps that need a different uid/gid override via substitution" (evidence: repo, ref: kubernetes/components/volsync/replicationsource.yaml:24-27 + replicationdestination.yaml:31-34, verified: 2026-05-19)
- [claim] "App PVC bootstrap-from-snapshot uses `spec.dataSourceRef` pointing at the matching bootstrap ReplicationDestination — first reconcile populates the PVC from the latest Kopia snapshot in the per-app repo identity" (evidence: repo, ref: kubernetes/components/volsync/pvc.yaml:10-13, verified: 2026-05-19)
- [claim] "Cluster restore flow: `just volsync restore <rsrc> [previous=0] [ns=default]` suspends the app Kustomization + HelmRelease, scales workloads to zero, waits for Pod deletion, runs a privileged `wipe` Job that `find /data -mindepth 1 -delete`, then creates a Direct-method ReplicationDestination `<rsrc>-manual` with timestamped manual trigger, waits for the mover Job, deletes the RD, and resumes Flux" (evidence: repo, ref: kubernetes/volsync/mod.just:25-86, verified: 2026-05-19)
- [claim] "List-snapshots recipe shells into the kopia Deployment and runs `kopia snapshot list <rsrc>@<ns>:/data --all --manifest-id --json`, then renders a human-readable table via jq" (evidence: repo, ref: kubernetes/volsync/mod.just:88-118, verified: 2026-05-19)
- [claim] "`just volsync kopia-maintenance` patches the `kopia-daily-maintenance` KopiaMaintenance with a `manual` trigger value, then polls `.status.lastManualSync` until it matches the trigger value before printing the CR yaml — synchronous wait for completion" (evidence: repo, ref: kubernetes/volsync/mod.just:120-133, verified: 2026-05-19)
- [claim] "`just volsync last-snapshots [date]` is a Python report that filters `replicationsources -A` by `status.lastSyncTime` falling in the given local-Budapest day, parses Kopia progress logs to estimate snapshot size, and prints a per-RS table; default date is today" (evidence: repo, ref: kubernetes/volsync/mod.just:135-225, verified: 2026-05-19)
- [claim] "`just volsync state suspend|resume` suspends/resumes both the operator Kustomization and HelmRelease and scales the volsync Deployment between 0 and 1 — pauses backup activity cluster-wide" (evidence: repo, ref: kubernetes/volsync/mod.just:227-233, verified: 2026-05-19)

## Drift Risk

- [drift] The VolSync operator and movers come from the **perfectra1n fork** (`ghcr.io/perfectra1n/volsync`), not upstream — versions and CVE coverage track that fork, not the upstream repo. `fullnameOverride: volsync` is what keeps the chart's resource names compatible. If the fork is abandoned, migrating to upstream requires re-validating manifests.
- [drift] The Kopia repository's S3 path and password come from 1Password item `volsync-template` — only the `KOPIA_S3_BUCKET` and `KOPIA_PASSWORD` fields are referenced. If that item is renamed, ALL apps lose their backups in one shot until the ExternalSecret picks up a fresh extract.
- [drift] Per-app contract is `${APP}` / `${APP}-bootstrap` / `${APP}-volsync-secret` — `just volsync` recipes hardcode this naming. Apps that diverge from `${APP} = HelmRelease name = PVC name` (or override `VOLSYNC_CLAIM`) will silently break the restore recipe in particular.
- [drift] Bootstrap RDs carry `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` so Flux never re-templates them after the first apply. Fresh fetches from Kopia (e.g. after schema/uid changes) require deleting BOTH the PVC AND the bootstrap RD — the platform CLAUDE.md flags this explicitly; without that knowledge the bootstrap path looks broken.
- [drift] The MutatingAdmissionPolicy jitter range is hardcoded at 0-300s via `shuf -i 0-300 -n 1`. If schedules become non-hourly (default), the jitter range must be reasoned about together with the schedule cadence; the platform CLAUDE.md flags this.
- [drift] Both maintenance and per-app ExternalSecrets reference the **same** 1P `volsync-template` item — a credential rotation here is global; there is no per-app key separation. Same for the OVH credentials reused across every app's secret.
- [drift] Kopia browser UI is exposed publicly (via `envoy-external`) on a `${PUBLIC_DOMAIN}`-prefixed hostname — protected by Cloudflare Access (per the cloudflare area note's `Private Cloud` app with `*.<domain>`) but the Kopia binary itself does not authenticate (`--without-password`).

## Open Questions / Gaps

- [gap] No verification was run against the live cluster in this pass — claims are repo-evidence only. `.claude/skills/volsync/references/validation.md` is the live-state validation path.
- [gap] The exact list of apps wired into the component (which app `ks.yaml` files declare the `postBuild.substitute` block for volsync) was not enumerated here — that is a contract sweep best done as part of the k8s-workloads area-reference.
- [gap] The Kopia browser UI's authentication delegation to Cloudflare Access vs. its own `--without-password` config is a security-relevant cross-cutting claim; final exposure model belongs in security-review.
- [gap] No formal restore-time SLO is captured (data ingress from OVH `DE` region, sequential mover Jobs, single-node cluster). The restore recipe sets a 120m timeout on the mover Job as the only documented upper bound.

## Relations

- depends_on [[external-secrets]]
- depends_on [[ovh-storage]]
- relates_to [[k8s-workloads]]
- relates_to [[flux-gitops]]
- part_of [[home-ops-platform]]
