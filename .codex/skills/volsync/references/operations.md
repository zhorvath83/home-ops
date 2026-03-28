# Operations

Use this reference for status, snapshot, maintenance, and restore workflows.

## Task Entry Points

The repo already provides `vs:` task wrappers for:

- listing snapshots
- triggering manual snapshots
- restore workflows
- maintenance runs
- status inspection

Prefer those workflows over ad-hoc kubectl sequences when feasible.
Use Kopia-backed `vs:` workflows for PVC snapshots and restores. Do not redirect those tasks through Backrest, which belongs to the separate `resticprofile` file-level backup plane.

## Restore Model

The restore flow is deliberately stateful and should be treated carefully:

1. suspend the Flux Kustomization and HelmRelease for the app
2. scale the controller down
3. wipe the destination PVC
4. create the restore destination and wait for completion
5. resume Flux and scale the workload back up

If a restore task changes resource names, labels, or assumptions, inspect `.taskfiles/VolSync/Tasks.yaml` together with the platform resources before editing.
