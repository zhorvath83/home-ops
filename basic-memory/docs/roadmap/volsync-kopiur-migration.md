---
title: volsync-kopiur-migration
type: roadmap
permalink: home-ops/docs/roadmap/volsync-kopiur-migration
topic: VolSync (perfectra1n fork) → kopiur migration — adopt the existing Kopia repository
  in place on a maintained Kopia-native operator
status: proposed
priority: medium
scope: Replace the abandoned perfectra1n VolSync fork with kopiur (home-operations/kopiur)
  as the PVC backup operator. kopiur adopts the existing Kopia repository on OVH S3
  in place (snapshots preserved), so the migration is per-app cut-over via `kubectl
  kopiur migrate volsync`, plus a rewrite of the per-app Kustomize component and retirement
  of the fork install + jitter MutatingAdmissionPolicy. Gated on kopiur leaving alpha
  (v1alpha1, CRD surface still shifting).
rationale: The perfectra1n fork is abandoned; its developer now maintains kopiur.
  Because home-ops uses the fork Kopia mover, kopiur can adopt the same Kopia repository
  in place — preserving all snapshot history — so the migration cost is operator-swap,
  not data-migration. A maintained Kopia-native operator with chart-native observability
  and a dedicated VolSync migration CLI is a strict improvement over a dead fork,
  provided kopiur matures past alpha before a production backup system depends on
  it.
options:
- Wait-and-migrate — track kopiur to beta/stable, then one coordinated migration (recommended;
  fits production-backup criticality vs alpha maturity)
- Parallel-run pilot — deploy kopiur alongside the fork now for one low-criticality
  app, validate in-place Kopia adoption, expand per-app as it stabilizes
- 'Fork-replace now — migrate everything immediately (rejected: alpha CRD surface
  on a data-loss-critical system)'
related_areas:
- volsync-backup
- observability
- external-secrets
---

# VolSync (perfectra1n fork) → kopiur migration

## Metadata (observation-form, schema validation)

- [topic] VolSync (perfectra1n fork) → kopiur migration
- [status] proposed
- [priority] medium
- [gating] kopiur is **alpha** (API group `kopiur.home-operations.com` **v1alpha1**, "heavy construction", CRD surface may change between releases) — a production backup system should not migrate onto an alpha operator yet. This roadmap tracks the migration; execution gates on kopiur reaching a stable-enough maturity.

## Context

