---
title: flux-components-common
type: roadmap
permalink: home-ops/docs/roadmap/flux-components-common
topic: Adopt a flux components/common pattern — cluster-wide vars + shared OCIRepository
  + GitHub commit-status
status: implemented
priority: done
scope: 'Mirror the heavybullets8/heavy-ops components/common/ pattern adapted to home-ops
  constraints: dummy namespace + shared app-template OCIRepository + cluster-settings
  ConfigMap + GitHub commit-status alerts. Skip SOPS layer (Phase 6.7 collapsed it).
  Add a second patch on the cluster-apps Kustomization that injects postBuild.substituteFrom
  into every child Kustomization, with substitution.flux.home.arpa/disabled opt-out
  label.'
rationale: Reduces per-app OCIRepository duplication, centralizes timezone/IP/domain
  hardcoding into substitution vars, adds visible GitHub commit-status feedback for
  Flux reconciliations. Pattern is established across bjw-s/onedr0p/buroa/heavybullets8.
  Cluster ks.yaml is already patched for HelmRelease defaults — the new patch is structurally
  identical, just targets postBuild.
options:
- Full adoption — mirror heavybullets8 1:1 minus SOPS pieces
- Selective adoption (recommended) — namespace + repos + vars/cluster-settings + ks.yaml
  substituteFrom patch first; defer alerts until pushover/alertmanager model is resolved
- Substitution-only — just the cluster-settings ConfigMap and the ks.yaml patch; skip
  the Kustomize Component shape entirely
related_areas:
- flux-gitops
- k8s-workloads
- external-secrets
---

# Adopt a flux `components/common` pattern — cluster-wide vars + shared OCIRepository + GitHub commit-status

## Metadata (observation-form, schema validation)
- [topic] Adopt a flux components/common pattern — cluster-wide vars + shared OCIRepository + GitHub commit-status
- [status] proposed
- [priority] medium

## Scope

Mirror the `kubernetes/components/common/` pattern from the heavybullets8/heavy-ops reference into our repo, adapted to the home-ops constraints (no runtime SOPS, External-Secrets-only secret delivery, Pushover-based alerting today).

### Reference structure (heavybullets8/heavy-ops)

```
kubernetes/components/common/
├── kustomization.yaml          # Kustomize Component, includes 5 subtrees
├── namespace.yaml              # dummy 'not-used' namespace with VolSync + prune annotations
├── alerts/
│   ├── alertmanager/           # Flux Provider+Alert → in-cluster Alertmanager (error)
│   └── github/                 # Flux Provider+Alert+ExternalSecret → GitHub commit-status (info)
├── repos/
│   └── app-template/           # shared OCIRepository for bjw-s app-template chart
├── sops/                       # cluster-wide SOPS Secret
└── vars/
    ├── cluster-settings.yaml   # ConfigMap with cluster-wide substitution vars
    └── cluster-secrets.secret.sops.yaml  # sensitive substitution vars
```

### Reference cluster `ks.yaml` substitution model

The root `cluster-apps` Kustomization is patched so every child Kustomization auto-inherits:

```yaml
postBuild:
  substituteFrom:
    - { name: cluster-settings, kind: ConfigMap, optional: false }
    - { name: cluster-secrets,  kind: Secret,    optional: false }
```

with an opt-out via `labelSelector: substitution.flux.home.arpa/disabled notin (true)` on the patch target. The same patch also injects `decryption.provider: sops` and `deletionPolicy: WaitForTermination` everywhere.

### Adaptation to home-ops

