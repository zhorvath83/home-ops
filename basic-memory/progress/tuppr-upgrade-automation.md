---
title: tuppr-upgrade-automation
type: progress
permalink: home-ops/docs/progress/tuppr-upgrade-automation
topic: Tuppr-based Talos + Kubernetes upgrade automation (single-node)
status: completed
priority: medium
scope: Implement AD-019 by introducing home-operations/tuppr under kubernetes/apps/system-upgrade/tuppr/
  (mirroring upstream onedr0p layout) to GitOps-manage Talos OS and Kubernetes upgrades
  on single Talos control-plane node k8s-cp0. Replace manual just talos upgrade-node
  / upgrade-k8s with declarative TalosUpgrade and KubernetesUpgrade CRs tracking Renovate-pinned
  TALOS_VERSION (v1.13.2) and KUBERNETES_VERSION (v1.36.1) in .mise.toml. Just recipes
  remain as documented emergency-manual fallback.
rationale: 'Closes AD-019 (active, 2025-10-01) execution item — writing the Tuppr
  Plan resources and wiring them into Flux. Current manual upgrade flow violates GitOps
  source-of-truth principle for steady-state cluster configuration. Tuppr v0.2.0 introduced
  explicit single-node support (PR #99 + PR #175 PriorityClassName fix, dedicated
  single-node integration test) and chart-native monitoring (ServiceMonitor, PrometheusRule,
  dashboards) that slots into existing kube-prometheus-stack + Grafana sidecar-discovery.
  Per-upgrade downtime (~5-10 min) equivalent to manual flow.'
related_areas:
- talos-cluster
- flux-gitops
- k8s-workloads
- volsync-backup
- observability
tags:
- progress
- tuppr
- talos
- kubernetes
- upgrades
- single-node
- gitops
---

## Completed — 2026-05-23

All 8 phases of the implementation plan have been executed and committed (52d02de43). Summary:

- **Namespace + Kustomization**: `system-upgrade` namespace with prune:disabled annotation, top-level kustomization wiring into cluster-apps root Flux Kustomization.
- **Controller**: Tuppr v0.1.35 HelmRelease + OCIRepository under `tuppr/app/`, single-node values (`replicaCount: 1`, monitoring opt-in, `grafanaOperator.enabled: false` for sidecar-discovery).
- **TalosUpgrade CR**: `tuppr/upgrades/talosupgrade.yaml` with `policy.placement: soft`, `rebootMode: powercycle`, health checks gating on Flux Kustomization/HelmRelease Ready + cilium + cloudflare-tunnel.
- **KubernetesUpgrade CR**: `tuppr/upgrades/kubernetesupgrade.yaml` with explicit `spec.talosctl.image.tag` pin (required for single-node — controller defaults to K8s version tag which is invalid for talosctl).
- **Flux wiring**: Two Kustomizations (`tuppr` wait:true, `tuppr-upgrades` dependsOn + wait:false) in `tuppr/ks.yaml` with healthCheckExprs.
- **Renovate refactor**: Talos datasource migrated from `github-releases` to `custom.talos-factory`; Kubernetes datasource migrated from `github-releases` to `docker depName=ghcr.io/siderolabs/kubelet`. Groups and prBodyNotes updated to match.
- **Just recipes**: `upgrade-node` and `upgrade-k8s` doc annotations updated to reference Tuppr CRs as steady-state.
- **CRD bootstrap audit**: Tuppr CRDs NOT pre-bootstrapped (follows onedr0p/szinn pattern — dependsOn + healthCheckExprs is sufficient). Follow-up roadmap item `crd-bootstrap-coverage` created for a broader audit.

### Renovate datasource changes
| Location | Old | New |
|---|---|---|
| `kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml` spec.talos.version | N/A (new file) | `custom.talos-factory depName=siderolabs/talos` |
| `kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml` spec.kubernetes.version | N/A (new file) | `docker depName=ghcr.io/siderolabs/kubelet` |
| `kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml` spec.talosctl.image.tag | N/A (new file) | `custom.talos-factory depName=siderolabs/talos` |
| `.mise.toml` TALOS_VERSION | `github-releases depName=siderolabs/talos` | `custom.talos-factory depName=siderolabs/talos` |
| `.mise.toml` KUBERNETES_VERSION | `github-releases depName=kubernetes/kubernetes` | `docker depName=ghcr.io/siderolabs/kubelet` |
| `.renovate/groups.json5` Talos group | `github-releases` only | `custom.talos-factory, docker, github-releases` |
| `.renovate/prBodyNotes.json5` Talos reminder | `matchDatasources` missing | Added `custom.talos-factory, docker` |
| `kubernetes/apps/system-upgrade/tuppr/app/ocirepository.yaml` | N/A (new file) | `registryUrl=https://ghcr.io/home-operations/charts chart=tuppr` |
# Tuppr-based Talos + Kubernetes upgrade automation (single-node)

