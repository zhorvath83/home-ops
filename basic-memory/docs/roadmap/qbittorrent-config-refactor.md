---
title: qbittorrent-config-refactor
type: roadmap
permalink: home-ops/docs/roadmap/qbittorrent-config-refactor
topic: qBittorrent config-handling refactor (16.d)
status: proposed
scope: 'Replace the current init container pattern (`controllers.qbittorrent.initContainers.01-copy-config`
  busybox cp + PBKDF2 append) with a cleaner approach. Trigger: the homepage config
  split (commit `2807e9d4b`) demonstrated that non-secret config + secret-key combinations
  can be handled without init containers via `configMap` + `secret` subPath mounts.'
priority: low
rationale: 'Current pain points: (1) runtime config overwrites — qBittorrent writes
  to `qBittorrent.conf` during runtime (UI tuning, plugin state), and every pod restart
  overwrites with the configMap baseline, losing UI-side changes; (2) init container
  privilege footprint; (3) two-file split between git baseline and PVC runtime state
  with no resync path. Whether these are problems worth fixing depends on the value
  of runtime UI tuning.'
options:
- '**A — ESO template assembly**: 1P `qbittorrent` item gains a `qbittorrent_conf`
  text field with the full `qBittorrent.conf` including PBKDF2; ExternalSecret `template.data`
  renders the Secret key; HR `subPath` mount places it at `/config/qBittorrent/qBittorrent.conf`.
  Init container is eliminated. Tradeoff: baseline lives in 1P, not git — editing
  UX is worse.'
- '**B — Bootstrap-only init container**: keep the `01-copy-config` init container
  but add a `[ ! -f /config/qBittorrent/qBittorrent.conf ]` guard so it only copies
  on first boot. Runtime tuning survives, but baseline updates (chart bump, new config)
  never auto-apply — manual `rm` needed.'
- '**C — Status quo + explicit documentation**: keep current behavior as a deliberate
  choice ("git = single source of truth, UI tuning ephemeral"); add a doc section
  in `.claude/skills/k8s-workloads/` or the qbittorrent CLAUDE.md explaining the tradeoff.
  No refactor, just docs.'
related_areas:
- k8s-workloads
- external-secrets
---

# qBittorrent config-handling refactor (16.d)

## Metadata (observation-form, schema validation)

- [topic] qBittorrent config-handling refactor (16.d)
- [status] proposed
- [priority] low

## Scope

Replace the current init container pattern (`controllers.qbittorrent.initContainers.01-copy-config` busybox cp + PBKDF2 append) with a cleaner approach. Trigger: the homepage config split (commit `2807e9d4b`) demonstrated that non-secret config + secret-key combinations can be handled without init containers via `configMap` + `secret` subPath mounts.

## Rationale

Current pain points: (1) runtime config overwrites — qBittorrent writes to `qBittorrent.conf` during runtime (UI tuning, plugin state), and every pod restart overwrites with the configMap baseline, losing UI-side changes; (2) init container privilege footprint; (3) two-file split between git baseline and PVC runtime state with no resync path. Whether these are problems worth fixing depends on the value of runtime UI tuning.

## Options

1. **A — ESO template assembly**: 1P `qbittorrent` item gains a `qbittorrent_conf` text field with the full `qBittorrent.conf` including PBKDF2; ExternalSecret `template.data` renders the Secret key; HR `subPath` mount places it at `/config/qBittorrent/qBittorrent.conf`. Init container is eliminated. Tradeoff: baseline lives in 1P, not git — editing UX is worse.
2. **B — Bootstrap-only init container**: keep the `01-copy-config` init container but add a `[ ! -f /config/qBittorrent/qBittorrent.conf ]` guard so it only copies on first boot. Runtime tuning survives, but baseline updates (chart bump, new config) never auto-apply — manual `rm` needed.
3. **C — Status quo + explicit documentation**: keep current behavior as a deliberate choice ("git = single source of truth, UI tuning ephemeral"); add a doc section in `.claude/skills/k8s-workloads/` or the qbittorrent CLAUDE.md explaining the tradeoff. No refactor, just docs.

## Related

- relates_to [[k8s-workloads]]
- relates_to [[external-secrets]]
