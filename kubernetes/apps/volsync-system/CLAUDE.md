# VolSync Platform Guide

This guide applies to `kubernetes/apps/volsync-system/`. It captures durable guardrails for the PVC backup platform; for current-state detail (operator fork, jitter policy, KopiaMaintenance, alerts, claims, drift risk) read the Basic Memory area-reference `docs/areas/volsync-backup` via the `basic-memory` MCP.

## Scope

This subtree defines the backup platform itself, not ordinary application workloads. Layers:

- `volsync/` — the operator + cluster-wide policy resources
- `volsync/maintenance/` — `KopiaMaintenance` CR
- `kopia/` — the Kopia repository-server browser UI

VolSync + Kopia here protects cluster PVCs. It is **not** the browse or restore surface for the separate `resticprofile` + Backrest file-level backup plane.

## Guardrails

- Schedule, retention, and jitter behavior here are cluster-wide policy — do not tune as if they were app-local.
- Inspect this subtree together with `kubernetes/components/volsync/` before changing backup behavior.
- Preserve the per-app contract `<app>` / `<app>-bootstrap` / `<app>-volsync-secret` — the `just volsync` recipes and app-level Flux Kustomizations both depend on these names.
- The shared component is **always-on**: every app PVC populates from a `<app>-bootstrap` ReplicationDestination via `dataSourceRef`. Fresh fetches from Kopia require deleting **both** the PVC AND the bootstrap RD (the `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` label freezes the RD after first apply).
- If jitter policy changes, reason about app-level schedules and restore timing together, not in isolation.
- Do not add per-app assumptions here unless the platform is intentionally being changed for the whole fleet.

## Validation

See `.claude/skills/volsync/references/validation.md`.
