---
title: crd-bootstrap-coverage
type: roadmap
permalink: home-ops/docs/roadmap/crd-bootstrap-coverage
topic: Audit CRD bootstrap coverage — ensure all CR kinds used in the repo have their
  CRDs available before Flux reconciles the CRs that reference them
status: proposed
priority: medium
scope: Audit every CR kind declared in kubernetes/apps/ against the CRD sources that
  make them available (bootstrap helmfile, HelmRelease install.crds, Flux native CRDs,
  GA APIs). Identify gaps where a CR could be applied before its CRD exists, causing
  transient reconciliation failures. Decide which gaps warrant pre-installation in
  the bootstrap helmfile (00-crds.yaml) versus which are adequately guarded by dependsOn
  + healthCheckExprs chains.
rationale: 'The bootstrap helmfile (00-crds.yaml) currently pre-installs CRDs for
  envoy-gateway, kube-prometheus-stack, and grafana-operator — three of the ~12 CRD-backed
  workloads in the cluster. The remaining CR kinds (cert-manager, cilium, external-secrets,
  volsync, tuppr, snapshot-controller, etc.) rely on Flux HelmRelease install.crds:
  CreateReplace (injected cluster-wide) and dependsOn chains. This creates a race
  window on fresh bootstrap: if a Kustomization referencing a CR reaches the cluster
  before the HelmRelease that owns its CRD has completed install, the Kustomization
  will fail and retry until the CRD arrives. The race is self-healing but slows initial
  bootstrap and can confuse operators.'
related_areas:
- flux-gitops
- k8s-workloads
tags:
- roadmap
- crd
- bootstrap
- flux
- helmfile
---

# CRD bootstrap coverage audit

## Metadata (observation-form, schema validation)

- [topic] Audit CRD bootstrap coverage — ensure all CR kinds used in the repo have their CRDs available before Flux reconciles the CRs that reference them
- [status] done — continues [[crd-bootstrap-coverage]] (progress)
- [priority] medium

## Scope

Audit every CustomResource kind declared in kubernetes/apps/ against the CRD delivery mechanism that makes it available. The bootstrap helmfile (kubernetes/bootstrap/helmfile.d/00-crds.yaml) currently pre-installs CRDs for envoy-gateway, kube-prometheus-stack, and grafana-operator. The cluster-root Flux Kustomization (kubernetes/flux/cluster/ks.yaml) injects install.crds: CreateReplace into every HelmRelease, so CRDs are created during Helm install. The question is whether the dependsOn + healthCheckExprs chains are sufficient to prevent CR-before-CRD race conditions, or whether additional CRDs should be pre-installed in the bootstrap helmfile.

## Current state

### Bootstrap helmfile CRDs (00-crds.yaml)

| Chart | CR kinds provided | CR kinds consumed in repo |
|-------|-----------------|--------------------------|
| envoy-gateway | EnvoyProxy, GatewayClass, ClientTrafficPolicy, BackendTrafficPolicy, HTTPRoute, etc. | EnvoyProxy, ClientTrafficPolicy, BackendTrafficPolicy, EnvoyPatchPolicy, SecurityPolicy, Gateway, GatewayClass, HTTPRoute |
| kube-prometheus-stack | PrometheusRule, ServiceMonitor, PodMonitor, etc. | PrometheusRule, ServiceMonitor, PodMonitor |
| grafana-operator | GrafanaDashboard (CRD) | (no GrafanaDashboard CR in repo — sidecar-discovery path) |

### CR kinds used in kubernetes/apps/ without bootstrap CRD pre-install

| CR kind | CRD source (HelmRelease) | dependsOn chain? | Race risk |
|---------|------------------------|------------------|-----------|
| TalosUpgrade, KubernetesUpgrade | tuppr (system-upgrade) | Yes: tuppr-upgrades dependsOn tuppr, healthCheckExprs on HelmRelease Ready | Low — HelmRelease install creates CRDs before CRs are applied |
| ExternalSecret, ClusterSecretStore | external-secrets | Yes: onepassword-connect dependsOn external-secrets | Low — but ClusterSecretStore is in bootstrap resources.yaml.j2, applied before Flux |
| Certificate, ClusterIssuer | cert-manager | Yes: cert-manager is depended on by multiple apps | Medium — cert-manager CRDs must exist before Certificate CRs in cert-manager/ and external-secrets/ |
| CiliumNetworkPolicy, CiliumClusterwideNetworkPolicy, CiliumLoadBalancerIPPool, CiliumL2AnnouncementPolicy, CiliumCIDRGroup | cilium | Yes: cilium-config and cilium-netpols dependOn cilium | Medium — CiliumNetworkPolicy CRs in netpols/ depend on cilium CRDs |
| KopiaMaintenance | kopia (volsync) | Yes: volsync-maintenance dependsOn volsync | Low |
| Receiver, Provider (notification) | flux-notification (flux-system) | Flux native — installed during bootstrap | None |
| VolumeSnapshotClass | snapshot-controller | Yes: dependsOn snapshot-controller | Low |
| MutatingAdmissionPolicy, MutatingAdmissionPolicyBinding | Kubernetes 1.32+ GA | Native API — no CRD needed | None |

