---
title: pingvin-share-x-selfhosted-roadmap
type: note
permalink: home-ops/docs/progress/pingvin-share-x-selfhosted-roadmap
tags:
- pingvin-share-x
- selfhosted
- roadmap
- completed
- oidc
---

# Pingvin Share X — Selfhosted Namespace Implementation — Completed

## Status: completed
## Priority: medium
## Area: selfhosted
## Created: 2026-06-09
## Completed: 2026-06-15

## Summary

Implemented [Pingvin Share X](https://github.com/smp46/pingvin-share-x) (v1.19.1) in the `selfhosted` namespace as a GitOps-managed HelmRelease using the bjw-s app-template chart, exposed via Gateway API HTTPRoute on both `envoy-external` and `envoy-internal` gateways at `share.${PUBLIC_DOMAIN}`.

The implementation went beyond the original roadmap scope. In addition to the planned Round 2 work (config + secrets + init container), OIDC authentication via Pocket-ID was added (originally explicitly excluded), the built-in Caddy was disabled in favour of a split-port Service (3333 frontend + 8080 backend), and the NFS uploads mount was replaced with PVC-only storage. The workload is hardened with a per-app CiliumNetworkPolicy and `readOnlyRootFilesystem: true`.

Live cluster state (verified 2026-06-16): `HelmRelease/pingvin-share-x` is Ready (chart app-template@5.0.1); pod `pingvin-share-x-87886bd8c-4z28h` is Running 1/1 with 0 restarts over 46h.

## Changes Made

| Aspect | Original Roadmap Plan | Actual Implementation |
|---|---|---|
| Built-in Caddy | Enabled, single Service on port 3000 | **Disabled** (`CADDY_DISABLED: "true"`); split Service: 3333 (frontend) + 8080 (backend) |
| OAuth/OIDC | Explicitly excluded ("only local SQLite + built-in auth") | **Added**: OIDC via Pocket-ID at `https://id.${PUBLIC_DOMAIN}`; `disablePassword: "true"`; `initUser.enabled: false` |
| UID/GID | 10002/10002 | 10001/10001 (aligned with `open-webui` neighbour) |
| Uploads storage | NFS mount `${NAS_IP}:/media/pingvinshare_uploads` to `/data/uploads` | **PVC-only** (NFS removed); `frontend-img` subPath mount added for logo upload |
| Init container image | `ghcr.io/dmfrey/bash:5.2.26-alpine3.20` (bo0tzz reference) | `docker.io/nginx:stable-alpine` |
| `/tmp` emptyDir | Required for `readOnlyRootFilesystem: true` + `cp -rn` entrypoint | Not needed (Caddy disabled, entrypoint no longer runs `cp -rn`) |
| ConfigMap | Round 2 TODO | Done: `kustomization.yaml` configMapGenerator with `config/config.yaml` (`disableNameSuffixHash: true`) |
| ExternalSecret | Round 2 TODO | Done: pulls from `pingvinsharex` (OIDC + initUser creds) + `smtp2go` 1Password items |
| Init container (envsubst) | Round 2 TODO | Done: `config-init` runs `envsubst < /config-template/config.yaml > /config/config.yaml` |
| Image digest pinning | Verify sha256 for v1.19.1 | Pinned: `v1.19.1@sha256:332f0b41acf1828f0f0221acb74304f6e1d33a7a952a1be60b3988eeae2b797e` |
| CiliumNetworkPolicy | Not in original roadmap | Added: ingress restricted to `envoy-external` + `envoy-internal` on ports 3333+8080; egress via cluster-wide `allow-cluster-egress` CCNP |
| Gateway policy | Not in original roadmap | Added: `block-user-agents.lua` Envoy Gateway filter (commit `7432cb5f2`, part of broader gw+iam work) |
| VolSync backup | Planned | Wired via `components/volsync` in `ks.yaml` (5Gi PVC, democratic-csi-local-hostpath) |

## Scope Deviations Rationale

- **Caddy disabled**: with the gateway terminating TLS and Envoy routing `/api/*` directly to port 8080, the in-container Caddy hop was redundant. Commit `ec75a93bd`.
- **OIDC added**: aligned with the IAM platform (`docs/areas/iam`); `disablePassword: "true"` makes Pocket-ID the sole identity source. This superseded the original "built-in auth only" decision and the `initUser.enabled: true` permanent-on plan.
- **NFS to PVC**: NFS uploads mount removed in favour of PVC-only storage (commit `f08c90c56`); VolSync PVC snapshots cover durability.
- **UID 10001**: aligned with `open-webui` (10001/10001) rather than the planned 10002; safe because democratic-csi-local-hostpath uses `fsGroupChangePolicy: OnRootMismatch` and the apps do not share PVCs.

## Files

- `kubernetes/apps/selfhosted/pingvin-share-x/ks.yaml` — Flux Kustomization entry; dependsOn `onepassword-connect` + `democratic-csi`; volsync component; 5Gi capacity
- `kubernetes/apps/selfhosted/pingvin-share-x/app/kustomization.yaml` — resources: CNP + ExternalSecret + HelmRelease; configMapGenerator for `config/config.yaml` with `disableNameSuffixHash: true`
- `kubernetes/apps/selfhosted/pingvin-share-x/app/helmrelease.yaml` — bjw-s app-template HelmRelease; two ports (3333/8080), `config-init` initContainer, `readOnlyRootFilesystem: true`, resources 100m/256Mi req to 1Gi mem limit
- `kubernetes/apps/selfhosted/pingvin-share-x/app/externalsecret.yaml` — ExternalSecret pulling `pingvinsharex` + `smtp2go` from `onepassword-connect` ClusterSecretStore, 12h refresh
- `kubernetes/apps/selfhosted/pingvin-share-x/app/ciliumnetworkpolicy.yaml` — per-app CNP restricting ingress to envoy gateways
- `kubernetes/apps/selfhosted/pingvin-share-x/app/config/config.yaml` — Pingvin Share config template with `${VAR}` envsubst placeholders (SMTP, OIDC); uses `$$` to escape `${...}` against Flux postBuild substitution

## Deferred

None. The implementation is fully operational and stable in the cluster.

## Verification

- `kubectl -n selfhosted get helmrelease pingvin-share-x` returned Ready, "Helm upgrade succeeded for release selfhosted/pingvin-share-x.v33 with chart app-template@5.0.1"
- `kubectl -n selfhosted get pods -l app.kubernetes.io/name=pingvin-share-x` returned `pingvin-share-x-87886bd8c-4z28h` Running 1/1, 0 restarts, 46h uptime
- HTTPRoute `share.${PUBLIC_DOMAIN}` attached to both `envoy-external` and `envoy-internal` gateways
- OIDC discovery URL: `https://id.${PUBLIC_DOMAIN}/.well-known/openid-configuration`

## Original Roadmap Reference

Originally at `docs/roadmap/pingvin-share-x-selfhosted-roadmap`. Moved to `docs/progress/` upon completion per the project's "Fully implemented roadmap items → progress/[roadmap-item-name]" rule. Reference implementations consulted: [bo0tzz/clusterfuck](https://github.com/bo0tzz/clusterfuck/tree/main/kubernetes/apps/share/pingvin-share) (init container + envsubst pattern), [thiagoalmeidasa/homelab](https://github.com/thiagoalmeidasa/homelab) (readOnlyRootFilesystem reference).

## Relations

- depends_on [[docs/areas/networking]] (Envoy Gateway HTTPRoute, gateway-policies)
- depends_on [[docs/areas/external-secrets]] (ClusterSecretStore, ExternalSecret)
- depends_on [[docs/areas/volsync-backup]] (PVC backup)
- depends_on [[docs/areas/iam]] (Pocket-ID OIDC provider)
- part_of [[docs/areas/k8s-workloads]]
- relates_to [[docs/areas/flux-gitops]] (HelmRelease, Kustomization)
- relates_to [[docs/roadmap/sso-implementation]] (OIDC integration)