The current PVC backup plane runs on **VolSync + Kopia** using the **perfectra1n fork** image (`ghcr.io/perfectra1n/volsync`). That fork is effectively abandoned: its developer now builds **kopiur** ([home-operations/kopiur](https://github.com/home-operations/kopiur)) — a Rust-based, Kopia-native Kubernetes backup operator that treats a Kopia repository as a first-class Kubernetes resource. kopiur ships an OCI Helm chart, a kubectl plugin, and crucially a **`kubectl kopiur migrate volsync`** command with a documented cut-over path.

The decisive compatibility fact: because home-ops uses the fork's **Kopia mover**, kopiur **adopts the existing Kopia repository in place** — all snapshots are preserved and history continues. Snapshot-history risk on migration is therefore low; the risk is operator maturity, not data continuity.

## What we gain

- **Maintained operator** replacing an abandoned fork — security updates, bug fixes, and a responsive upstream instead of a dead fork.
- **Kopia-native CRD model** with a clean separation of recipe (`BackupConfig`), invocation (`Backup`), schedule (`BackupSchedule`), and restore (`Restore`) — invalid states are unrepresentable (Rust enums), reconcilers handle every variant at compile time.
- **Built-in observability**: the chart exposes `serviceMonitor`, `prometheusRule`, and grafana-operator `dashboards` natively (see onedr0p/bjw-s reference HelmRelease) — replaces the hand-rolled VolSync PrometheusRules + GrafanaDashboard/Folder.
- **First-class scheduling** with jitter and timezone in `BackupSchedule` — subsumes the cluster-wide `volsync-mover-jitter` MutatingAdmissionPolicy hack.
- **kubectl plugin** (krew/Homebrew) for trigger/inspect/restore/browse/maintenance — improves day-2 ops over the current `just volsync`-only flow.
- **Cosign-signed, digest-pinned OCI release artifacts** with SBOMs — stronger supply-chain posture than the fork image.

## What to do (high level)

1. Track kopiur to a maturity point where the v1alpha1 CRD surface has stabilized enough for a production backup system (no fixed version yet — this is the gate).
2. Stand up a parallel `kopiur-system` platform (`kubernetes/apps/kopiur-system/`: namespace, OCIRepository, HelmRelease, ClusterRepository/Repository pointing at the existing OVH S3 backend + 1Password repository secret).
3. Rewrite the per-app Kustomize component (`kubernetes/components/volsync/`) as a kopiur component (`BackupConfig` + `BackupSchedule` + bootstrap `Restore`).
4. Per-app cut-over via `kubectl kopiur migrate volsync` (offline GitOps mode `-f` for review, then `--apply`), verifying snapshot identity continuity.
5. Retire the fork: delete `KopiaMaintenance` + the VolSync install and the jitter MutatingAdmissionPolicy — **not** the repository Secret. Update the `volsync-backup` area-reference (or replace it with a `kopiur-backup` area).

## Options

1. **Wait-and-migrate (recommended)** — track kopiur to beta/stable, then one coordinated migration. Fits production-backup criticality vs alpha maturity; the fork keeps working in the meantime.
2. **Parallel-run pilot** — deploy kopiur alongside the fork now for one low-criticality app, validate the in-place Kopia adoption end-to-end, then expand per-app as kopiur stabilizes. Front-loads learning but exposes a production workload to an alpha operator early.
3. **Fork-replace now** — migrate everything onto kopiur immediately. Rejected: alpha CRD surface still shifting on a system where data loss is unacceptable.

## Related

- relates_to [[volsync-backup]] — the area being replaced; its area-reference is the current-state source of truth
- relates_to [[observability]] — VolSync PrometheusRules + GrafanaDashboard/Folder map onto kopiur chart-native ServiceMonitor/PrometheusRule/grafana dashboards
- relates_to [[external-secrets]] — the Kopia repository password + S3 credentials move from the fork Secret to a kopiur Repository/ClusterRepository `secretRef` backed by the shared onepassword-connect ClusterSecretStore

## Execution plan (research-backed)

### Current state
- PVC backups via VolSync + Kopia mover, perfectra1n fork image `ghcr.io/perfectra1n/volsync` (`kubernetes/apps/volsync-system/volsync/app/helmrelease.yaml`, `fullnameOverride: volsync` to keep upstream resource names).
- Platform under `kubernetes/apps/volsync-system/`: operator + `snapshot-controller` dep, Kopia repository-server browser UI, `KopiaMaintenance` CR + ExternalSecret, cluster-wide **MutatingAdmissionPolicy `volsync-mover-jitter`** injecting a 0–300s busybox initContainer into every `volsync-src-*` Job, `PrometheusRules` (`VolSyncComponentAbsent`, `VolSyncVolumeOutOfSync`), GrafanaDashboard/Folder, tokenless maintenance ServiceAccount. Backend: OVH Object Storage (S3) via 1Password Connect.
- Per-app wiring: Kustomize **component** `kubernetes/components/volsync/` (parameterized by `${APP}`, `${VOLSYNC_*}`, `${APP_UID/APP_GID}`) → ExternalSecret, PVC bootstrap from a ReplicationDestination, hourly ReplicationSource, idle bootstrap RD with IfNotPresent SSA.
- Fork is abandoned; upstream dev moved to kopiur.

### Target state
- kopiur operator in `kopiur-system` adopting the **same** Kopia repository on OVH S3 — existing snapshots preserved, history continues.
- Per-app backups expressed as kopiur `BackupConfig` + `BackupSchedule` (jitter/timezone native) + bootstrap `Restore`; the jitter MutatingAdmissionPolicy retired.
- Observability via chart-native ServiceMonitor + PrometheusRule + grafana-operator dashboard.
- VolSync install, fork image, and `KopiaMaintenance` removed; the repository Secret retained.

### kopiur specifics (from upstream docs + reference repos)
- **Chart**: `oci://ghcr.io/home-operations/charts/kopiur` (cosign-signed, digest-pinned, OCIRepository; reference uses tag `0.9.2`). Webhook cert self-managed → **no cert-manager** required; k8s ≥ 1.24. License AGPL-3.0.
- **CRDs (v1alpha1)**: `Repository` (namespaced), `ClusterRepository` (cluster, gated by allowedNamespaces), `BackupConfig`, `Backup`, `BackupSchedule`, `Restore` (PVC restore + volume-populator source), `Maintenance` (quick/full maintenance with ownership lease).
- **Migration command**: `kubectl kopiur migrate volsync -n <ns> --resolve-secrets --apply`. Offline/GitOps mode: `-f` (no kubeconfig), `--out-dir` writes one file per ReplicationSource + a `_shared.yaml`; `--apply` is rejected offline (review then `kubectl apply`). Accounting on stderr: every read field reported as `mapped` / `UNMAPPABLE` / `ignored` — nothing silently dropped.
- **Kopia-fork sources (our case)**: repo adopted in place, **no `create` block** to prevent fresh init; identity pinned to `<sanitized-name>@<sanitized-namespace>:/data` so snapshots list under the same identity; secrets referenced in place, never copied; retention maps 1:1 (`retain.latest`→`keepLatest`, `retain.yearly`→`keepAnnual`).
- **Unmappable fork fields** (need manual handling): `actions.beforeSnapshot`/`afterSnapshot` (different pod context), `policyConfig` (replaced by typed fields), `shallow` restore windows (use `asOf`/`offset`/`snapshotID`).
- **Reference layouts**: onedr0p/home-ops and bjw-s-labs/home-ops — `kopiur-system` namespace, split Flux Kustomizations (`kopiur` app + `kopiur-repository`, the latter dependsOn the former), ClusterRepository with S3 backend + `scheduleDefaults.timezone`; eleboucher/homelab — kopiur-system with a gdrive-sync use-case alongside.

### Suggested cut-over (per upstream guide)
1. Suspend/delete the fork's `ReplicationSource`; **keep its Secret**.
2. Dry-run the migration and review the accounting — especially the pinned `spec.identity` line.
3. Re-run with `--apply`; wait for `Ready` and the old snapshots to appear under the adopted repo.
4. Prove continuity: take a new snapshot and confirm it lists under the same identity.
5. Delete fork `KopiaMaintenance` objects and the VolSync install — **not the repository Secret**.

### Open questions (to resolve before accepting)
- [needs-research] Does kopiur still require `snapshot-controller`, or does `Restore` as volume-populator remove that dependency? (Affects what stays under the platform.)
- [needs-research] Does kopiur have an equivalent to the Kopia repository-server **browser UI**, or does the `kubectl kopiur browse` plugin replace it? Decide whether the separate kopia browser deployment is retired.
- [needs-research] Repository scoping decision: namespaced `Repository` per app vs a single `ClusterRepository` with `allowedNamespaces` (the onedr0p reference uses ClusterRepository with `all: true`). Matches the current single-shared-repository model.
- [needs-decision] Acceptance gate: which kopiur version/maturity level is "stable enough" for this production backup plane — and does this roadmap wait for it (Option 1) or pilot first (Option 2)?

### Verification
- After adoption: new kopiur `Backup` completes `Ready` and the snapshot lists under the pre-migration identity (continuity proof).
- A test `Restore` populates a PVC from a pre-migration snapshot.
- Chart-native ServiceMonitor scraped by Prometheus; `VolSync*`-equivalent alerts fire under kopiur labels; grafana dashboard renders.
- `just volsync list-snapshots`-equivalent flow reproduced via `kubectl kopiur` before the fork recipes are removed.

### Rollback & safety
- Pre-cut-over: kopiur runs alongside the fork (read-only adoption — no `create` block), so the fork remains the active writer until cut-over. Rollback = stop using kopiur, resume the fork's `ReplicationSource`; the Kopia repository is shared and unchanged.
- The migration is per-app and reversible up to the point the fork install is deleted. Keep the fork install alive across at least one full backup+restore cycle on kopiur before removing it.
- **Do not** delete the repository Secret at any point — both the fork and kopiur reference it.

### Gotchas & dependencies
- kopiur is alpha: pin a specific chart tag (OCIRepository `ref.tag`) and a digest-pinned image; expect breaking CRD changes between releases — budget for migration steps on upgrade.
- The jitter MutatingAdmissionPolicy targets `volsync-src-*` Jobs by name prefix — it will not match kopiur jobs and must be retired (jitter is now native in `BackupSchedule`).
- The per-app component is heavily parameterized by Flux `postBuild.substitute` variables; the kopiur rewrite must preserve the same parameter surface so app kustomizations keep working unchanged.
- AGPL-3.0 license — note for any future bundling/redistribution, irrelevant for in-cluster use.

### Effort
L (~1–2 days of focused work once kopiur is deemed stable enough): platform setup + ClusterRepository/Secret wiring, per-app component rewrite, one pilot app cut-over + restore drill, then per-app rollout. Effort is dominated by the per-app component rewrite and the per-app cut-over verification, not by the platform install.
