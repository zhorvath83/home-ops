---
title: cr-health-alerting
type: roadmap
permalink: home-ops/docs/roadmap/cr-health-alerting
topic: Cluster-wide custom-resource health alerting — surface silent CR failures and
  page on them through the existing in-cluster Alertmanager.
status: proposed
priority: high
scope: Make every operator-managed custom resource that exposes a health signal observable
  in Prometheus, and alert when any such CR leaves its healthy state. Prefer operator-native
  CR-health metrics where they exist; synthesize the rest from status.conditions via
  kube-state-metrics customResourceState. Detailed scope/depth is decided in a follow-up
  assessment — this note fixes the problem and the decision framework only.
rationale: Several operators reconcile silently — a CR can sit in a pending/error
  state with no visible signal unless its status.conditions are inspected directly.
  Recent days surfaced cases of CRs drifting into a stuck state unnoticed. Today only
  Flux (event-based), VolSync, and tuppr page on CR health; ESO, cert-manager, Grafana-operator,
  Gateway API, VolumeSnapshot, and Silence CRs have no alert at all.
related_areas:
- observability
- networking
- external-secrets
- flux-gitops
- iam
- k8s-workloads
principles:
- Operator-native CR-health metric is the preferred source where it exists — one PrometheusRule
  on the already-scraped metric, no kube-state-metrics config needed.
- Where the operator does NOT emit a CR-health metric, kube-state-metrics customResourceState
  synthesizes one from status.conditions — the cluster already runs this mechanism
  for Flux; extend it. This is more work and is the fallback path.
- 'Every alert must be evidence-backed: the metric must exist in Prometheus before
  the rule is written (verify via direct query and via the operator''s /metrics endpoint,
  as this assessment did) — never assume an operator emits a metric it does not.'
tags:
- roadmap
- observability
- alerting
- cr-health
---

# Cluster-wide custom-resource health alerting

## Metadata (observation-form, schema validation)

- [topic] Cluster-wide custom-resource health alerting — surface silent CR failures and page on them through the existing in-cluster Alertmanager
- [area] observability
- [status] proposed
- [priority] high
- [confidence] high
- [verified_at] 2026-07-27

## The problem