## Reference implementations

### onedr0p/home-ops

- **Bootstrap CRDs**: envoy-gateway, kube-prometheus-stack, cert-manager, external-secrets, rook-ceph. Does NOT pre-install tuppr CRDs.
- **CRD handling**: Uses helmfile postsync hooks with `until kubectl get crd ...` for Cilium and external-secrets CRDs. Does NOT pre-install tuppr CRDs — relies on Flux dependsOn chains.
- **tuppr**: No CRD bootstrap. The tuppr-upgrades Kustomization dependsOn tuppr, and tuppr healthCheckExprs wait for HelmRelease Ready. Self-healing race on fresh bootstrap.
- Source: <https://github.com/onedr0p/home-ops>

### bjw-s-labs/home-ops

- **tuppr**: NOT USED. No system-upgrade controller at all — manual talosctl upgrades on a multi-node cluster.
- **Bootstrap**: Unknown CRD pre-install strategy (repo uses Flux + Kustomize, likely relies on install.crds and dependsOn).
- Source: <https://github.com/bjw-s-labs/home-ops>

### billimek/k8s-gitops

- **Bootstrap CRDs**: Pre-installs CRDs for prometheus-operator, external-secrets, volsync, rook-ceph, cloudnative-pg, emqx-operator, envoy-gateway, node-feature-discovery, silence-operator, snapshot-controller, grafana-operator, AND **tuppr** in the bootstrap helmfile (00-crds.yaml).
- **tuppr**: CRDs pre-installed via helmfile. The bootstrap helmfile explicitly includes the tuppr chart with version 0.1.35 for CRD extraction.
- Source: <https://github.com/billimek/k8s-gitops/blob/master/setup/bootstrap/helmfile.d/00-crds.yaml>

### szinn/k8s-homelab

- **tuppr**: Uses tuppr v1alpha1 CRs (TalosUpgrade, KubernetesUpgrade) with custom.talos-factory datasource. No CRD bootstrap — relies on Flux dependsOn chains.
- **Bootstrap CRDs**: Uses a shared preset (github>home-operations/renovate-presets) for Renovate config. CRD pre-install strategy not visible in the tuppr subtree.
- Source: <https://github.com/szinn/k8s-homelab/tree/main/kubernetes/main/apps/system-upgrade/tuppr>

### buroa/k8s-gitops

- **tuppr**: Uses tuppr with v1alpha1 CRs (same pattern as onedr0p). No CRD bootstrap — relies on Flux dependsOn chains.
- **Renovate**: Talos group uses docker + github-releases datasources. Tuppr group exists for chart + controller image grouping.
- Source: <https://github.com/buroa/k8s-gitops/tree/main/kubernetes/apps/system-upgrade/tuppr>

## Options

1. **A — Status quo (no CRD bootstrap for tuppr)** — Keep relying on install.crds: CreateReplace + dependsOn + healthCheckExprs. The tuppr HelmRelease creates CRDs during install, and tuppr-upgrades waits for tuppr to be Ready. Self-healing on fresh bootstrap (Flux retries). No additional maintenance burden. Risk: transient reconciliation failures on fresh bootstrap, slower initial rollout.

2. **B — Add tuppr CRDs to bootstrap helmfile (billimek pattern)** — Add the tuppr chart to 00-crds.yaml for CRD extraction. Guarantees CRDs exist before any Flux Kustomization references them. Pro: eliminates race window entirely. Con: adds a version pin to maintain in the bootstrap helmfile (currently only 3 charts, adding a 4th increases bootstrap churn).

3. **C — Systematic audit + selective bootstrap (recommended)** — Audit all CR kinds vs CRD sources, add high-risk CRDs to bootstrap helmfile (cert-manager, cilium, tuppr), keep low-risk ones on install.crds path. This is the onedr0p approach (helmfile hooks for Cilium and external-secrets) extended to the other high-risk CRDs.

4. **D — Full bootstrap (all CRDs pre-installed)** — Add every CRD-backed chart to 00-crds.yaml. Maximum safety, maximum maintenance burden. Every chart version bump must be duplicated in the bootstrap helmfile.

## Risks and open questions

- [risk] **Bootstrap order**: The cluster bootstrap chain (kubernetes/bootstrap/mod.just) applies CRDs before apps. If the CRD helmfile is incomplete, apps that reference missing CRDs will fail until Flux reconciles. The existing 00-crds.yaml was originally designed for exactly this — pre-seeding CRDs that Flux would otherwise race to install.
- [risk] **cert-manager**: The highest-risk gap. Certificate and ClusterIssuer CRs are used across multiple apps (external-secrets, networking, observability). If cert-manager CRDs are not pre-installed, TLS certificate issuance will fail on fresh bootstrap until cert-manager HelmRelease completes.
- [risk] **Cilium**: CiliumNetworkPolicy CRs are used in netpols/. If Cilium CRDs are not pre-installed, network policies will fail to apply. However, onedr0p handles this with a helmfile postsync hook, not a CRD pre-install.
- [risk] **Maintenance cost**: Each chart added to 00-crds.yaml must have its version pinned and kept in sync with the HelmRelease version. Renovate manages both, but divergences can occur.

