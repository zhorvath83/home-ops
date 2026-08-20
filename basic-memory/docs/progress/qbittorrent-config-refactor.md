---
title: qbittorrent-config-refactor
type: note
permalink: home-ops/docs/progress/qbittorrent-config-refactor
topic: qBittorrent API-driven config provisioning
status: done
scope: Replace init-container ConfigMap copy + PBKDF2 append with API-driven provisioning.
  Config files removed from git, categories and watched folders set via API, p2pblocklist
  converted from CronJob to initContainer, WebUI credentials provisioning via env
  vars.
priority: medium
rationale: 'Current pain points: (1) runtime config overwrites — qBittorrent writes
  to qBittorrent.conf during runtime, and every pod restart overwrites with the configMap
  baseline, losing UI-side changes; (2) init container privilege footprint; (3) two-file
  split between git baseline and PVC runtime state with no resync path. Whether these
  are problems worth fixing depends on the value of runtime UI tuning.'
related_areas:
- k8s-workloads
- external-secrets
---

# qBittorrent config provisioning refactor

## Status: done

API-driven provisioning complete. qBittorrent.conf is the image default; all non-default
settings, categories, and watched folders are applied via the qBittorrent API from a
declarative JSON config committed to git.

## Architecture

### Init container (01-init): qbt-init.sh

Runs before the main container using the qBittorrent image (bash, curl, gunzip). Single
responsibility:

1. **Ipfilter download**: downloads ipfilter.dat.gz from GitHub and gunzips it to
   `/ipfilter/ipfilter.dat`. Non-fatal on failure — qBittorrent starts without IP filtering
   and a WARNING is logged.

### postStart hook: qbt-poststart.sh

Generic executor that reads `/scripts/qbt-config.json` and drives the qBittorrent API.

1. Polls `/api/v2/app/version` up to 120s (60 x 2s); exits 1 if the API never comes up.
2. Reads `.preferences` from the config and merges `web_ui_username` / `web_ui_password`
   from the `QBT_WEBUI_USERNAME` / `QBT_WEBUI_PASSWORD` env vars via `jq --arg` (safe JSON
   escaping; empty values are omitted, with a WARN if unset).
3. `setPreferences` — POST `/api/v2/app/setPreferences` with `json=<compact preferences>`.
   This includes `scan_dirs` (the watched-folder map), which replaces the whole scan_dirs
   value on each apply.
4. Reads `.categories[]` and for each calls `createCategory` with `category=<name>` and
   `savePath=${save_path}/${category}`, where `save_path` is `.preferences.save_path`
   (`/media/downloads/complete/`). Category savePaths are therefore derived from the
   category name + the shared save_path, not stated per-category.
5. HTTP status check: 2xx and 409 (Conflict = idempotent "already exists") accepted; all
   others exit 1. `Referer: http://127.0.0.1:8080` header on all calls (CSRF protection).

The executor is **create-only**: it never deletes categories or watched folders. Removing an
entry from `qbt-config.json` stops it being re-created, but does not remove it from qBittorrent
state — that must be done manually (WebUI or a one-off API call).

### ConfigMap: qbittorrent-scripts

`configMapGenerator` mounts three files at `/scripts/` (read-only):

- qbt-init.sh — init container script
- qbt-poststart.sh — postStart hook script
- qbt-config.json — declarative preferences + category list

`disableNameSuffixHash: true` keeps the ConfigMap name stable, and
`kustomize.toolkit.fluxcd.io/substitute: disabled` prevents Flux envsubst on the ConfigMap.

### Restart-on-config-change

The controller carries `reloader.stakater.com/auto: "true"`. Reloader watches the mounted
`qbittorrent-scripts` ConfigMap and restarts the pod when it changes, so a committed
`qbt-config.json` edit propagates through Flux reconcile → ConfigMap update → pod restart →
postStart re-applies preferences and categories.

### Authentication

`bypass_local_auth: true` is set via API for LAN access without password. WebUI credentials
are provisioned via env vars:

- 1Password item `qbittorrent` holds `webui-username` and `webui-password`
- ExternalSecret (`dataFrom.extract`) syncs all keys to Kubernetes Secret `qbittorrent-secret`
- HelmRelease: `QBT_WEBUI_USERNAME` / `QBT_WEBUI_PASSWORD` from `secretKeyRef`
  (`qbittorrent-secret`)
- poststart.sh merges them into the setPreferences payload via `jq --arg`

## Categories

Declared in the `categories` array of `qbt-config.json` and created via the `createCategory`
API. Each category's savePath is derived as `/media/downloads/complete/<category>`:

| Category | savePath |
|---|---|
| movies | /media/downloads/complete/movies |
| shows | /media/downloads/complete/shows |
| docuseries | /media/downloads/complete/docuseries |
| docufilms | /media/downloads/complete/docufilms |
| ebooks | /media/downloads/complete/ebooks |
| misc | /media/downloads/complete/misc |

The `documentaries` category was split into `docuseries` and `docufilms`.

## Watched folders

`scan_dirs` in `setPreferences` maps each `/media/downloads/watchdir/<category>` to
`/media/downloads/complete/<category>` for the same set (misc, movies, shows, docuseries,
docufilms, ebooks). qBittorrent auto-adds torrents dropped in a watchdir and files them under
the matching complete path.

## Config values

`qbt-config.json` (`preferences` block) is the source of truth for all setPreferences values.
Key decisions reflected there:

| Setting | Value | Rationale |
|---|---|---|
| anonymous_mode | true | Hide client identity from peers |
| ip_filter_enabled | true | p2pblocklist ipfilter loaded by init container |
| bittorrent_protocol | 0 | 0 = TCP+uTP (Both) |
| auto_tmm_enabled | true | Automatic Torrent Management by category savePath |
| queueing_enabled | true | Active-download/torrent/upload limits enforced |
| scheduler_enabled | true | Time-banded alt speed limits (08:00–20:00) |
| max_ratio_enabled | true | Ratio limit policy on (act = stop, `max_ratio_act: 0`) |
| bypass_local_auth | true | LAN access without password |
| web_ui_csrf_protection_enabled | false | API calls carry Referer header instead |
| merge_trackers | true | Preserved from original config |
| recheck_completed_torrents | true | Preserved from original config |

Settings not settable via the qBittorrent API (disk IO mode, queue size, hashing threads, async
IO threads, file pool size, disk cache size, resume-data storage type) are left at the image
default.

## File changes

### Deleted

- qbittorrent/app/config/qBittorrent.conf — replaced by API + image default
- qbittorrent/app/config/categories.json — replaced by API
- qbittorrent/app/config/watched_folders.json — replaced by API (scan_dirs in setPreferences)
- qbittorrent-p2pblocklist/ (entire directory) — replaced by initContainer ipfilter download

### Added

- qbittorrent/app/config/qbt-init.sh — ipfilter download
- qbittorrent/app/config/qbt-poststart.sh — generic API executor (setPreferences + createCategory)
- qbittorrent/app/config/qbt-config.json — declarative preferences + category list

### Modified

- qbittorrent/app/helmrelease.yaml — initContainer, postStart hook, credential secretKeyRefs,
  persistence restructure, reloader annotation
- qbittorrent/app/kustomization.yaml — configMapGenerator (scripts + config), Flux envsubst
  disabled

## Related

- relates_to [[k8s-workloads]]
- relates_to [[external-secrets]]
