# Operations

Use this reference for status, snapshot, maintenance, and restore workflows.

## Recipe Entry Points

`kubernetes/volsync/mod.just` is the live source for the `just volsync` recipes. Prefer those recipes over ad-hoc kubectl sequences when feasible. Use the Kopia-backed `just volsync` recipes for PVC snapshots and restores. Do not redirect those flows through Backrest, which belongs to the separate `resticprofile` file-level backup plane.

The available recipes group into:

- inspection: `list-snapshots`, `rs-status`, `last-backups`
- snapshot triggers: `snapshot`, `snapshot-all`
- maintenance: `kopia-maintenance`
- restore: `restore` (unified wipe-and-restore from any historical Kopia snapshot)
- cluster-wide pause: `state suspend|resume`

## Naming Contract

After Phase 15.a, every PVC-backed app in this repo satisfies `app == Flux Kustomization == HelmRelease` parity. The `just volsync` recipes rely on this contract: `restore` suspends a Kustomization with the same name as the app, and the shared component derives every Kopia, RS, RD, PVC, and ExternalSecret name from the `${APP}` substitution in the app's `ks.yaml`. Do not reintroduce KS / HR divergence without also revisiting these recipes.

## Fresh-Cluster Bootstrap (no recipe needed)

`kubernetes/components/volsync/` keeps an always-on `ReplicationDestination` named `${APP}-bootstrap` and the app PVC has `dataSourceRef` pointing at it. On a fresh cluster Flux applies the manifests, the RD writes a VolumeSnapshot from the latest Kopia snapshot, and the PVC populates from it. Each restore emits one expected `Warning ClaimMisbound` event on a transient `vs-prime-<uuid>` PVC — this is the SIG-storage volume-populator staging PVC and is not a failure.

The Kopia repository identity is derived purely from `${APP}` (`${APP}-volsync-secret`, `sourceIdentity.sourceName: ${APP}`). A KS rename that preserves `${APP}` does not change the OVH binding.

## Unified Restore Flow (`just volsync restore`)

`just volsync restore <app> [previous=0] [ns=default]` replays a Kopia snapshot back into an existing PVC. `previous=0` is the latest snapshot, `previous=N` is the N-th historical one.

The recipe walks the workload through eight steps:

1. `flux suspend` on the Flux Kustomization and the HelmRelease for the app
2. scale the deploy/sts to 0, wait for pods to fully delete
3. apply a one-shot `<app>-wipe` Job (Alpine, root, `find /data -mindepth 1 -delete`) that mounts the PVC and removes every file under `/data`
4. wait for the wipe Job to complete, then delete it
5. apply an ad-hoc `<app>-manual` ReplicationDestination with `copyMethod: Direct`, `destinationPVC: <app>`, `previous: N`
6. wait for the VolSync mover Job (`volsync-dst-<app>-manual`) to complete
7. delete the ad-hoc RD
8. `flux resume` + force HelmRelease reconcile + wait for the app pod to become Ready

The wipe step is what makes the restore an exact replica of the snapshot. Without it, Kopia's Direct mover overwrites the files that exist in the snapshot but leaves leftover files from the live PVC — silent corruption if the live data evolved past the snapshot's file set.

Recipe failure between step 3 and step 6 leaves the PVC empty (workload stays scaled down with Flux suspended). Recovery: investigate `kubectl get job volsync-dst-<app>-manual -n <ns>` and the Kopia repository, then re-run `just volsync restore`.

If a recipe change touches resource names, labels, or workflow assumptions, inspect `kubernetes/volsync/mod.just` together with `kubernetes/components/volsync/` and the touched platform resources before editing.
