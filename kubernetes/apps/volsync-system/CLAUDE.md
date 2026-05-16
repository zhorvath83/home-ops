# VolSync Platform Guide

This guide applies to `kubernetes/apps/volsync-system/`.

## What Is Special Here

This subtree defines the backup platform itself, not ordinary application workloads.

Current live layers:

- `kopia/`: the Kopia service and supporting secret wiring
- `volsync/`: the VolSync operator and cluster-wide policy resources
- `volsync/maintenance/`: Kopia maintenance resources

## Guardrails

- Treat schedule, retention, and jitter behavior here as cluster-wide policy, not app-local tuning.
- Inspect this subtree together with `kubernetes/components/volsync/` before changing backup behavior.
- VolSync and Kopia in this subtree protect cluster PVCs. They are not the browse or restore surface for the separate `resticprofile` plus Backrest file-level backup plane.
- Do not add per-app assumptions here unless the platform is intentionally being changed for the whole fleet.
- Preserve resource names and secret wiring that the `just volsync` recipes depend on (`<app>`, `<app>-bootstrap`, `<app>-volsync-secret`) unless the task explicitly changes those workflows.
- The component is **always-on**: every app PVC populates from a `<app>-bootstrap` ReplicationDestination via `dataSourceRef`. Fresh fetches from Kopia require deleting both the PVC **and** the bootstrap RD (the `IfNotPresent` SSA label freezes the RD after the first `restore-once` trigger).
- If you change the jitter policy, reason about app-level schedules and restore timing together, not in isolation.

## Validation

See `.claude/skills/volsync/references/validation.md` for the validation procedure.
