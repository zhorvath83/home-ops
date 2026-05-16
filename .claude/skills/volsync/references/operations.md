# Operations

Use this reference for status, snapshot, maintenance, and restore workflows.

## Recipe Entry Points

`kubernetes/volsync/mod.just` is the live source for the `just volsync` recipes. Prefer those recipes over ad-hoc kubectl sequences when feasible. Use the Kopia-backed `just volsync` recipes for PVC snapshots and restores. Do not redirect those flows through Backrest, which belongs to the separate `resticprofile` file-level backup plane.

The available recipes group into:

- inspection: `list-snapshots`, `rs-status`, `last-backups`
- snapshot triggers: `snapshot`, `snapshot-all`
- maintenance: `kopia-maintenance`
- restore: `restore` (always-on bootstrap restore), `restore-into` (point-in-time, in-place)
- cluster-wide pause: `state suspend|resume`

## Naming Contract

After Phase 15.a, every PVC-backed app in this repo satisfies `app == Flux Kustomization == HelmRelease` parity. The `just volsync` recipes rely on this contract: `restore-into` suspends a Kustomization with the same name as the app, and the shared component derives every Kopia, RS, RD, PVC, and ExternalSecret name from the `${APP}` substitution in the app's `ks.yaml`. Do not reintroduce KS / HR divergence without also revisiting these recipes.

## Always-On Bootstrap Restore

`kubernetes/components/volsync/` keeps an always-on `ReplicationDestination` named `${APP}-bootstrap` and the app PVC has `dataSourceRef` pointing at it. Effects to know:

- Every new PVC populates from `${APP}-bootstrap` on first creation. Each restore emits one expected `Warning ClaimMisbound` event on a transient `vs-prime-<uuid>` PVC — this is the SIG-storage volume-populator staging PVC and is not a failure.
- The RD is applied with `IfNotPresent` SSA semantics, so a single `restore-once` manual trigger leaves the RD pinned to that VolumeSnapshot. To force a fresh Kopia fetch you must delete **both** the PVC and the `${APP}-bootstrap` RD before letting Flux recreate them; otherwise the new PVC populates from the cached `status.latestImage` instead of OVH.

The Kopia repository identity is derived purely from `${APP}` (`${APP}-volsync-secret`, `sourceIdentity.sourceName: ${APP}`). A KS rename that preserves `${APP}` does not change the OVH binding.

## Restore Recipes — Pick The Right One

- `just volsync restore <app> [ns=default]` — patches the always-on `${app}-bootstrap` RD with a `manual: restore-once` trigger and waits for it to synchronize. Use this for fresh-cluster bootstrap restores driven by the always-on RD.
- `just volsync restore-into <ns> <app> [previous=0]` — provisions an ad-hoc `<app>-manual` RD with `copyMethod: Direct` writing into the existing PVC, suspends and scales down the workload, waits for the mover job, then resumes and reconciles the HelmRelease. Use this for point-in-time rollback into an already-deployed app. Relies on the `app == KS == HR` naming contract above.

If a recipe change touches resource names, labels, or workflow assumptions, inspect `kubernetes/volsync/mod.just` together with `kubernetes/components/volsync/` and the touched platform resources before editing.