Operators reconcile custom resources asynchronously. A CR can reach a pending, failed, or
partially-applied state while its controller keeps running and no pod restarts. Without an
explicit read of `status.conditions` (or the operator's own health metric) the failure is
invisible — exactly the "silently stuck" pattern recently observed in the cluster.

Today only three paths page on CR health:

- **Flux** — event-based: `Alert` + `type: alertmanager` `Provider` → in-cluster Alertmanager (reconciliation failures).
- **VolSync** — metric-based: the `volsync` PrometheusRule on `volsync_volume_out_of_sync` / `volsync_missed_intervals_total` / `volsync_kopia_*`.
- **tuppr** — metric-based: the chart-shipped `tuppr` PrometheusRule on the upgrade-controller metrics.

**No alert exists** for: ExternalSecret / ClusterSecretStore, cert-manager Certificate /
ClusterIssuer, Grafana-operator CRs (Grafana / GrafanaDatasource / GrafanaDashboard /
GrafanaFolder), Gateway API CRs (Gateway / GatewayClass / HTTPRoute + the Envoy Gateway
attached policies), VolumeSnapshot / VolumeSnapshotContent, and Silence CRs.

## What to investigate (thoroughly, before implementation)

1. **Per-CR status model.** Each operator exposes health differently — top-level
   `status.conditions` (Flux, ESO, cert-manager, Grafana-operator, VolSync, tuppr,
   KopiaMaintenance), the Gateway API `parents[].conditions` model (HTTPRoute), the
   attached-policy `status.ancestors[].conditions` model (BackendTLSPolicy,
   BackendTrafficPolicy, SecurityPolicy, EnvoyExtensionPolicy, ClientTrafficPolicy,
   EnvoyPatchPolicy), boolean fields (`status.readyToUse` on VolumeSnapshot), or no
   status at all (Flux Alert/Provider, EnvoyProxy, Probe, Silence). Map every CR kind to
   its model.

2. **Operator-native CR-health metric availability.** For each CR-owning operator, confirm
   via the operator's own `/metrics` endpoint (not via Prometheus assumptions) whether it
   emits a CR-health metric. This is the preferred source — if present, only a
   PrometheusRule is needed.

3. **kube-state-metrics customResourceState coverage.** KSM v2.19.1 already runs with
   `customResourceState` enabled, but the current config covers only three Flux CRDs
   (Kustomization, GitRepository, HelmRelease) via the `gotk_resource_info` metric — and
   notably OMITS `OCIRepository` (36 instances). Determine which additional CRDs need
   customResourceState entries and how to express the ancestors-conditions model in the
   KSM labelsFromPath syntax (the hardest sub-problem).

4. **Gateway API ancestors-conditions feasibility.** The attached-policy CRs publish
   Accepted/Programmed/ResolvedRefs under `status.ancestors[].conditions`, indexed per
   ancestor Gateway. Verify KSM customResourceState can emit one series per
   (policy, ancestor, condition) and that an alert can be written on it without per-route
   label explosion.

5. **Existing routing and precedent.** All alerts must route through the existing
   in-cluster Alertmanager (pushover default receiver, blackhole for InfoInhibitor/Watchdog).
   Follow the existing per-operator PrometheusRule pattern (volsync, tuppr, oom-alert,
   hubble-dns-exfil, hubble-policy-deny, blackbox-exporter) — co-locate each rule with the
   area it alerts on, not in a central mega-rule.

6. **Status-less CRs.** CRs with no `status.conditions` (Flux Alert/Provider, EnvoyProxy,
   Probe, Silence) cannot be alerted via conditions. Evaluate the weak fallback signal
   `controller_runtime_reconcile_errors_total` (operator-level, not CR-specific) and
   Kubernetes events — flag these as low-priority / accept-the-gap rather than force a
   noisy rule.

## Decision framework (principles, locked)

- **Operator-native CR-health metric is the preferred source where it exists.** One
  PrometheusRule on the already-scraped metric. No kube-state-metrics config, no synthesis.
- **kube-state-metrics customResourceState is the fallback** for operators that do not emit
  a CR-health metric but whose CRs have `status.conditions`. The mechanism is already
  operational — extend it.
- **Evidence-backed only.** Verify the metric exists in Prometheus (and at the operator's
  `/metrics` endpoint) before writing any rule. Do not assume.
- **Per-operator PrometheusRules** following the existing volsync/tuppr/oom precedent — not
  a single cluster-wide mega-rule.
- **Flux CR alerting stays event-based** (Alert + Provider → Alertmanager) as the primary
  paging path; the `flux_resource_info` metric is for dashboards, not paging, to avoid
  duplicate noise.
- **Route through the existing in-cluster Alertmanager** — no new notification path.
- **Gateway API ancestors-conditions coverage is in scope** (target: full), but its
  feasibility is the key technical risk to validate in the follow-up assessment.

## Evidence snapshot (2026-07-27 assessment)

This is the starting state a future assessment continues from — recorded so the framework
is not re-derived from assumptions.

### Every audited CR was healthy at assessment time

All 116 CRDs were enumerated and every live CR with a status signal was healthy
(`Ready=True` / `Accepted=True` / `Available=True` / `Reconciled=True` /
`Succeeded`). 62 Kustomization (Healthy=True), 51 HelmRelease (UpgradeSucceeded),
36 OCIRepository + 1 GitRepository (Ready), 62 ExternalSecret (SecretSynced),
ClusterSecretStore (Valid), 19 ReplicationSource (active, latestMoverStatus.result=Successful),
19 ReplicationDestination (`*-bootstrap` WaitingForManual / restore-once — the repo's
intended bootstrap pattern, NOT a failure), Grafana (GrafanaReady=True) + all
Datasource/Dashboard/Folder (ApplySuccessful), 2 Gateway (Accepted+Programmed) + 28 HTTPRoute
(Accepted+ResolvedRefs) + all Envoy policies (Accepted via ancestors), 2 Certificate (Ready)
+ 2 Order (valid) + ClusterIssuer (ACMEAccountRegistered), TalosUpgrade + KubernetesUpgrade
(Completed), KopiaMaintenance (MaintenanceHealthy=OperatingNormally), 23 VolumeSnapshot +
23 VolumeSnapshotContent (ready=true, err={}). No invisible-stuck CR at assessment time —
the problem is structural (no alert), not a current incident.

### Status-less CR types (no condition to alert on)

Flux `Alert` / `Provider` (24+24, by design), `EnvoyProxy` (2, config-ref object — the
Gateway does not write status), `Probe` (2, blackbox — health comes from probe metrics),
`Silence` (1, silence-operator writes no status.conditions).

### Operator-native CR-health metrics confirmed present (category A — only a PrometheusRule needed)

- Flux: `flux_resource_info` (199 series, kinds = Alert, GitRepository, HelmRelease,
  Kustomization, OCIRepository, Provider, Receiver — covers OCIRepository too). Also the
  KSM-synthesized `gotk_resource_info` (114 series, 3 kinds only).
- ESO: `externalsecret_status_condition` (125 series, label `condition` + `status`) and
  `clustersecretstore_status_condition`, plus `externalsecret_sync_calls_error`.
- cert-manager: `certmanager_certificate_ready_status` and
  `certmanager_clusterissuer_ready_status`, plus
  `certmanager_certificate_expiration_timestamp_seconds` /
  `certmanager_certificate_renewal_timestamp_seconds`.
- VolSync: `volsync_volume_out_of_sync`, `volsync_missed_intervals_total`,
  `volsync_kopia_*` — already alerted.
- tuppr — already alerted.

### Operators confirmed NOT emitting a CR-health metric (category B — KSM customResourceState needed)

Verified by directly querying each operator's `/metrics` endpoint (not via Prometheus
assumptions):

