# Selfhosted Apps Guide

This guide applies to `kubernetes/apps/selfhosted/` and `kubernetes/apps/media/` (the latter via symlink). It captures durable guardrails for user-facing application workloads; for current-state detail (app inventory by Homepage group, cross-cutting patterns, exposure model, storage strategy, claims, drift risk) read the Basic Memory area-reference `docs/areas/k8s-workloads` via the `basic-memory` MCP.

## Scope

User-facing application workloads — one app per directory with a `ks.yaml` entry point and main manifests under `app/`. Optional sibling directories such as `backup/` for scheduled jobs are acceptable when the repo already uses that pattern. A mix of app-template Helm releases and upstream charts is normal.

## Guardrails

- Inspect 2-3 sibling apps with similar exposure, storage, and auth before changing structure.
- Chart preference order: official chart → bjw-s `app-template` → custom manifests only when needed.
- Routes for published apps target `envoy-external` in namespace `networking`; add `envoy-internal` as a second parent when the app should also be reachable directly from the LAN. Technical endpoints can stay `envoy-external`-only.
- Dashboard apps carry Homepage annotations; match group and icon conventions of nearby siblings.
- App-managed secrets come from an `ExternalSecret` backed by the `onepassword-connect` ClusterSecretStore (see the canonical pattern in `kubernetes/apps/external-secrets/CLAUDE.md`).
- Backed-up apps use the shared VolSync component via `ks.yaml`, not app-local backup manifests.
- VolSync is not the only backup layer for every app. Critical workloads may also write a curated export into the shared `/backups/<app>` NFS tree so `resticprofile` captures a second copy in OVH Object Storage; Paperless is the canonical dual-coverage pattern. Preserve those export jobs and NFS mounts when they already exist.
- For storage, compare against sibling apps first — several media-oriented apps combine PVC, NFS, and `emptyDir` mounts.

## Resource Baseline

- Set explicit `resources.requests.cpu`, `resources.requests.memory`, and `resources.limits.memory`.
- Do not add CPU limits by default; use them only when a specific app needs throttling protection.
- Size requests from live usage or close sibling apps instead of copying large generic values.

## Validation

See `.claude/skills/k8s-workloads/references/validation.md`.