## Metadata (observation-form, schema validation)
- [topic] Tuppr-based Talos + Kubernetes upgrade automation (single-node)
- [status] completed
- [priority] medium
## Scope
Implement AD-019 (`docs/decisions/ad-019-tuppr-system-upgrade`, decided 2025-10-01) by introducing the `home-operations/tuppr` controller into the cluster under a new `system-upgrade` namespace, mirroring the upstream onedr0p layout (`kubernetes/apps/system-upgrade/tuppr/{app,upgrades}`). Declarative `TalosUpgrade` and `KubernetesUpgrade` CRs replace the operator-driven `just talos upgrade-node` / `just talos upgrade-k8s` recipes (kubernetes/talos/mod.just:348-362) for steady-state upgrades on the single Talos control-plane node `k8s-cp0`. Target versions track the Renovate-pinned `TALOS_VERSION` (v1.13.2, .mise.toml:6) and `KUBERNETES_VERSION` (v1.36.1, .mise.toml:8). The Just recipes stay as documented emergency-manual fallback.

## Rationale
AD-019 already fixed the controller choice (Tuppr over k3s-flavoured system-upgrade-controller). This roadmap closes AD-019's open execution item: writing the Tuppr Plan resources and wiring them into Flux. The current manual upgrade flow violates the root-CLAUDE.md GitOps principle for "steady-state cluster configuration". Tuppr v0.2.0 introduced explicit single-node support (PR #99 + PR #175 — PriorityClassName fix; dedicated `Context("Single node upgrade", …)` integration test at `test/integration/talosupgrade_test.go:60`) and ships chart-native monitoring (`monitoring.serviceMonitor`, `monitoring.prometheusRule`, `monitoring.dashboards`), which slots into the repo's existing kube-prometheus-stack + sidecar-discovery Grafana pattern. Per-upgrade downtime (~5-10 min while the only node drains and reboots) is equivalent to the current manual flow.