## Explicit scope-bounds (NOT in this roadmap)

- Changing the Flux reconciliation model (install.crds policy is cluster-wide and works for steady-state)
- Replacing the helmfile bootstrap chain with a different tool
- Adding helmfile postsync hooks for CRD waiting (onedr0p pattern) — separate concern from pre-installing CRDs

## Research Session (2026-05-23)

Four reference implementations audited for CRD bootstrap strategy:

| Repo | 00-crds.yaml charts | Postsync hooks | Key pattern |
|------|-----|------|------|
| onedr0p | 3 (envoy-gateway, kube-prometheus-stack, grafana-operator) | cilium CRD wait + network config apply; onepassword-connect CRD wait + ClusterSecretStore apply | Minimal CRD pre-install, postsync hooks bridge the gaps |
| bjw-s | 3 (same as onedr0p) | cilium CRD wait + config apply; onepassword-connect ClusterSecretStore apply | Same as onedr0p, no tuppr, no system-upgrade |
| billimek | 12 (envoy-gateway, kube-prometheus-stack, grafana-operator, external-secrets, volsync, rook-ceph, cloudnative-pg, emqx-operator, node-feature-discovery, silence-operator, snapshot-controller, **tuppr**) | None found (comprehensive CRD pre-install makes hooks unnecessary) | Aggressive CRD pre-install, maximum safety, maximum maintenance burden |
| szinn | 3 (envoy-gateway, kube-prometheus-stack, grafana-operator) | cilium CRD wait + config apply | Same 3-chart baseline, postsync hook for cilium only |

### Confirmed gaps in home-ops

1. **ClusterSecretStore in resources.yaml.j2 without ESO CRDs** — highest risk. onedr0p/bjw-s solve this with a postsync hook that waits for the ESO CRD then applies ClusterSecretStore. home-ops applies it before ESO CRDs exist.
2. **No cilium postsync hook** — medium risk. onedr0p/bjw-s/szinn all wait for cilium CRDs before applying network config. home-ops relies on Flux dependsOn only.
3. **No postsync hook mechanism at all** — the helmfile bootstrap has no hooks for CRD waiting. Every other reference repo uses them.
4. **cert-manager CRDs not pre-installed** — low risk, consistent with all reference repos (handled by needs chain ordering).
5. **tuppr CRDs not pre-installed** — low risk, only billimek pre-installs them. onedr0p/szinn use dependsOn + healthCheckExprs, same as home-ops.

### Cross-cutting observation

Every reference repo uses the same cluster-wide HelmRelease patch injecting install.crds: CreateReplace. The difference is entirely in the bootstrap phase: how CRDs are guaranteed to exist before Flux starts reconciling CRs. The two strategies are (a) pre-install more CRDs in 00-crds.yaml or (b) add postsync hooks to the helmfile apps phase. onedr0p/bjw-s/szinn use (b) for cilium and external-secrets; billimek uses (a) for everything.

## Implementation (2026-05-23)

### Audit findings

After detailed research and code review, the existing bootstrap is **much closer to the consensus pattern than the roadmap assumed**:

1. **Cilium postsync hook** — ALREADY EXISTS (CRD wait + config apply via kustomize). Matches onedr0p/bjw-s/szinn pattern.
2. **Onepassword-connect postsync hook** — ALREADY EXISTS (ClusterSecretStore apply). Missing only the ESO CRD wait step.
3. **ClusterSecretStore in resources.yaml.j2** — NOT PRESENT. Only 1PW Connect secrets are in resources.yaml.j2. The ClusterSecretStore is applied by the postsync hook.
4. **Bootstrap sequence** — `namespaces → resources → crds → apps`. Correct order: resources only contains Secrets (no CRD-dependent objects).
5. **00-crds.yaml** — 3 charts (envoy-gateway, kube-prometheus-stack, grafana-operator). Matches the 3/4 consensus.

### Change made

**01-apps.yaml**: Added `kubectl wait --for=create crd/clustersecretstores.external-secrets.io --timeout=2m` before the ClusterSecretStore apply in the onepassword-connect postsync hook. This is the only gap — the consensus pattern (onedr0p, bjw-s) explicitly waits for the ESO CRD before applying ClusterSecretStore.

### No changes needed

- 00-crds.yaml — stays at 3 charts
- resources.yaml.j2 — ClusterSecretStore not present, no change
- Bootstrap sequence — correct as-is
- Cilium postsync hook — already matches consensus
- cert-manager, tuppr, volsync — handled by needs chain and Flux dependsOn

### Status: DONE

The CRD bootstrap coverage audit identified one gap (ESO CRD wait in 1PW hook) and closed it. All other aspects already match the upstream consensus pattern.
