---
title: recyclarr
type: note
permalink: home-ops/docs/roadmap/recyclarr
tags:
- roadmap
- recyclarr
- sonarr
- radarr
- arr-stack
- config-sync
- planned
---

# Roadmap: Recyclarr

## Status: planned

## Summary

Introduce Recyclarr into the cluster to automate quality profile, custom format, quality definition, media naming, and media management synchronization for Sonarr and Radarr, using the TRaSH Guides as the canonical source.

## Motivation

- Sonarr and Radarr quality profiles and custom formats drift from TRaSH Guide recommendations over time
- Manual sync is error-prone and tedious
- Recyclarr automates this as a daily CronJob with zero UI required
- Recyclarr v8+ adds custom format groups (auto-sync categories), media naming, and media management sync

## Current State (Config Survey)

### Sonarr

| Property | Value |
|----------|-------|
| Image | ghcr.io/home-operations/sonarr:4.0.17.2967 |
| Port | 8989 |
| Route | shows.PUBLIC_DOMAIN (envoy-external + envoy-internal) |
| Namespace | default |
| PVC | sonarr (existingClaim) |
| Security | UID/GID 10001, readOnlyRootFilesystem, drop ALL caps |
| Resources | 5m CPU / 220Mi mem request, 1Gi mem limit |
| VolSync | Yes (hourly Kopia to OVH S3) |
| **ExternalSecret (API key)** | **NONE** — API key lives in the PVC config DB |
| NFS media mount | Yes (NAS_IP:/media → /media) |

### Radarr

| Property | Value |
|----------|-------|
| Image | ghcr.io/home-operations/radarr:6.2.0.10390 |
| Port | 7878 |
| Route | movies.PUBLIC_DOMAIN (envoy-external + envoy-internal) |
| Namespace | default |
| PVC | radarr (existingClaim) |
| Security | UID/GID 10001, readOnlyRootFilesystem, drop ALL caps |
| Resources | 5m CPU / 200Mi mem request, 1Gi mem limit |
| VolSync | Yes (hourly Kopia to OVH S3) |
| **ExternalSecret (API key)** | **NONE** — API key lives in the PVC config DB |
| NFS media mount | Yes (NAS_IP:/media → /media) |

### Critical Gap: API Key Delivery

Neither Sonarr nor Radarr has an ExternalSecret for their API keys. Currently these keys are stored inside each app's config database (PVC). Recyclarr requires these API keys as environment variables via !env_var.

**Options**:
1. Create new 1Password items for each API key (sonarr-api-key, radarr-api-key) and new ExternalSecrets to deliver them
2. Use a single Recyclarr ExternalSecret that extracts both keys from existing 1Password items (if the keys are already stored there under sonarr/radarr items)
3. Use !file substitution instead of !env_var (mount K8s secret as file, supported since Recyclarr v7.5.0)

Decision needed: which approach for API key delivery?

### Recyclarr Capabilities Survey

| Capability | Description | Relevance |
|-----------|-------------|-----------|
| Quality Definitions | Sync quality definitions (series for Sonarr, movie for Radarr) from TRaSH Guides | High — ensures proper quality scoring |
| Quality Profiles | Create/update profiles from guide templates (trash_id) or custom definitions | High — core feature |
| Custom Formats | Sync individual CFs with score assignment to profiles | High — core feature |
| Custom Format Groups | Auto-sync CF categories (Audio, HDR, Streaming, Unwanted, Required, etc.) to guide-backed profiles | High — v8 feature, reduces manual config |
| Media Naming | Sync episode/movie naming schemes from TRaSH Guides | Medium — ensures consistent naming |
| Media Management | Sync propers/repacks handling | Low — single setting |
| Include/Template | Reusable config snippets, template-based quick setup | Medium — reduces duplication |
| Prowlarr support | **Not supported** | N/A — Prowlarr manages indexers independently |
| Notifications | Apprise-based notifications per sync run | Low — optional |

### Deployment Model

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| Controller | CronJob | Recyclarr is task-based, not long-running. K8s-native scheduling, resource efficiency |
| Schedule | @daily | Sufficient for config drift prevention |
| Concurrency | Forbid | Prevent overlapping syncs |
| Image | ghcr.io/recyclarr/recyclarr:8 | Track major v8, avoid latest (removed in v8.4.0) |
| Chart | bjw-s app-template | Consistent with repo pattern |
| Ingress | None | CronJob — no UI needed |
| VolSync | Yes | Standard PVC backup pattern |

### TRaSH Guide Templates Available

**Sonarr** (13 templates): WEB-1080p, WEB-1080p (Alternative), WEB-2160p, WEB-2160p (Alternative), WEB-2160p (Combined), Anime Remux 1080p, plus French and German variants.

**Radarr** (16 templates): HD Bluray + WEB, UHD Bluray + WEB, Remux + WEB 1080p, Remux + WEB 2160p, Remux 2160p (Alternative), Remux 2160p (Combined), Anime Remux 1080p, plus French and German variants.