| Reference piece | Action | Why |
|---|---|---|
| `namespace.yaml` (`not-used` dummy namespace) | **Rejected — per-namespace files instead** | Initial implementation used a shared `_` namespace, but each namespace needs different labels/annotations. Moved to per-namespace `apps/*/namespace.yaml` files (2026-05-23). |
| `alerts/alertmanager/` | **Defer / skip** | We have no Alertmanager today; depends on [[alertmanager-enable]]. Until then, the existing per-namespace Pushover `components/flux-alerts/` covers this path |
| `alerts/github/` | **Adopt and adapt** | Posts Flux Kustomization status back to GitHub as commit-status checks — high value for visible MR feedback. Needs 1P item `flux` (or equivalent) with a GitHub PAT, plumbed via ExternalSecret backed by our `onepassword-connect` ClusterSecretStore (not the heavybullets8 `onepassword` name) |
| `repos/app-template/` | **Adopt** | Removes per-app duplication of the bjw-s `app-template` OCIRepository. Inventory the app subtrees that currently declare their own and migrate to the shared one |
| `sops/` | **Skip** | Phase 6.7 (2026-05-17) collapsed the runtime SOPS layer entirely (`AD-009` superseded). We do not want to reintroduce SOPS at the substitution layer |
| `vars/cluster-settings.yaml` (ConfigMap, non-sensitive) | **Adopt with home-ops content** | Centralizes timezone, public domain, internal IPs that today are hardcoded across manifests. Candidate vars: `TIMEZONE`, `CLUSTER_NAME`, `PUBLIC_DOMAIN`, `NAS_IP=192.168.1.10`, `K8S_CP0_IP=192.168.1.11`, `ENVOY_INTERNAL_IP=…`, `ENVOY_EXTERNAL_IP=…`, `K8S_GATEWAY_IP=…`, `CLUSTER_DNS_IP=10.245.0.10` |
| `vars/cluster-secrets.secret.sops.yaml` | **Replace with ExternalSecret-backed Secret OR skip** | If any cluster-wide *sensitive* substitution vars are needed, deliver them via ExternalSecret reading from 1Password, producing a `Secret/cluster-secrets` consumed by the same `substituteFrom` block. Skip entirely if no current need (most candidates are non-sensitive per repo policy — public domain and internal RFC1918 IPs are not secret) |

### Cluster `ks.yaml` changes required

Today our `kubernetes/flux/cluster/ks.yaml` already has a patch that injects HelmRelease defaults into every child Kustomization. The proposed change adds a **second patch** (does NOT replace the existing one):

1. Add `postBuild.substituteFrom` on the root Kustomization itself, referencing `cluster-settings` (ConfigMap, optional: false)
2. Add a patch with `target.labelSelector: substitution.flux.home.arpa/disabled notin (true)` that injects the same `substituteFrom` block into every child Kustomization
3. **Do NOT** include the `decryption.provider: sops` line — we have no SOPS layer
4. **Do NOT** mass-add `deletionPolicy: WaitForTermination` without an audit — that changes finalizer behavior cluster-wide

### Migration order

1. ~~Land `kubernetes/components/common/namespace.yaml`~~ — **SUPERSEDED (2026-05-23)**: per-namespace `apps/*/namespace.yaml` files instead of shared component
2. Land `vars/cluster-settings.yaml` + the cluster `ks.yaml` substituteFrom patch — minimal viable footprint, no behavior change unless apps start referencing the new vars
2. Migrate hardcoded values to `${VAR}` substitution one subtree at a time, validating reconciliation between each batch
3. Land `repos/app-template/` and migrate apps' `chartRef` to the shared OCIRepository
4. Add `alerts/github/` once the 1P `flux` item is provisioned with a scoped PAT (Repo-status write only)
5. Defer `alerts/alertmanager/` until [[alertmanager-enable]] is decided and implemented

## Rationale

- **Reduces duplication**: every app currently has to reason about its own `OCIRepository` (or the deprecated `HelmRepository`) and re-declare common values. A shared `components/common/` is the canonical homelab pattern (heavybullets8, plus matching shapes in bjw-s, onedr0p, buroa).
- **Visible MR feedback**: `alerts/github/` posts commit-status checks back to GitHub for every Kustomization apply — turns Flux reconciliation into a visible CI signal on MRs, complementing the existing Pushover-on-error path.
- **Substitution layer is the right level**: today timezone, internal IPs, and similar values are hardcoded inline. Centralizing them as substitution vars makes future rename or topology change a single-file edit.
- **Cluster `ks.yaml` is already patched** for HelmRelease defaults — the proposed second patch is structurally identical, just targets `postBuild` instead of HelmRelease behavior.

## Tradeoffs and risks

