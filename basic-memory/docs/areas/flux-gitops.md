---
title: flux-gitops
type: area_reference
permalink: home-ops/docs/areas/flux-gitops
area: flux-gitops
status: current
confidence: high
verified_at: '2026-07-05'
summary: Flux runs via the Flux Operator pattern with a single FluxInstance CR declaring
  controllers, GitRepository sync, and root Kustomization. The cluster-apps Kustomization
  at kubernetes/flux/cluster/ks.yaml is the reconciliation root and injects shared
  HelmRelease defaults into every HelmRelease via a child-Kustomization patch. Per-namespace
  alerting goes to Pushover.
verified_against:
- kubernetes/apps/flux-system/flux-operator/app/helmrelease.yaml
- kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml
- kubernetes/apps/flux-system/flux-provider-pushover/
- kubernetes/components/flux-alerts/
- kubernetes/flux/cluster/ks.yaml
- kubernetes/CLAUDE.md
- .github/workflows/scanning-deprecated-kube-resources.yaml
- docs/flux-readme.md
drift_risk: Performance patches (concurrent counts, memory limits, OOMWatch, in-memory
  kustomize, DisableChartDigestTracking, CancelHealthCheckOnNewRevision) are inline
  patches in the FluxInstance HR — re-evaluate on operator upgrade or hardware change.
  MissingRollbackTarget recovery requires `helm uninstall` outside GitOps — pattern
  preserved here before docs/migration/STATUS.md (Phase 6) gets archived.
---

# flux-gitops — current state

## Metadata (observation-form, schema validation)

- [area] flux-gitops
- [status] current
- [confidence] high
- [verified_at] 2026-07-05

## Summary

The cluster runs Flux via the Flux Operator pattern: a single `FluxInstance` CR (in `kubernetes/apps/flux-system/flux-instance/`) declares the four controllers, GitRepository sync target, and root Kustomization. No classic `flux bootstrap` step. The Operator reconciles the FluxInstance.

The reconciliation root is `kubernetes/flux/cluster/ks.yaml` — a single `cluster-apps` Kustomization that scans `./kubernetes/apps` with `prune=true` and injects shared HelmRelease defaults into every HelmRelease via a child-Kustomization patch. Flux reconciliation alerts are delivered to Pushover through a native Flux `Provider` `type: alertmanager` (in `components/common/alerts/alertmanager/`) that posts to the in-cluster Alertmanager (`alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/`), which in turn routes to Pushover via its `AlertmanagerConfig`. The custom `flux-provider-pushover` relay app and the `flux-alerts`/`pushover` component bundle were retired 2026-07-05 by roadmap `alertmanager-introduction`. The GitHub commit-status Provider/Alert (`components/common/alerts/github/`) is unchanged.

## Components

- [component] intel-gpu-resource-driver — DRA driver DaemonSet in kube-system (OCI chart v0.10.1 from ghcr.io/intel), CDI paths at /run/cdi matching Talos defaults; apps reference GPU via shared components/gpu/ ResourceClaimTemplate

- [component] flux-operator — manages the FluxInstance lifecycle (kubernetes/apps/flux-system/flux-operator/)
- [component] flux-instance — declares controllers, sync target, and performance patches (kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml)
- [component] cluster-apps Kustomization — single root reconciler, `prune=true`, injects HelmRelease defaults via child-Kustomization patch (kubernetes/flux/cluster/ks.yaml)
- [component] alertmanager alerts component — per-namespace Flux `Provider` (`type: alertmanager`) + `Alert` bundle that posts Flux reconciliation errors into the in-cluster Alertmanager (kubernetes/components/common/alerts/alertmanager/). Wired into `components/common/alerts/kustomization.yaml` alongside `github`.
- [component] (Retired 2026-07-05) flux-provider-pushover — was a global custom Pushover relay deployment in flux-system; replaced by the alertmanager alerts component above.
- [component] Pluto deprecated-API scanning — weekly cron (Fri 00:00 UTC) + workflow_dispatch, `pluto detect-files -d kubernetes`, on-failure auto-creates GitHub issue assigned to repo owner (.github/workflows/scanning-deprecated-kube-resources.yaml)

## Claims (verified against repo)