## Evidence base (verbatim sources)
- **AD-019** (active, 2025-10-01): "Replace the current system-upgrade-controller with bjw-s tuppr." Tradeoff noted: "Existing SUC Plan resources do not migrate 1:1 — new Tuppr Plan resources have to be written." No existing SUC Plan resources to migrate in this repo, so the migration cost is just writing the new CRs.
- **Upstream layout (onedr0p/home-ops main)**: `kubernetes/apps/system-upgrade/` houses `namespace.yaml`, a top-level `kustomization.yaml` (`namespace: system-upgrade`, `components: [../../../components/alerts]`, `resources: [namespace.yaml, tuppr/ks.yaml]`), and a `tuppr/` subtree. `tuppr/ks.yaml` defines **two** Flux Kustomizations: `tuppr` (path `./tuppr/app`) and `tuppr-upgrades` (path `./tuppr/upgrades`, `dependsOn: [tuppr]`, `wait: false`). `tuppr/app/kustomization.yaml` resources: `helmrelease.yaml`, `ocirepository.yaml` (chartRef to a separate OCIRepository CR). HelmRelease values (multi-node): `replicaCount: 2`, `monitoring.{serviceMonitor,prometheusRule,dashboards}.enabled: true`, `monitoring.dashboards.grafanaOperator.enabled: true`.
- **PR #99 + PR #175 (Release 0.2.0)**: "fixes an issue where single node clusters would fail to talos upgrade by implementing logic to try to account for single node clusters and set PriorityClassName"; also introduces "configure drain behavior", "prevent talos and kube upgrades running at the same time", and maintenance windows.
- **Issue #65** (closed, linked PR #99): TLS expired cert on the single node caused the controller to silently mark "0 nodes upgraded". Mitigation: audit Talos PKI freshness before each upgrade window.
- **TalosUpgrade CRD** (`config/crd/bases/tuppr.home-operations.com_talosupgrades.yaml` at main): `spec.talos.version` required (semver pattern). `spec.parallelism` defaults to 1. `spec.policy.placement` enum is `hard` | `soft` (default `soft`) — controls how strictly upgrade jobs avoid the target node. `spec.policy.rebootMode` enum is `default` | `powercycle` (default `default`). `spec.policy.timeout` defaults to `30m`. `spec.drain.{deleteLocalData,disableEviction,force,ignoreDaemonSets,skipWaitForDeleteTimeout}` map directly to kubectl drain flags. `spec.healthChecks[]` are CEL expressions over arbitrary k8s resources, with required `apiVersion` + `kind` + `expr`. `spec.nodeSelector` is a standard LabelSelector. `spec.maintenance.windows[]` accepts 5-field cron `start` + `duration` + IANA `timezone`. `spec.talosctl.image` defaults to `ghcr.io/siderolabs/talosctl:<target-version>`.
- **KubernetesUpgrade CRD**: `spec.kubernetes.version` required (semver). `spec.kubernetes.endpoint` overrides the apiserver URL (defaults to in-cluster ClusterIP, which bypasses CoreDNS — keep default). `spec.kubernetes.imageRepository` overrides the registry+path prefix for component images. **No `drain`, `parallelism`, `policy` or `nodeSelector` field** — the Talos-side `talosctl upgrade-k8s` flow handles rolling component updates internally. `spec.healthChecks[]` and `spec.maintenance` are the same shape as for TalosUpgrade.
- **Schematic preservation**: TalosUpgrade has **no** `spec.talos.schematic` field. The controller infers the factory schematic ID from the node's running `machine.install.image`. CHANGELOG references node annotations `tuppr.home-operations.com/schematic` and `tuppr.home-operations.com/factory-url` as optional per-node overrides. For `k8s-cp0`, `kubernetes/talos/machineconfig.yaml.j2` renders `factory.talos.dev/metal-installer/<schematic-id>:<TALOS_VERSION>`, so the i915 + intel-ucode + mei extensions in `kubernetes/talos/schematic.yaml` are preserved automatically across tuppr-driven upgrades.
- **Helm chart**: `oci://ghcr.io/home-operations/charts/tuppr`. Chart and app version in lockstep (latest 0.1.35, 2026-05-18). Default `priorityClassName: system-node-critical`, leader-election on, control-plane tolerations on, RBAC on, validating webhook on `:9443`. ServiceMonitor disabled by default — opt-in via `monitoring.serviceMonitor.enabled`.

## Architecture decisions
- **New namespace `system-upgrade`** (not `kube-system`). Matches upstream onedr0p convention and the still-proposed `namespace-split` roadmap's intent. Prevents tuppr's drain/job activity from polluting the platform namespace owned by Cilium, CoreDNS and democratic-csi.
- **Placement**: `kubernetes/apps/system-upgrade/` (new app subtree). Add `./system-upgrade/` to the cluster-apps root Flux `Kustomization` once the subtree exists (`kubernetes/flux/cluster/apps.yaml` or equivalent — verify exact entry-point file at implementation time; the repo currently lists `kubernetes/apps/<area>` via cluster Kustomization).
- **Two Flux Kustomizations** in `tuppr/ks.yaml`:
  - `tuppr` — controller only, path `./kubernetes/apps/system-upgrade/tuppr/app`, `wait: true` (default), HelmRelease health check.
  - `tuppr-upgrades` — `TalosUpgrade` + `KubernetesUpgrade` CRs, path `./kubernetes/apps/system-upgrade/tuppr/upgrades`, `dependsOn: [{ name: tuppr }]`, `wait: false`. Critical: `wait: false` so a long-running upgrade-in-progress state never blocks Flux reconciliation of unrelated apps.
- **Chart reference**: separate `OCIRepository` CR (`tuppr/app/ocirepository.yaml`) + HelmRelease `spec.chartRef: { kind: OCIRepository, name: tuppr }`. Matches the onedr0p layout and the broader bjw-s pattern; lets Renovate annotate the chart version on the OCIRepository tag.
- **No `dependsOn: [cilium, coredns]`** on the `tuppr` Kustomization. The controller must remain operable when those components are exactly the thing that needs a Talos upgrade fix.
- **Version source of truth**: `.mise.toml` stays canonical for talosctl client + emergency Just recipes. TalosUpgrade.spec.talos.version and KubernetesUpgrade.spec.kubernetes.version are independent declarations updated by the same Renovate annotation regex.