- **grafana-operator** (`grafana-operator-metrics-service:9090`) — only
  `controller_runtime_*` / `go_*` / `process_*`. No `grafanadashboard_*` /
  `grafanadatasource_*` / status-condition metric. Grafana-operator CRs have
  status.conditions (GrafanaReady, DatasourceSynchronized, DashboardSynchronized,
  FolderSynchronized) → KSM customResourceState can synthesize.
- **envoy-gateway** (`envoy-gateway.networking:19001`) — emits
  `resource_apply_total`, `status_update_total`, `xds_snapshot_*`,
  `controller_runtime_reconcile_errors_total{controller="gatewayapi-..."}` but NO
  `gateway_*` / `httproute_*` / `policy_*` / Accepted / Programmed metric. Gateway API
  CR health is not metric-exposed → KSM customResourceState (top-level for Gateway/
  HTTPRoute, ancestors for the attached policies).
- **silence-operator** — the `Silence` CR has no `status.conditions` at all; there is
  nothing to synthesize. Weak fallback only.

### Mechanism already in place

- kube-state-metrics v2.19.1 with `--custom-resource-state-config-file` mounted from
  ConfigMap `kube-prometheus-stack-kube-state-metrics-customresourcestate-config`, sourced
  from the kube-prometheus-stack HelmRelease values (`kube-state-metrics.customResourceState`).
  Currently covers only Kustomization / GitRepository / HelmRelease. **OCIRepository is
  missing** from it (though `flux_resource_info` covers it natively — a consistency point
  to resolve: single source of truth vs duplication).
- All CR-owning operators are already scraped (`up=1`): ServiceMonitors for grafana-operator,
  envoy-gateway, external-secrets, cert-manager, flux-operator, volsync, tuppr; PodMonitor for
  silence-operator. There is NO "just add a ServiceMonitor" shortcut — the missing piece is
  always either a PrometheusRule (A) or a KSM customResourceState entry (B), never a scrape.

### Existing custom PrometheusRules (precedent pattern to follow)

`observability/volsync`, `system-upgrade/tuppr` (chart-shipped),
`observability/oom-alert`, `observability/hubble-dns-exfil`,
`observability/hubble-policy-deny`, `observability/blackbox-exporter`. Each is a small
per-area PrometheusRule co-located with the component it alerts on.

## Open decisions (for the follow-up assessment)

These were discussed but intentionally NOT locked here — the follow-up assessment decides
them with a fresh pass:

- **Scope** — full coverage (all A+B, ancestors included) vs critical-platform-only vs
  largest-gaps-only. The B-category and especially the ancestors-conditions mapping carry
  the bulk of the work; scope trades effort against silent-failure risk.
- **B-category depth** — whether to cover VolumeSnapshot and KopiaMaintenance or leave them.
- **Gateway API ancestors-conditions feasibility** — confirm the KSM customResourceState
  mapping is practical before committing to full policy coverage.
- **KSM customResourceState single-source-of-truth** — reconcile the existing
  `gotk_resource_info` (3 Flux kinds) with the native `flux_resource_info` (7 kinds):
  drop the KSM Flux entries and rely on the operator metric, or keep both.
- **C-category (status-less CRs)** — accept the gap, or add weak operator-level
  reconcile-error alerts.

## Related

- relates_to [[observability]]
- relates_to [[networking]]
- relates_to [[external-secrets]]
- relates_to [[flux-gitops]]
- relates_to [[iam]]
- relates_to [[k8s-workloads]]
- continues [[alertmanager-introduction]]
