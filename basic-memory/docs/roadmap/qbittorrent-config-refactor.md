---
title: qbittorrent-config-refactor
type: note
permalink: home-ops/docs/roadmap/qbittorrent-config-refactor
topic: qBittorrent API-driven config provisioning
status: in-progress
scope: Replace init-container ConfigMap copy + PBKDF2 append with API-driven provisioning.
  Config files removed from git, categories and watched folders set via API, p2pblocklist
  converted from CronJob to initContainer.
priority: medium
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

# qBittorrent config provisioning refactor

## Status: in-progress

First round: API-driven provisioning with bypass_local_auth. No password management yet (second round).

## Architecture

### Init container: qbt-init.sh

Runs before the main container. Uses the qBittorrent image (bash, curl, gunzip included).

1. **Config overwrite**: Always copies `/defaults/qBittorrent.conf` to `/config/qBittorrent/qBittorrent.conf`. This ensures a clean baseline on every pod start — the postStart hook then applies all non-default settings via API.
2. **Ipfilter download**: Downloads ipfilter.dat from GitHub. Non-fatal on failure (qBittorrent starts without IP filtering).

### postStart hook: qbt-poststart.sh

Generic executor that reads `qbt-config.json` and calls each API endpoint. No qBittorrent-specific knowledge in the script.

1. Polls `/api/v2/app/version` up to 120s (60 x 2s)
2. Iterates `qbt-config.json` entries, each with `endpoint` + `method` + `payload`
3. `method: "json"` sends payload as `json=<compact JSON>` form parameter (setPreferences convention)
4. `method: "form"` sends each payload key-value as separate `--data-urlencode` form field (createCategory convention)
5. HTTP status check: 2xx and 409 (Conflict = idempotent success) accepted, all others exit 1
6. `Referer: http://127.0.0.1:8080` header on all calls (CSRF protection)

### ConfigMap: qbittorrent-scripts

Contains three files mounted at `/scripts/`:
- `qbt-init.sh` — init container script
- `qbt-poststart.sh` — postStart hook script
- `qbt-config.json` — declarative API call definitions

### Authentication

First round uses `bypass_local_auth: true` set via the setPreferences API call. The default config from the image has `AuthSubnetWhitelistEnabled=true` with RFC1918 ranges, so LAN access also bypasses auth. No password management in this round — the ExternalSecret remains but is unused. Second round will add `web_ui_password` via the ExternalSecret.

## Config values

Preferences set via API are in `qbt-config.json`. Key decisions:

| Setting | Decision | Rationale |
|---|---|---|
| start_paused_enabled | false | Session value authoritative |
| max_active_downloads | 3 | Queueing value more realistic |
| max_active_torrents | 100 | Queueing value more realistic |
| max_active_uploads | 90 | Queueing value more realistic |
| alt_dl_limit | 10240 | More realistic scheduled limit |
| alt_up_limit | 1024 | More realistic scheduled limit |
| ip_filter_enabled | true | p2pblocklist exists |
| bittorrent_protocol | 0 | 0 = TCP+uTP (Both) |
| merge_trackers | true | Preserved from original config |
| recheck_completed_torrents | true | Preserved from original config |

Settings NOT settable via API (DiskIOReadMode, DiskIOWriteMode, DiskQueueSize, HashingThreadsCount, AsyncIOThreadsCount, FilePoolSize, DiskCacheSize, ResumeDataStorageType) are preserved by the config overwrite — the image default `/defaults/qBittorrent.conf` sets sensible values for all of these.

## Categories

Set via createCategory API calls in qbt-config.json:

| Category | savePath |
|---|---|
| movies | movies |
| shows | shows |
| documentaries | documentaries |
| ebooks | ebooks |
| manual-downloads | manual-downloads |

## File changes

### Deleted

- `qbittorrent/app/config/qBittorrent.conf` — replaced by API + image default
- `qbittorrent/app/config/categories.json` — replaced by API
- `qbittorrent/app/config/watched_folders.json` — replaced by API (scan_dirs in setPreferences)
- `qbittorrent-p2pblocklist/` (entire directory) — replaced by initContainer ipfilter download

### Added

- `qbittorrent/app/config/qbt-init.sh` — config overwrite + ipfilter download
- `qbittorrent/app/config/qbt-poststart.sh` — generic API executor
- `qbittorrent/app/config/qbt-config.json` — declarative API call definitions

### Modified

- `qbittorrent/app/helmrelease.yaml` — initContainer, postStart hook, persistence restructure
- `qbittorrent/app/kustomization.yaml` — configMapGenerator: scripts + config
- `default/kustomization.yaml` — p2pblocklist ks.yaml removed

## Second round (future)

- Add `web_ui_password` key to 1Password item
- Update ExternalSecret to expose it as env var
- Mount the secret and set `web_ui_password` via API (or remove bypass_local_auth)

## Related

- relates_to [[k8s-workloads]]
- relates_to [[external-secrets]]
