---
title: qbittorrent-config-refactor
type: note
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
- [status] accepted
- [priority] medium

## Scope

Replace the init-container + ConfigMap config-injection pattern with a zero-config-file approach: let qBittorrent generate its own qBittorrent.conf from upstream defaults, then apply non-default settings via the WebUI API (`/api/v2/app/setPreferences`, `/api/v2/torrents/createCategory`). The WebUI password is set via the same API (`web_ui_password` key, plaintext — qBittorrent hashes internally), delivered from 1Password through ESO.

## Rationale

Current pain points resolved:

1. **No full config file in git** that breaks on qBittorrent config-structure changes across versions
2. **No init container** — eliminates privilege footprint and the busybox image pull (mostly — see first-boot auth below)
3. **No ConfigMap** — no configMapGenerator, no config/ directory, no kustomization complexity
4. **API-driven config is version-agnostic** — qBittorrent will only ignore unknown keys, not crash on structural changes in an INI file
5. **Categories and watched folders** are also API-settable, eliminating categories.json and watched_folders.json

## Architecture

### Phase 1 — Remove config injection

Delete ConfigMap, init container, config/ directory, configMapGenerator in kustomization.yaml. The PVC remains as /config mount for runtime state.

### Phase 2 — API setup via postStart hook

A postStart lifecycle hook on the main container:

1. Waits for the qBittorrent WebUI to accept connections (poll `/api/v2/app/version` with retry)
2. Authenticates using the bootstrap auth bypass (localhost, no auth required via LocalHostAuth)
3. Calls `/api/v2/app/setPreferences` with the non-default settings JSON
4. Calls `/api/v2/torrents/createCategory` for each category (idempotent — 409 if exists, ignore)
5. Sets the real WebUI password via `web_ui_password` in setPreferences

The password from 1Password is passed as an env var from the ExternalSecret.

### Phase 3 — ESO password delivery

The ExternalSecret already syncs the qbittorrent 1Password item. Add a new key (webui_password) to the 1Password item. The postStart script reads it from an env var and passes it in the setPreferences call. The PBKDF2 field becomes unnecessary — delete it from 1Password and remove the secret mount from HelmRelease.

### Phase 4 — Cleanup

Remove the configfiles and secret persistence mounts from HelmRelease. Remove the configMapGenerator from kustomization.yaml. Remove config/ directory. Simplify the HelmRelease persistence block to only config PVC + NFS.

## First-Boot Authentication

qBittorrent >=4.6.1 generates a random temporary admin password on first boot and prints it to stdout. The API setup script needs to authenticate its first setPreferences call.

**Recommended: Option C — Minimal bootstrap conf**

A 3-line INI fragment written by a minimal init container (busybox echo) to `/config/qBittorrent/qBittorrent.conf` before qBittorrent starts:

```ini
[LegalNotice]
Accepted=true

[Preferences]
WebUI\LocalHostAuth=true
WebUI\Username=zhorvath83
```

qBittorrent picks this up on startup. Then the postStart script:

1. Calls API on localhost (auth bypassed for localhost per LocalHostAuth=true)
2. Sets all preferences via setPreferences (including web_ui_password, bypass_local_auth, etc.)
3. Creates categories via createCategory

The bootstrap conf is version-stable — LegalNotice and WebUI LocalHostAuth have not changed across qBittorrent 4.x/5.x.

**Rejected alternatives:**

- A — Parse pod logs for temp password: fragile (log timing, buffering, multi-container pod)
- B — Skip auth on first boot: requires verifying upstream default for bypass_local_auth, unreliable

## API Mapping — setPreferences payload