- **Coordination with [[pushover-provider-model-unify]]**: that roadmap item already flags that we have two parallel Pushover delivery surfaces. Adding `alerts/github/` to a new `components/common/` introduces a *third* alerting surface unless we unify first. Sequencing matters.
- **Coordination with [[alertmanager-enable]]**: if we adopt Alertmanager, the `alerts/alertmanager/` subtree becomes relevant; if we don't, it stays disabled. The common component should be designed so the alertmanager subtree can be added later without restructuring.
- **Substitution-on-everything blast radius**: any malformed `cluster-settings` ConfigMap entry that interpolates into a manifest can break reconciliation across every Kustomization in one shot. The `substitution.flux.home.arpa/disabled` opt-out label is the escape hatch — needs to be documented as part of the rollout.
- **SOPS resurrection risk**: the heavybullets8 reference uses SOPS for cluster-secrets. We must NOT copy this; `AD-009` was explicitly superseded. Sensitive substitution vars (if any) MUST flow through ExternalSecret-backed `Secret/cluster-secrets`.
- **VolSync privileged-mover annotation**: the dummy namespace declares `volsync.backube/privileged-movers: "true"`. We need to verify this is the right default for the home-ops cluster — `docs/areas/volsync-backup` should be cross-checked before adopting verbatim.
- **Naming-collision risk**: 1P item name (`flux` vs our existing items) and ExternalSecret name (`github-token-secret`) need to be reconciled against `docs/areas/external-secrets` conventions.

## Options

1. **Full adoption** — mirror the heavybullets8 layout 1:1, dropping only the `sops/` and `vars/cluster-secrets.secret.sops.yaml` pieces. Maximum parity, highest cognitive familiarity for anyone coming from the homelab community.
2. **Selective adoption (recommended starting point)** — `namespace.yaml` + `repos/app-template/` + `vars/cluster-settings.yaml` + cluster `ks.yaml` substituteFrom patch first. Defer `alerts/github/` and `alerts/alertmanager/` until the cross-cutting alerting model is resolved via [[pushover-provider-model-unify]] and [[alertmanager-enable]].
3. **Substitution-only adoption** — just the `vars/cluster-settings` ConfigMap and the `ks.yaml` substituteFrom patch. Skip the components/common Kustomize Component shape entirely. Minimum surface, but loses the shared OCIRepository and GitHub-alert benefits.

## Related
- relates_to [[flux-gitops]]
- relates_to [[k8s-workloads]]
- relates_to [[external-secrets]]
- relates_to [[pushover-provider-model-unify]]
- relates_to [[alertmanager-enable]]
- relates_to [[volsync-backup]]

## Identified consumers

- 2026-05-20 — `kubernetes/apps/default/isponsorblocktv`: the `ctrld` DoH sidecar's pod `dnsConfig.nameservers` lists ${CLUSTER_DNS_IP} as a second nameserver so `ctrld`'s OS-upstream fallback resolves via cluster DNS (CoreDNS pins `clusterIP: 10.245.0.10` in `kubernetes/apps/kube-system/coredns/app/helmrelease.yaml`). The IP is now duplicated across these two manifests — first concrete case for `${CLUSTER_DNS_IP}` substitution. Only changes if the CoreDNS `clusterIP` or the Talos `serviceSubnets` (`10.245.0.0/16`) changes.


## Implementation (2026-05-22)

Implemented via commit 925b3cfd4 and 4da7cc2a5. The cluster-settings ConfigMap now defines ${PUBLIC_DOMAIN}, ${TIMEZONE}, ${NAS_IP}, ${ENVOY_INTERNAL_IP}, ${K8S_GATEWAY_IP}, ${PLEX_IP}, ${LAN_SUBNET}, ${ROUTER_IP}, ${LB_IP_POOL_START}, ${LB_IP_POOL_STOP}, ${IOT_SUBNET}, ${POD_CIDR}, ${SVC_CIDR}, and ${CLUSTER_DNS_IP}. The root cluster-apps Kustomization injects postBuild.substituteFrom referencing both cluster-settings and cluster-secrets. Hardcoded domain, timezone, and IP references across app manifests have been migrated to use these variables. The GitHub commit-status alert (alerts/github/) was also landed as part of the components/common Kustomize Component.

Deferred items:
- Shared OCIRepository for bjw-s app-template (repos/app-template/) — deferred to a follow-up
- Alertmanager integration — deferred pending alertmanager-enable roadmap item
