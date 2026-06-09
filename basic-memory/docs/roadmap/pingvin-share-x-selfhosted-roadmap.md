---
title: pingvin-share-x-selfhosted-roadmap
type: note
permalink: home-ops/docs/roadmap/pingvin-share-x-selfhosted-roadmap
---

# Pingvin Share X — Selfhosted Namespace Implementation Roadmap

## Overview

Implement [Pingvin Share X](https://github.com/smp46/pingvin-share-x) (v1.19.1) in the `selfhosted` namespace as a GitOps-managed HelmRelease using the bjw-s app-template chart, exposed via Gateway API HTTPRoute on both envoy-external and envoy-internal gateways.

**Scope excludes**: ClamAV, S3 storage, OAuth. Only local SQLite + built-in auth.

**Reference implementations**: [bo0tzz/clusterfuck](https://github.com/bo0tzz/clusterfuck/tree/main/kubernetes/apps/share/pingvin-share) (init container + envsubst), [thiagoalmeidasa/homelab](https://github.com/thiagoalmeidasa/homelab) (readOnlyRootFilesystem + Caddy).

## Implementation Status

### Round 1 — Deployed (no config, no secrets)

Files created:
- `kubernetes/apps/selfhosted/pingvin-share-x/ks.yaml`
- `kubernetes/apps/selfhosted/pingvin-share-x/app/kustomization.yaml`
- `kubernetes/apps/selfhosted/pingvin-share-x/app/helmrelease.yaml`
- Updated `kubernetes/apps/selfhosted/kustomization.yaml`

Key decisions:
- **Caddy enabled**: Single Service on port 3000, no `CADDY_DISABLED` or `API_URL`
- **readOnlyRootFilesystem: true** with `/tmp` emptyDir (entrypoint `cp -rn` fails silently, app works)
- **No config file**: App starts with defaults, admin setup wizard for initial configuration
- **No secrets**: No ExternalSecret in this round, will be added in Round 2
- **NFS uploads**: `${NAS_IP}:/media/pingvinshare_uploads` → `/data/uploads`
- **UID/GID**: 10002/10002

### Round 2 — Config + Secrets (TODO)

- ConfigMap generator with config.yaml template (envsubst placeholders)
- Init container with `ghcr.io/dmfrey/bash` for envsubst
- ExternalSecret pulling from `smtp2go` + `pingvinsharex` 1Password items
- No passwords in ConfigMap — all secrets via Kubernetes Secret env vars

## Application Profile

| Property | Value |
|---|---|
| Image | `ghcr.io/smp46/pingvin-share-x` |
| Current version | v1.19.1 |
| Architectures | linux/amd64, linux/arm64 |
| License | BSD-2-Clause |
| Database | SQLite (file-based, in data directory) |
| Service port | 3000 (Caddy routes /api/* internally) |
| Data path | `/data` (via `DATA_DIRECTORY` env var override) |
| Upload path | `/data/uploads/` (NFS-mounted) |

## Architecture Decisions

### Caddy Enabled (Single Service)

The container bundles Caddy which routes `/api/*` to the backend (port 8080) and everything else to the frontend (port 3333). A single Service on port 3000 exposes the Caddy listener. No need for `CADDY_DISABLED` or `API_URL` env vars.

### Trust Proxy

`TRUST_PROXY=true` — the app sits behind Envoy Gateway, which terminates TLS and forwards `X-Forwarded-*` headers.

### Config: Init Container + envsubst (Round 2)

1. ConfigMap (`pingvinsharex-configmap`) has template with `${VAR}` placeholders
2. ExternalSecret (`pingvinsharex-secret`) pulls SMTP + initUser credentials from 1Password
3. Init container runs `envsubst < /config-template/config.yaml > /config/config.yaml`
4. Main container reads generated config from shared emptyDir at `/config/config.yaml`

No passwords in ConfigMap — all sensitive values from Kubernetes Secrets sourced by ExternalSecret.

### Persistence and Storage

| Volume | Type | Mount Path | Purpose |
|---|---|---|---|
| `pingvin-share-x` | PVC (VolSync component) | `/data` | SQLite database + app data |
| NFS uploads | NFS (`${NAS_IP}:/media/pingvinshare_uploads`) | `/data/uploads` | Uploaded files |
| `tmp` | emptyDir | `/tmp` | Temp files (readOnlyRootFilesystem) |

- PVC: 5Gi (`democratic-csi-local-hostpath` storage class, from VolSync component)
- VolSync: hourly Kopia backups to OVH S3
- App UID/GID: **10002/10002** (next after open-webui's 10001/10001)
- NFS mount overlays the `/data/uploads` subdirectory of the PVC
- `readOnlyRootFilesystem: true` — `/tmp` as emptyDir, entrypoint `cp -rn` fails silently

### Exposure

| Gateway | Hostname | Notes |
|---|---|---|
| envoy-external (HTTPS) | `share.${PUBLIC_DOMAIN}` | Cloudflare Tunnel to public internet |
| envoy-internal (HTTPS) | `share.${PUBLIC_DOMAIN}` | LAN direct via k8s-gateway split DNS |

### initUser

`initUser.enabled: true` stays enabled permanently — idempotent, no duplicate creation if admin already exists.

### Secrets (Round 2)

ExternalSecret sources from **two** 1Password items:
- `smtp2go` → SMTP_HOSTNAME, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM
- `pingvinsharex` → INIT_USER_EMAIL, INIT_USER_PASSWORD

Both merge into a single Kubernetes Secret named `pingvinsharex-secret`.

## HelmRelease Key Sections

- Controller: `pingvin-share-x` (strategy: Recreate)
- Image: `ghcr.io/smp46/pingvin-share-x:v1.19.1@sha256:332f0b41acf1828f0f0221acb74304f6e1d33a7a952a1be60b3988eeae2b797e`
- Env: `TZ=${TIMEZONE}`, `TRUST_PROXY=true`, `DATA_DIRECTORY=/data`
- Security: runAsNonRoot, UID/GID 10002, drop ALL caps, readOnlyRootFilesystem, allowPrivilegeEscalation=false, seccompProfile RuntimeDefault
- Resources: 100m CPU / 256Mi memory request, 1Gi memory limit
- Service: `app:3000` (Caddy)
- Route: `share.${PUBLIC_DOMAIN}` → `app:3000`, envoy-external + envoy-internal
- PVC: existingClaim `pingvin-share-x` → `/data` (advancedMounts)
- NFS: `${NAS_IP}:/media/pingvinshare_uploads` → `/data/uploads` (globalMounts)
- emptyDir: `/tmp` (globalMounts)

## Open Items

- Config + secrets (Round 2): ConfigMap, ExternalSecret, init container
- 1Password items: create `pingvinsharex` item (INIT_USER_EMAIL, INIT_USER_PASSWORD)
- Image digest: verify sha256 for v1.19.1
- Init container image: `ghcr.io/dmfrey/bash:5.2.26-alpine3.20` (from bo0tzz reference)
- Verify: `readOnlyRootFilesystem: true` works with the entrypoint `cp -rn`

## File and Path References

- Namespace: `kubernetes/apps/selfhosted/namespace.yaml`
- Parent kustomization: `kubernetes/apps/selfhosted/kustomization.yaml`
- App-template OCI repository: `kubernetes/components/common/repos/app-template/`
- VolSync component: `kubernetes/components/volsync/`
- Cluster settings vars: `kubernetes/components/common/vars/`
- Open WebUI (reference app): `kubernetes/apps/selfhosted/open-webui/`
- SearXNG (reference app, stateless): `kubernetes/apps/selfhosted/searxng/`
- Plex (reference app, NFS mount): `kubernetes/apps/default/plex/app/helmrelease.yaml`
- Bo0tzz reference: `bo0tzz/clusterfuck/kubernetes/apps/share/pingvin-share/`
- Thiagoalmeidasa reference: `thiagoalmeidasa/homelab/kubernetes/apps/default/pingvin-share/`
- Networking area-reference: BM `docs/areas/networking`
- External Secrets area-reference: BM `docs/areas/external-secrets`
- VolSync area-reference: BM `docs/areas/volsync-backup`

## Relations

- depends_on [[networking]] (Envoy Gateway HTTPRoute)
- depends_on [[external-secrets]] (ClusterSecretStore, ExternalSecret)
- depends_on [[volsync-backup]] (PVC backup)
- part_of [[k8s-workloads]]
- relates_to [[flux-gitops]] (HelmRelease, Kustomization)
