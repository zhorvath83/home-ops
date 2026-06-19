# System Upgrade Guide

This guide applies to `kubernetes/apps/system-upgrade/`. It captures durable guardrails for in-place node upgrades driven by `tuppr`. There is no dedicated Basic Memory area-reference; background and history live in BM decision `docs/decisions/AD-019-tuppr-system-upgrade` and progress note `docs/progress/tuppr-upgrade-automation`.

## Scope

`tuppr` performs Talos and Kubernetes version upgrades on the cluster — it is platform automation, not an app workload:

- `tuppr/app/` — the tuppr controller HelmRelease
- `tuppr/upgrades/` — the declarative `TalosUpgrade` and `KubernetesUpgrade` CRs that pin the target versions

## Single-Node Blast Radius (Read Before Touching)

This is a single control-plane node cluster. An upgrade here is **a full cluster outage**, not a rolling update:

- `TalosUpgrade` runs with `drain.enabled: false` (there is nowhere to drain to) and `rebootMode: powercycle` — applying it **reboots the only node**.
- Treat any change under `tuppr/upgrades/` as a scheduled-maintenance action, not a routine commit. Do not bump `TalosUpgrade`/`KubernetesUpgrade` versions casually.

## Guardrails For Edits Here

- The target versions are **Renovate-tracked** — preserve the inline annotations: `TalosUpgrade.spec.talos.version` (`datasource=custom.talos-factory depName=siderolabs/talos`) and `KubernetesUpgrade.spec.kubernetes.version` (`datasource=docker depName=ghcr.io/siderolabs/kubelet`).
- Both upgrade CRs gate on a health check that requires **all VolSync `ReplicationSource` objects to be idle** (not `Synchronizing`) — do not weaken or remove it; it prevents rebooting mid-backup.
- The `tuppr-upgrades` Kustomization `dependsOn` `tuppr` and uses `wait: false`; keep that ordering.
- Talos image/schematic and version flows are coordinated with `kubernetes/talos/` and the `just talos` recipes — cross-check `docs/areas/talos-cluster` in BM before changing version sourcing.

## Validation

- A version bump cannot be meaningfully validated by reconcile alone — it executes a real node reboot. Confirm the change is intentional, the target version exists in the Talos Factory / kubelet datasource, and a maintenance window is acceptable before committing.