| API key | Value | Notes |
|---------|-------|-------|
| save_path | /media/downloads/complete/ | Default save path |
| temp_path | /media/downloads/incomplete/ | Incomplete torrents path |
| temp_path_enabled | true | Enable incomplete folder |
| start_paused_enabled | true | Add torrents paused |
| preallocate_all | true | Pre-allocate disk space |
| incomplete_files_ext | true | Append .!qB to incomplete files |
| auto_tmm_enabled | false | Disable Auto TMM by default |
| save_path_changed_tmm_enabled | false | Don't relocate on save path change |
| category_changed_tmm_enabled | false | Don't relocate on category path change |
| export_dir | /media/downloads/watchdir/added/ | .torrent export on add |
| export_dir_fin | /media/downloads/watchdir/downloaded/ | .torrent export on completion |
| listen_port | 50413 | Torrenting port |
| upnp | false | Disable UPnP |
| bittorrent_protocol | 0 | TCP+uTP (Both) |
| dht | false | Disable DHT |
| pex | false | Disable PeX |
| lsd | false | Disable LSD |
| anonymous_mode | true | Anonymous mode |
| queueing_enabled | true | Enable queuing |
| max_active_downloads | 10 | Max active downloads |
| max_active_torrents | 2000 | Max active torrents |
| max_active_uploads | 2000 | Max active uploads |
| max_ratio_act | 0 | Stop at ratio limit |
| dont_count_slow_torrents | true | Ignore slow torrents in queue count |
| limit_tcp_overhead | true | Include TCP overhead in limits |
| alt_dl_limit | 10240 | Alt download limit (KiB/s) |
| alt_up_limit | 1024 | Alt upload limit (KiB/s) |
| scheduler_enabled | true | Enable scheduler |
| schedule_from_hour | 8 | Scheduler start hour |
| schedule_from_min | 0 | Scheduler start minute |
| schedule_to_hour | 20 | Scheduler end hour |
| schedule_to_min | 0 | Scheduler end minute |
| scheduler_days | 1 | Weekdays only |
| ip_filter_enabled | true | Enable IP filter |
| ip_filter_path | /config/ipfilter.dat | IP filter file path |
| save_resume_data_interval | 10 | Resume data save interval (min) |
| web_ui_username | zhorvath83 | WebUI username |
| web_ui_password | <from env var> | WebUI password (plaintext, qBt hashes it) |
| web_ui_port | 8080 | WebUI port |
| web_ui_host_header_validation_enabled | false | Disable host header validation |
| web_ui_domain_list | 10.244.0.0/16 | Trusted reverse proxies |
| bypass_local_auth | true | Bypass auth for localhost |
| web_ui_csrf_protection_enabled | true | CSRF protection |
| web_ui_secure_cookie_enabled | true | Secure cookie flag |
| web_ui_max_auth_fail_count | 5 | Max auth failures before ban |
| web_ui_ban_duration | 3600 | Ban duration (seconds) |
| web_ui_session_timeout | 3600 | Session timeout (seconds) |
| scan_dirs | {"/media/downloads/watchdir":"/media/downloads/complete"} | Watched folder to save path |
| locale | en | Language |

## API Mapping — createCategory calls

| Category | savePath |
|----------|----------|
| movies | movies |
| shows | shows |
| documentaries | documentaries |
| ebooks | ebooks |
| manual-downloads | manual-downloads |

## Settings NOT in the API (kept as upstream defaults)

| Current conf key | Current value | Upstream default | Impact |
|------------------|---------------|-------------------|--------|
| FileLogger* | Various | Enabled by default | Acceptable — defaults are sensible |
| AutoRun* | Disabled | Disabled | Same |
| BitTorrent/MergeTrackersEnabled | true | true (5.x) | Same |
| Core/AutoDeleteAddedTorrentFile | IfAdded | Never | Torrent files kept after add — acceptable |
| Meta/MigrationVersion | 8 | Auto-set | qBittorrent manages this |
| Network* | Various disabled | Disabled | Same |
| Preferences/DynDNS* | Disabled | Disabled | Same |
| Preferences/IPFilter* | Conflicting values | Handled via API | API covers it |
| Preferences/WebUI Address/ServerDomains/AlternativeUI/RootFolder/Clickjacking/CustomHTTPHeaders/HTTPS* | Various | Defaults match | Same |

## Implementation Order

1. Add webui_password key to 1Password qbittorrent item (plaintext password)
2. Update ExternalSecret to expose webui_password as env var (or restructure to use dataFrom + target.template)
3. Create the postStart API setup script (inline shell in HelmRelease lifecycle.postStart)
4. Replace the init container with a minimal 3-line bootstrap (LegalNotice + LocalHostAuth + Username)
5. Remove ConfigMap, config/ directory, configMapGenerator from kustomization.yaml
6. Remove the PBKDF2 field from 1Password and the secret mount from HelmRelease
7. Clean up HelmRelease persistence block (config PVC + NFS only)
8. Test: fresh PVC (first boot), existing PVC (subsequent boot), pod restart

## Related

- relates_to [[k8s-workloads]]
- relates_to [[external-secrets]]
- implements [[AD-020-renovate-cloud-fragments]]