- **Monitoring opt-in: all-in from first MR** (chosen 2026-05-20). `monitoring.serviceMonitor.enabled: true`, `monitoring.prometheusRule.enabled: true`, `monitoring.dashboards.enabled: true` with `grafanaOperator.enabled: false` (sidecar-discovery path). Rationale: alert coverage on `tuppr_upgrade_failed_total`-style series must be live from the first real upgrade, not added retroactively. Pre-merge mitigation for the dashboards-without-Grafana-Operator path: `helm template --dry-run` against the rendered HelmRelease values locally and verify the manifest contains ConfigMaps with the `grafana_dashboard: "1"` label and NOT `GrafanaDashboard` CRs. If the chart only emits CRs in this mode, drop `monitoring.dashboards.enabled` to `false` and open a follow-up.

## Implementation plan

### Phase 0 — Pre-flight (no code changes)
- Verify single-node Ready, expected versions: `kubectl get node`, `talosctl -n k8s-cp0 version`, `kubectl version` should match `.mise.toml` pins (v1.13.2 / v1.36.1).
- Talos PKI freshness (Issue #65 mitigation): `talosctl -n k8s-cp0 health` clean; if client cert within 30 days of expiry, regenerate `talosconfig` via `just talos gen-talosconfig` first.
- Confirm schematic-preservation pre-condition: `just talos machine-image k8s-cp0` must return a string matching `factory.talos.dev/metal-installer/<id>:v1.13.2`. Tuppr will reuse this image URL for the upgrade; if the node was ever re-bootstrapped with a vanilla `ghcr.io/siderolabs/installer`, the i915 + ucode + mei extensions would be dropped on first tuppr-driven upgrade.
- Snapshot rendered machineconfig locally for rollback reference (do NOT commit — contains derived secrets): `just talos render-config k8s-cp0 > ${TMPDIR}/k8s-cp0-pre-tuppr.yaml`.

### Phase 1 — Subtree scaffolding
Create the following files under `kubernetes/apps/system-upgrade/`:
- `namespace.yaml` — bare `v1 Namespace` named `system-upgrade` with the repo's standard labels (mirror an existing namespace.yaml, e.g. `kubernetes/apps/external-secrets/namespace.yaml`).
- `kustomization.yaml` — top-level: `namespace: system-upgrade`, `resources: [./namespace.yaml, ./tuppr/ks.yaml]`, `components: [<flux-alerts component path used by sibling areas>]` (look up the exact relative path used by `kubernetes/apps/kube-system/kustomization.yaml:components` and copy).
- `tuppr/ks.yaml` — two Flux Kustomizations `tuppr` and `tuppr-upgrades` per the onedr0p layout described above. Use the schema URL header already standard in this repo (`yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json`). Add a `healthCheckExprs` block on the `tuppr` Kustomization keying off the HelmRelease Ready condition (pattern as in `kubernetes/apps/external-secrets/onepassword-connect/ks.yaml`).

### Phase 2 — Controller install
Under `tuppr/app/`:
- `kustomization.yaml` — `resources: [./helmrelease.yaml, ./ocirepository.yaml]`.
- `ocirepository.yaml` — `source.toolkit.fluxcd.io/v1 OCIRepository`, name `tuppr`, url `oci://ghcr.io/home-operations/charts/tuppr`, `spec.ref.tag: 0.1.35` with inline annotation `# renovate: datasource=docker depName=ghcr.io/home-operations/charts/tuppr versioning=helm` (the existing OCI custom manager in `.renovate/customManagers.json5:5-13` matches `oci://<dep>:<ver>` patterns; verify the regex picks up the OCIRepository `tag` form too, otherwise add an inline annotation that the second customManager — line 14-28 — will catch by datasource/depName pair).
- `helmrelease.yaml` — name `tuppr`, `spec.chartRef: { kind: OCIRepository, name: tuppr }`, `spec.interval: 1h`. Values (deviations from chart default only):
  - `replicaCount: 1` — single-node, do not over-provision.
  - `monitoring.serviceMonitor.enabled: true` — kube-prometheus-stack is already in-cluster (`kubernetes/apps/observability/kube-prometheus-stack`).
  - `monitoring.prometheusRule.enabled: true` — adopt the chart-provided rules; reduces home-grown rule churn.
  - `monitoring.dashboards.enabled: true`, `monitoring.dashboards.grafanaOperator.enabled: false` — this repo uses sidecar-discovery, not the Grafana Operator (confirm by re-reading the observability area-reference or the Grafana HelmRelease values). The chart should then publish dashboards as ConfigMaps with the `grafana_dashboard: "1"` label.
  - Leave `priorityClassName: system-node-critical` at chart default. **Do not override** — PR #175's single-node fix depends on this priority class.
  - Webhook on `:9443` — verify no Cilium baseline policy blocks apiserver → webhook traffic; the chart's Service should already expose this.

### Phase 3 — TalosUpgrade CR
File: `kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml`. Key fields:
- `spec.talos.version: v1.13.2` annotated `# renovate: datasource=github-releases depName=siderolabs/talos` (matches `.mise.toml:5-6`).
- `spec.parallelism: 1` (explicit even though default).
- `spec.policy.placement: soft` — **mandatory for single-node**. With `hard`, the tuppr-spawned upgrade job cannot avoid the only node and fails immediately.
- `spec.policy.rebootMode: powercycle` — matches the existing `just talos upgrade-node` semantics (mod.just:352, `-m powercycle`).
- `spec.policy.stage: false`, `spec.policy.timeout: 30m`, `spec.policy.force: false`, `spec.policy.debug: false` (override chart default `debug: true` for steady-state).
- `spec.drain.ignoreDaemonSets: true`, `spec.drain.force: true`, `spec.drain.deleteLocalData: true`, `spec.drain.disableEviction: false` — standalone pods are not expected, but `force: true` covers the unexpected case; `deleteLocalData: true` accepts that emptyDir-using pods (download-tools scratch, prometheus WAL if not on PVC) will lose state during the reboot anyway.
- `spec.healthChecks` — minimum gate set:
  - `kustomize.toolkit.fluxcd.io/v1 Kustomization` ALL Ready: `expr: object.status.conditions.filter(c, c.type == 'Ready').all(c, c.status == 'True')`, `timeout: 5m`. Guards against starting an upgrade while Flux is mid-reconcile.
  - `helm.toolkit.fluxcd.io/v2 HelmRelease` ALL Ready: same expr shape, `timeout: 5m`.
  - Named: `kube-system / cilium` HelmRelease Ready and `networking / cloudflare-tunnel` HelmRelease Ready. These two are the upgrade-blast-radius gate (no CNI ⇒ no recovery; no tunnel ⇒ no remote console).
- `spec.maintenance.windows`: omit initially — manual trigger via Renovate-MR merge. Add a window only after one or two successful manual cycles, if upgrades should be deferred to off-hours.
- `spec.nodeSelector: {}` — explicit empty selector documents the single-node intent.

### Phase 4 — KubernetesUpgrade CR
File: `kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml`. Key fields:
- `spec.kubernetes.version: v1.36.1` annotated `# renovate: datasource=github-releases depName=kubernetes/kubernetes` (matches `.mise.toml:7-8`).
- `spec.healthChecks`: identical to TalosUpgrade — keep them in sync (consider extracting via Flux post-build substitution if drift becomes a maintenance burden; defer for now per YAGNI).
- `spec.talosctl.image.tag: v1.13.2` with annotation `# renovate: datasource=github-releases depName=siderolabs/talos`. **Explicit pin required**: if omitted, the controller defaults the talosctl tag to the *target Kubernetes* version, which is invalid because `ghcr.io/siderolabs/talosctl` is tagged with Talos versions.
- `spec.kubernetes.endpoint`: omit (defaults to in-cluster apiserver ClusterIP — bypasses CoreDNS, which is exactly the right choice during an upgrade).
- `spec.kubernetes.imageRepository`: omit (the cluster already uses `registry.k8s.io` per `.renovate/customManagers.json5:29-37`).
- `spec.maintenance.windows`: omit initially.

And `upgrades/kustomization.yaml` — `resources: [./talosupgrade.yaml, ./kubernetesupgrade.yaml]`.

### Phase 5 — Cluster-apps root wiring
- Append `./apps/system-upgrade/` (or whatever entry-point pattern the repo's cluster Flux Kustomization uses — locate by reading `kubernetes/flux/cluster/` files at implementation time) so the new subtree becomes Flux-watched.
- Re-run `flux reconcile source git flux-system` (or wait the configured interval) and verify the new namespace + Kustomizations appear: `flux get kustomizations -A | grep tuppr`.

### Phase 6 — Renovate integration verification
- The three inline-annotated fields (TalosUpgrade.spec.talos.version, KubernetesUpgrade.spec.kubernetes.version, KubernetesUpgrade.spec.talosctl.image.tag) are picked up by the existing inline regex manager (`.renovate/customManagers.json5:14-28`).
- The OCIRepository `spec.ref.tag` for the Helm chart is picked up by the OCI regex manager (`.renovate/customManagers.json5:5-13`). The exact `oci://...:<tag>` form is matched directly; verify by inspecting the first Renovate MR.
- A Talos version bump produces ONE MR touching `.mise.toml` and `talosupgrade.yaml` and `kubernetesupgrade.yaml` (the talosctl tag), grouped by depName. A Kubernetes version bump produces ONE MR touching `.mise.toml` and `kubernetesupgrade.yaml`. Verify on the first incoming PRs.

### Phase 7 — Just recipe documentation update
- In `kubernetes/talos/mod.just`, prepend the `[doc('...')]` annotation on `upgrade-node` (line 346) and `upgrade-k8s` (line 358) with "Manual fallback only. Steady-state upgrades are GitOps-driven via TalosUpgrade/KubernetesUpgrade in kubernetes/apps/system-upgrade/tuppr."
- Do NOT remove the recipes — they are the recovery path if tuppr itself breaks (e.g. a controller bug introduced in a fast-cadence patch release).

### Phase 8 — Validation (acceptance criteria, loop-until-verified)
1. `flux get kustomization tuppr -n system-upgrade` Ready; `flux get kustomization tuppr-upgrades -n system-upgrade` Ready.
2. `flux get hr tuppr -n system-upgrade` Ready; `kubectl get pods -n system-upgrade -l app.kubernetes.io/name=tuppr` 1/1 Running; `kubectl logs` shows leader-election won.
3. `kubectl get talosupgrade,kubernetesupgrade -A` shows both resources accepted (Ready=True per the v0.1.35 `set Ready condition on resource acceptance` change).
4. ServiceMonitor scraped: `kubectl get servicemonitor -n system-upgrade tuppr` exists and metrics appear in Prometheus (Grafana Explore against the tuppr_* metric series).
5. PrometheusRule loaded: `kubectl get prometheusrule -n system-upgrade tuppr` exists; `promtool check rules` clean.
6. Grafana dashboard discovered: search for the chart-shipped tuppr dashboard in Grafana UI.
7. End-to-end upgrade dry-run: wait for the next Renovate MR that bumps either `siderolabs/talos` or `kubernetes/kubernetes`; merge during a manual maintenance window. Observe `kubectl get talosupgrade -w` (or KubernetesUpgrade): phase progresses `Pending` → `InProgress` → `Completed`. Node returns Ready, `talosctl version` / `kubectl version` reflect new pin, no degraded Flux resources.
8. Rollback path tested at least once: `kubectl delete talosupgrade <name>`, revert PR, manually re-run `just talos upgrade-node` to confirm fallback works.

## Risks and open questions
- **Issue #65 residual**: The Tuppr fix prevents the silent "0 nodes upgraded" outcome, but an expired Talos client cert still aborts the upgrade. Pre-flight cert check in Phase 0 is the durable mitigation. Follow-up: add a periodic Pushover alert (existing flux-provider-pushover) on `talosctl health` cert-expiry warning.
- **Drain blast on single node**: Every Talos OS upgrade drains the only node, evicting all non-DaemonSet workloads (Plex, Paperless, *arr, qBittorrent, Actual, Mealie, etc.) for ~5-10 min. Document in `docs/areas/talos-cluster` once landed. No mitigation possible without adding a second node — explicitly scoped out of this roadmap.
- **`policy.placement` cannot be `hard`**: code-review guardrail; the CR file itself documents it.
- **Tuppr release cadence high**: 4 patch releases in 5 days (0.1.32 → 0.1.35). Consider a `.renovate/autoMerge.json5` entry for `ghcr.io/home-operations/charts/tuppr` patch (z) bumps after CI passes, **only** after 2-3 manually-confirmed successful upgrade cycles. Defer.
- **`monitoring.dashboards.grafanaOperator.enabled: false` correctness**: the chart's dashboards-without-Operator path must emit ConfigMaps with the `grafana_dashboard: "1"` label for the existing Grafana sidecar to discover them. **Pre-merge gate**: `helm template` against the rendered HelmRelease values locally and grep the output for `kind: ConfigMap` + `grafana_dashboard:`. If the chart emits only `GrafanaDashboard` CRs in this mode, flip `monitoring.dashboards.enabled` to `false` in the same MR before merge and open a follow-up to track upstream support.
- **Schematic drift**: if a future `just talos apply-node` ever switches the install image away from `factory.talos.dev/metal-installer/*`, the next tuppr upgrade will silently drop kernel extensions. The Phase 0 check is mandatory before every upgrade cycle until automated.
- **`registry.k8s.io` overrides**: KubernetesUpgrade.spec.kubernetes.imageRepository is unset, so component images are pulled from `registry.k8s.io`. Ensure firewall / Cloudflare Tunnel egress allows this.

## Explicit scope-bounds (NOT in this roadmap)
- Multi-node behaviour and `spec.parallelism > 1` — out of scope for single-node; no longer tracked as a roadmap item.
- Custom CEL health checks per application (app-level decision; e.g. Paperless DB consistency before upgrade) — out of platform scope.
- Replacing the entire `just talos` recipe surface with tuppr — only `upgrade-node` and `upgrade-k8s` migrate. Bootstrap, reset, reboot, apply-config stay Just-driven.
- AlertmanagerConfig CR for upgrade failure routing — depends on `alertmanager-enable` roadmap landing first.
- Cluster-wide namespace reshuffle — see `namespace-split` roadmap.
## Reference implementations surveyed
- **onedr0p/home-ops** (multi-node Talos+Flux): `kubernetes/apps/system-upgrade/tuppr/{app,upgrades}` layout, `replicaCount: 2`, full `monitoring.*` opt-in including `grafanaOperator.enabled: true`, `chartRef: { kind: OCIRepository, name: tuppr }`, two Flux Kustomizations split as `tuppr` + `tuppr-upgrades` (`dependsOn`, `wait: false`). Adopted as the layout template; single-node deviations are documented inline in each Phase above (`replicaCount: 1`, `parallelism: 1`, `policy.placement: soft`, `monitoring.dashboards.grafanaOperator.enabled: false`).
- **heavybullets8/heavy-ops** (single-node Talos+Flux+SOPS): does NOT use tuppr at time of writing. Upgrades are handled out-of-band — no comparable reference for single-node tuppr config.
- **home-operations/cluster-template**: not directly inspectable via WebFetch from this session; not adopted as a primary reference.
- **No publicly-known single-node tuppr deployment** at survey time. The single-node specifics in this plan are derived from
  (a) tuppr's own integration test at `test/integration/talosupgrade_test.go:60` (`Context("Single node upgrade", …)`),
  (b) the upstream commit-trail (PR #99, PR #175, Issue #12, Issue #65),
  (c) the CRD schema's enum semantics — specifically that `spec.policy.placement: hard` would make the upgrade job unschedulable on the only node.
  This is an acknowledged risk: the integration test is shallow (asserts finalizer + status phase only), so the first real upgrade is also the first end-to-end validation. Phase 0 + Phase 8 mitigate by gating execution behind PKI freshness, schematic-preservation, and a tested rollback to `just talos upgrade-node`.

## Why this supersedes earlier hesitation
An earlier read of the tuppr changelog and Issue #12 left an impression that single-node support was an open feature gap. The current evidence base reverses that: Issue #12 is CLOSED, PR #99 + PR #175 (Release 0.2.0) explicitly added the single-node code path and the `Context("Single node upgrade", …)` integration test, and the regression in Issue #65 is also CLOSED. AD-019 (active, 2025-10-01) already records the controller choice; this roadmap removes the residual single-node uncertainty and lays out the implementation steps. No new architectural decision is required — this is the execution plan for AD-019.

## Related
- implements [[AD-019-tuppr-system-upgrade]]
- relates_to [[talos-cluster]]
- relates_to [[flux-gitops]]
- relates_to [[k8s-workloads]]
- relates_to [[volsync-backup]]
- relates_to [[observability]]