Quick setup: recyclarr config create --template <name> generates a working config from a template.

## Adaptation for home-ops

| Aspect | bjw-s Reference | home-ops Adaptation | Rationale |
|--------|-----------------|---------------------|-----------|
| Namespace | downloads | default | All arr-stack apps in default namespace |
| UID/GID | 2000 | 10001 | Cluster-wide standard |
| Sonarr URL | sonarr.downloads.svc:8989 | sonarr.default.svc:8989 | Namespace change |
| Radarr URL | radarr.downloads.svc:7878 | radarr.default.svc:7878 | Namespace change |
| API keys | ExternalSecret per key (radarr, sonarr 1Password items) | TBD — need to decide on secret delivery approach | Current gap |
| ConfigMap | configMapGenerator with disableNameSuffixHash | Same pattern | Preserves stable name for HelmRelease reference |
| Flux substitution | Disabled on ConfigMap (annotation) | Same — prevents !env_var conflict | Essential |
| VolSync | Component with VOLSYNC_CLAIM=recyclarr-config | Same pattern, APP=recyclarr | Standard |

## Decision Points

### 1. API Key Secret Delivery

How to deliver Sonarr/Radarr API keys to Recyclarr:
- **Option A**: New 1Password items (sonarr-api-key, radarr-api-key) + per-key ExternalSecrets, merged via envFrom in Recyclarr's ExternalSecret
- **Option B**: Single Recyclarr ExternalSecret extracting keys from existing sonarr/radarr 1Password items (if keys are stored there)
- **Option C**: Use !file substitution — mount secret files instead of env vars

Recommendation: Option A (explicit items) for clarity and independence.

### 2. Quality Profile Selection

Which TRaSH Guide profiles to use:
- **Sonarr**: WEB-1080p? WEB-2160p (Combined)? Both?
- **Radarr**: HD Bluray + WEB? UHD Bluray + WEB? Both?
- This depends on the user's media quality preferences and storage/display capabilities.

### 3. Custom Format Scope

How much CF automation:
- **Guide-backed profiles + auto-sync CF groups**: Minimal config, Recyclarr manages CF assignment automatically based on guide recommendations
- **Guide-backed profiles + manual CF selection**: Explicit control over which CFs are synced and their scores
- **Custom profiles + manual CFs**: Full control, most maintenance burden

### 4. Additional Sync Sections

- **Media naming**: Sync or skip? (Consistent naming across the arr stack)
- **Media management**: Sync propers/repacks handling or leave manual?
- **Quality definition**: Sync or skip? (Already configured in Sonarr/Radarr?)

### 5. Schedule and Notifications

- **CronJob schedule**: @daily (default), or different interval?
- **Notifications**: Apprise-based? Pushover? None?

## Implementation Steps

- [ ] 1. Decide on API key delivery approach (see Decision Point 1)
- [ ] 2. Create 1Password items for API keys if needed
- [ ] 3. Create directory structure: kubernetes/apps/default/recyclarr/app/config/
- [ ] 4. Create recyclarr.yml config (based on decisions from DP 2-4)
- [ ] 5. Create app/kustomization.yaml with configMapGenerator for recyclarr.yml
- [ ] 6. Create app/ocirepository.yaml for app-template chart
- [ ] 7. Create app/externalsecret.yaml for API keys
- [ ] 8. Create app/helmrelease.yaml (CronJob controller, sync command, security context UID 10001)
- [ ] 9. Create ks.yaml with VolSync component and postBuild substitutes
- [ ] 10. Register recyclarr in kubernetes/apps/default/kustomization.yaml
- [ ] 11. Validate: flux build ks recyclarr --dry-run
- [ ] 12. Commit and push, verify reconciliation

## Dependencies

- depends_on [[sonarr]] — must be running for Recyclarr to sync
- depends_on [[radarr]] — must be running for Recyclarr to sync
- depends_on [[external-secrets]] — ClusterSecretStore for API keys
- depends_on [[volsync-backup]] — PVC backup for recyclarr-config

## Observations

- Recyclarr is a CronJob (runs once daily), not a long-running service — no ingress, no service port needed
- The !env_var syntax in recyclarr.yml is Recyclarr's own variable interpolation, NOT Flux/Kustomize — Flux substitution must be disabled on the ConfigMap to prevent conflicts
- Sonarr and Radarr currently have NO ExternalSecret for API keys — this is a new requirement introduced by Recyclarr
- Prowlarr does not need Recyclarr (they manage orthogonal aspects: indexers vs. quality)
- CF groups (v8+) auto-sync reduces manual config significantly when using guide-backed quality profiles
- The !file syntax (v7.5.0+) could be an alternative to !env_var if file-based secret mounting is preferred
- Namespace alignment: all arr-stack apps are in default, so Recyclarr goes there too

## Related

- relates_to [[k8s-workloads]]
- relates_to [[external-secrets]]
- relates_to [[volsync-backup]]
