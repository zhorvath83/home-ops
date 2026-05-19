---
title: flux-gitops
type: area_reference
permalink: home-ops/docs/areas/flux-gitops
area: flux-gitops
status: current
confidence: high
verified_at: '2026-05-19'
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
- [verified_at] 2026-05-19

## Summary
The cluster runs Flux via the Flux Operator pattern: a single `FluxInstance` CR (in `kubernetes/apps/flux-system/flux-instance/`) declares the four controllers, GitRepository sync target, and root Kustomization. No classic `flux bootstrap` step. The Operator reconciles the FluxInstance.

The reconciliation root is `kubernetes/flux/cluster/ks.yaml` — a single `cluster-apps` Kustomization that scans `./kubernetes/apps` with `prune=true` and injects shared HelmRelease defaults into every HelmRelease via a child-Kustomization patch. Notifications are delivered to Pushover via a per-namespace Alert+Provider+ExternalSecret bundle from the `flux-alerts` Kustomize component, plus a global Pushover provider deployment.

## Components
- [component] flux-operator — manages the FluxInstance lifecycle (kubernetes/apps/flux-system/flux-operator/)
- [component] flux-instance — declares controllers, sync target, and performance patches (kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml)
- [component] cluster-apps Kustomization — single root reconciler, `prune=true`, injects HelmRelease defaults via child-Kustomization patch (kubernetes/flux/cluster/ks.yaml)
- [component] flux-alerts component — per-namespace Alert+Provider+ExternalSecret bundle for Pushover (kubernetes/components/flux-alerts/)
- [component] flux-provider-pushover — global Pushover Provider deployment in flux-system namespace (kubernetes/apps/flux-system/flux-provider-pushover/)
- [component] Pluto deprecated-API scanning — weekly cron (Fri 00:00 UTC) + workflow_dispatch, `pluto detect-files -d kubernetes`, on-failure auto-creates GitHub issue assigned to repo owner (.github/workflows/scanning-deprecated-kube-resources.yaml)

## Claims (verified against repo)
- [claim] "Flux runs four controllers: source-controller, kustomize-controller, helm-controller, notification-controller — declared in FluxInstance.spec.values.instance.components" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:20-24, verified: 2026-05-19)
- [claim] "GitRepository sync points at https://github.com/zhorvath83/home-ops.git, ref refs/heads/main, path kubernetes/flux/cluster, 1h interval" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:25-30, verified: 2026-05-19)
- [claim] "Flux Operator manifests pinned to v0.49.0 with version constraint 2.x; Renovate-tracked via inline annotation" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:15-17, verified: 2026-05-19)
- [claim] "cluster-apps Kustomization in namespace flux-system has prune=true, interval=1h, scans ./kubernetes/apps via GitRepository sourceRef name=flux-system" (evidence: repo, ref: kubernetes/flux/cluster/ks.yaml:6-15, verified: 2026-05-19)
- [claim] "HelmRelease defaults are injected via a child-Kustomization patch on cluster-apps: install.crds=CreateReplace, install.strategy.name=RetryOnFailure, rollback.cleanupOnFail=true, timeout=10m, upgrade.cleanupOnFail=true, upgrade.crds=CreateReplace, upgrade.strategy.name=RemediateOnFailure, upgrade.remediation.remediateLastFailure=true, upgrade.remediation.retries=2 — per-HR overrides for these fields are anti-pattern" (evidence: repo, ref: kubernetes/flux/cluster/ks.yaml:16-51, verified: 2026-05-19)
- [claim] "FluxInstance applies performance patches via spec.values.instance.kustomize.patches: --concurrent=10 (then =20 for kustomize-controller), --requeue-dependency=5s, memory limit 2Gi for kustomize/helm/source controllers, in-memory kustomize builds (emptyDir medium=Memory), OOMWatch on helm-controller (95% threshold, 500ms interval), DisableChartDigestTracking, CancelHealthCheckOnNewRevision" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:34-107, verified: 2026-05-19)
- [claim] "FluxInstance disables cluster-level NetworkPolicy creation (instance.cluster.networkPolicy=false); the cluster-wide Cilium baseline allow-cluster-egress + allow-dns-egress applies instead" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:18-19, verified: 2026-05-19)
- [claim] "Recovery procedure for HRs stuck with MissingRollbackTarget or similar uninstall artefacts: `helm uninstall <release> -n <ns>` followed by `flux reconcile hr <name> -n <ns> --force`. Plain `flux reconcile` alone is insufficient" (evidence: behavior, ref: docs/flux-readme.md:50-59 + docs/migration/STATUS.md Phase 6, verified: 2026-05-19)
- [claim] "Operational entry points for Flux are encapsulated as `just k8s` recipes (flux-reconcile, flux-check, sync-hr/ks/es, sync, list-failed-hrs, restart-failed-hrs, apply-ks, delete-ks) in kubernetes/mod.just; documentation is the recipe set itself, not duplicated prose" (evidence: repo, ref: kubernetes/mod.just, verified: 2026-05-19)

## Drift Risk
- [drift] Performance patches in FluxInstance (concurrent counts, memory limits, OOMWatch parameters, in-memory kustomize, DisableChartDigestTracking, CancelHealthCheckOnNewRevision) are inline JSON patches inside the HelmRelease spec — re-evaluate on flux-operator-manifests upgrade or hardware/topology change
- [drift] MissingRollbackTarget recovery requires imperative `helm uninstall` outside the GitOps flow; the pattern is captured here as a claim but the detailed Phase 6 narrative lives in `docs/migration/STATUS.md` which is slated for archive/deletion
- [drift] HelmRelease defaults patch (in cluster-apps) is the single point of truth for shared install/rollback/upgrade behavior — per-HR overrides for those fields are flagged anti-pattern in `kubernetes/CLAUDE.md`, but enforced only by code review (no automated check)

## Open Questions / Gaps
- [gap] Pushover provider model split: `kubernetes/components/flux-alerts/` is a per-namespace component, while `kubernetes/apps/flux-system/flux-provider-pushover/` is a standalone app deployment — the relationship between them (which one is the source of truth for the Pushover credentials, how Alerts route) was not fully traced in this pass; deferred to a follow-up or to the external-secrets AreaReference
- [gap] Live cluster verification (FluxInstance Ready, controllers running, GitRepository latest revision) not performed — repo evidence only

## Relations
- depends_on [[external-secrets]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- part_of [[home-ops-platform]]
- supersedes [[flux-readme]]