- [claim] "Cluster-wide substitution variables are defined in the `cluster-settings` ConfigMap (`kubernetes/components/common/vars/cluster-settings.yaml`) and injected into every child Kustomization via a `postBuild.substituteFrom` patch on the root `cluster-apps` Kustomization — variables include ${PUBLIC_DOMAIN}, ${TIMEZONE}, ${NAS_IP}, ${ENVOY_INTERNAL_IP}, ${K8S_GATEWAY_IP}, ${PLEX_IP}, ${LAN_SUBNET}, ${POD_CIDR}, ${SVC_CIDR}, ${CLUSTER_DNS_IP}, and ${ROUTER_IP}" (evidence: repo, ref: kubernetes/components/common/vars/cluster-settings.yaml + kubernetes/flux/cluster/ks.yaml, verified: 2026-05-22)

- [claim] "Flux runs four controllers: source-controller, kustomize-controller, helm-controller, notification-controller — declared in FluxInstance.spec.values.instance.components" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:20-24, verified: 2026-05-19)
- [claim] "GitRepository sync points at <https://github.com/zhorvath83/home-ops.git>, ref refs/heads/main, path kubernetes/flux/cluster, 1h interval" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:25-30, verified: 2026-05-19)
- [claim] "Flux Operator manifests pinned to v0.49.0 with version constraint 2.x; Renovate-tracked via inline annotation" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:15-17, verified: 2026-05-19)
- [claim] "cluster-apps Kustomization in namespace flux-system has prune=true, interval=1h, scans ./kubernetes/apps via GitRepository sourceRef name=flux-system" (evidence: repo, ref: kubernetes/flux/cluster/ks.yaml:6-15, verified: 2026-05-19)
- [claim] "HelmRelease defaults are injected via a child-Kustomization patch on cluster-apps: install.crds=CreateReplace, install.strategy.name=RetryOnFailure, rollback.cleanupOnFail=true, timeout=10m, upgrade.cleanupOnFail=true, upgrade.crds=CreateReplace, upgrade.strategy.name=RemediateOnFailure, upgrade.remediation.remediateLastFailure=true, upgrade.remediation.retries=2 — per-HR overrides for these fields are anti-pattern" (evidence: repo, ref: kubernetes/flux/cluster/ks.yaml:16-51, verified: 2026-05-19)
- [claim] "FluxInstance applies performance patches via spec.values.instance.kustomize.patches: --concurrent=10 (then =20 for kustomize-controller), --requeue-dependency=5s, memory limit 2Gi for kustomize/helm/source controllers, in-memory kustomize builds (emptyDir medium=Memory), OOMWatch on helm-controller (95% threshold, 500ms interval), DisableChartDigestTracking, CancelHealthCheckOnNewRevision" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:34-107, verified: 2026-05-19)
- [claim] "FluxInstance disables cluster-level NetworkPolicy creation (instance.cluster.networkPolicy=false); the cluster-wide Cilium baseline allow-cluster-egress + allow-dns-egress applies instead" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:18-19, verified: 2026-05-19)
- [claim] "Recovery procedure for HRs stuck with MissingRollbackTarget or similar uninstall artefacts: `helm uninstall <release> -n <ns>` followed by `flux reconcile hr <name> -n <ns> --force`. Plain `flux reconcile` alone is insufficient" (evidence: behavior, ref: docs/flux-readme.md:50-59 + docs/migration/STATUS.md Phase 6, verified: 2026-05-19)
- [claim] "Alternative recovery when an HR is stuck mid-operation ('another operation (install/upgrade/rollback) is in progress') but a usable previous revision still exists: `helm history <release> -n <ns>` to list revisions, `helm rollback <release> <revision> -n <ns>` to revert, then `flux reconcile helmrelease <release> -n <ns>`. Use this before resorting to `helm uninstall` — the rollback path keeps history intact. External reference: <https://support.d2iq.com/hc/en-us/articles/8295311458964-Resolving-issues-with-HelmReleases-that-are-failed>" (evidence: behavior, ref: docs/helm-readme.md (deleted, migrated here), verified: 2026-05-20)
- [claim] "Operational entry points for Flux are encapsulated as `just k8s` recipes (flux-reconcile, flux-check, sync-hr/ks/es, sync, list-failed-hrs, restart-failed-hrs, apply-ks, delete-ks) in kubernetes/mod.just; documentation is the recipe set itself, not duplicated prose" (evidence: repo, ref: kubernetes/mod.just, verified: 2026-05-19)

## Drift Risk

