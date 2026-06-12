---
title: qbittorrent-config-refactor
type: note
permalink: home-ops/docs/progress/qbittorrent-config-refactor
topic: qBittorrent API-driven config provisioning
status: done
scope: Replace init-container ConfigMap copy + PBKDF2 append with API-driven provisioning.
  Config files removed from git, categories and watched folders set via API, p2pblocklist
  converted from CronJob to initContainer, WebUI password provisioning via envVars.
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

Both rounds complete: API-driven provisioning with WebUI password via envVars.

## Architecture

### Init container: qbt-init.sh

Runs before the main container. Uses the qBittorrent image (bash, curl, gunzip included).

1. **Config overwrite**: Always copies /defaults/qBittorrent.conf to /config/qBittorrent/qBittorrent.conf. Clean baseline on every pod start — postStart hook applies all non-default settings via API.
2. **Stale file cleanup**: Removes categories.json and watched_folders.json from PVC (now managed via API).
3. **Ipfilter download**: Downloads ipfilter.dat from GitHub. Non-fatal on failure.

### postStart hook: qbt-poststart.sh

Generic executor that reads qbt-config.json and calls each API endpoint.

1. Polls /api/v2/app/version up to 120s (60 x 2s)
2. Iterates qbt-config.json entries, each with endpoint + method + payload
3. method: "json" sends payload as json=<compact JSON> form parameter (setPreferences convention)
4. method: "form" sends each payload key-value as separate --data-urlencode form field (createCategory convention)
5. envVars field: maps API payload keys to environment variable names; script reads env vars and merges into payload/form args at runtime. Unset env vars trigger a WARNING and the key is omitted.
6. HTTP status check: 2xx and 409 (Conflict = idempotent success) accepted, all others exit 1
7. Referer: http://127.0.0.1:8080 header on all calls (CSRF protection)

### ConfigMap: qbittorrent-scripts

Contains three files mounted at /scripts/:
- qbt-init.sh — init container script
- qbt-poststart.sh — postStart hook script
- qbt-config.json — declarative API call definitions

Flux envsubst disabled via kustomize.toolkit.fluxcd.io/substitute: disabled annotation.

### Authentication

bypass_local_auth: true set via API. WebUI password provisioned via envVars mechanism:

- 1Password item qbittorrent, field webui-password stores the plaintext password
- ExternalSecret (dataFrom.extract) syncs all keys to Kubernetes Secret qbittorrent-secret
- HelmRelease: QBT_WEBUI_PASSWORD env var from secretKeyRef (qbittorrent-secret, key webui-password)
- qbt-config.json envVars: {"web_ui_password": "QBT_WEBUI_PASSWORD"} on the setPreferences entry
- poststart.sh reads QBT_WEBUI_PASSWORD, merges into the API payload via jq --arg (safe JSON escaping)

## Config values

Preferences set via API are in qbt-config.json. Key decisions:

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
| bypass_local_auth | true | LAN access without password |

Settings NOT settable via API (DiskIOReadMode, DiskIOWriteMode, DiskQueueSize, HashingThreadsCount, AsyncIOThreadsCount, FilePoolSize, DiskCacheSize, ResumeDataStorageType) are preserved by the config overwrite — the image default sets sensible values for all of these.

## Categories

Set via createCategory API calls in qbt-config.json with absolute savePath values:

| Category | savePath |
|---|---|
| movies | /media/downloads/complete/movies |
| shows | /media/downloads/complete/shows |
| documentaries | /media/downloads/complete/documentaries |
| ebooks | /media/downloads/complete/ebooks |
| manual-downloads | /media/downloads/complete/manual-downloads |

Stale categories.json and watched_folders.json are removed by qbt-init.sh on every pod start.

## File changes

### Deleted

- qbittorrent/app/config/qBittorrent.conf — replaced by API + image default
- qbittorrent/app/config/categories.json — replaced by API
- qbittorrent/app/config/watched_folders.json — replaced by API (scan_dirs in setPreferences)
- qbittorrent-p2pblocklist/ (entire directory) — replaced by initContainer ipfilter download

### Added

- qbittorrent/app/config/qbt-init.sh — config overwrite + stale file cleanup + ipfilter download
- qbittorrent/app/config/qbt-poststart.sh — generic API executor with envVars support
- qbittorrent/app/config/qbt-config.json — declarative API call definitions (with envVars for password)

### Modified

- qbittorrent/app/helmrelease.yaml — initContainer, postStart hook, QBT_WEBUI_PASSWORD secretKeyRef, persistence restructure
- qbittorrent/app/kustomization.yaml — configMapGenerator: scripts + config, Flux envsubst disabled
- media/kustomization.yaml — p2pblocklist ks.yaml removed

## Related

- relates_to [[k8s-workloads]]
- relates_to [[external-secrets]]