- [drift] Performance patches in FluxInstance (concurrent counts, memory limits, OOMWatch parameters, in-memory kustomize, DisableChartDigestTracking, CancelHealthCheckOnNewRevision) are inline JSON patches inside the HelmRelease spec — re-evaluate on flux-operator-manifests upgrade or hardware/topology change
- [drift] MissingRollbackTarget recovery requires imperative `helm uninstall` outside the GitOps flow; the pattern is captured here as a claim but the detailed Phase 6 narrative lives in `docs/migration/STATUS.md` which is slated for archive/deletion
- [drift] HelmRelease defaults patch (in cluster-apps) is the single point of truth for shared install/rollback/upgrade behavior — per-HR overrides for those fields are flagged anti-pattern in `kubernetes/CLAUDE.md`, but enforced only by code review (no automated check)

## Open Questions / Gaps

- [gap] (Resolved 2026-07-05) Pushover provider model split: the former two-path model (`components/common/alerts/pushover/` per-namespace Alert+Provider+ExternalSecret bundle pointing at the standalone `flux-provider-pushover` relay app) was retired by roadmap `alertmanager-introduction`. Flux reconciliation alerts now route through a single native `type: alertmanager` Provider into the kube-prometheus-stack Alertmanager, which routes to Pushover via its AlertmanagerConfig + the observability `alertmanager` ExternalSecret (1Password `pushover` item). One path, one credential source.
- [gap] Live cluster verification (FluxInstance Ready, controllers running, GitRepository latest revision) not performed — repo evidence only

## Relations

- depends_on [[external-secrets]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- part_of [[home-ops-platform]]
- supersedes [[flux-readme]]

## Update 2026-07-05

Flux alerting migrated to Alertmanager. See roadmap alertmanager-introduction.

**Before**: Flux reconciliation errors paged through a custom self-authored relay (image `ghcr.io/zhorvath83/flux-provider-pushover`, a Deployment in flux-system, fed by a Flux generic Provider pointing at the relay Service) plus a per-namespace `flux-alerts`/`pushover` Alert+Provider+ExternalSecret bundle. Two Pushover paths, one maintained container image.

**After**: Flux reconciliation errors flow through a native Flux Provider of type alertmanager (`components/common/alerts/alertmanager/provider.yaml`, address `http://alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/`) plus an Alert covering FluxInstance/GitRepository/HelmRelease/HelmRepository/Kustomization/OCIRepository with the same exclusionList the relay used (github.com and raw.githubusercontent.com lookup, dial tcp timeout, waiting socket). The component is wired into `components/common/alerts/kustomization.yaml` alongside `github` and fans out to every namespace pulling in `components/common`. Alertmanager routes to Pushover via its AlertmanagerConfig (pushover receiver, HTML template, sendResolved) plus the observability `alertmanager` ExternalSecret (1Password `pushover` item, PUSHOVER_ALERTMANAGER_TOKEN and PUSHOVER_USER_KEY).

**Networking (AD-023 V3 baseline)**: the Flux notification-controller to Alertmanager:9093 east-west path is granted by a per-app CiliumNetworkPolicy (`kubernetes/apps/observability/kube-prometheus-stack/app/ciliumnetworkpolicy.yaml`, second document, `alertmanager` ingress from `flux-system/notification-controller`). The Alertmanager pod carries `egress.home.arpa/allow-world` for api.pushover.net (observability is NOT free-world under the V3 baseline).

**Retired**: `apps/flux-system/flux-provider-pushover/` (app plus ks) and `components/common/alerts/pushover/` (Provider/Alert/ExternalSecret) deleted; both removed from their parent kustomizations. `flux-pushover-secret` and `flux-provider-pushover-secret` ExternalSecrets and the relay Deployment were pruned cluster-wide (cluster-apps `prune: true`). Verified: only `alertmanager` plus `github` Providers and `alertmanager` plus `github-status` Alerts remain across all 12 namespaces.

**Unchanged**: the GitHub commit status Provider and Alert at components/common/alerts/github — different function, kept as-is.

**Verified live**: a throwaway Flux Kustomization with a bad path (reason ArtifactFailed) generated an error event that the notification-controller dispatched to the alertmanager Provider; it arrived in the Alertmanager API as FluxKustomizationArtifactfailed (severity error, default pushover receiver) and delivered to Pushover. A regression test after the relay retirement confirmed Pushover still delivers solely via Alertmanager — no alerting gap.

**Note**: the FluxInstance and FluxOperator HelmReleases and the cluster-apps root Kustomization patch (shared HelmRelease defaults) are unchanged by this roadmap; only the notification Provider and Alert model changed.
