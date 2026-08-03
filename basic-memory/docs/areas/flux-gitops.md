---
title: flux-gitops
type: area_reference
permalink: home-ops/docs/areas/flux-gitops
area: flux-gitops
status: current
confidence: high
verified_at: '2026-08-03'
summary: Flux runs via the Flux Operator pattern with a single FluxInstance CR declaring
  controllers, GitRepository sync, and root Kustomization. The cluster-apps Kustomization
  at kubernetes/flux/cluster/ks.yaml is the reconciliation root and injects shared
  HelmRelease defaults into every HelmRelease via a child-Kustomization patch. Per-namespace
  alerting routes through the in-cluster Alertmanager; Pushover is the default receiver. A
  GitHub webhook Receiver gives push-triggered reconciliation alongside the 1h poll, and the
  FluxInstance app also ships the Flux Grafana dashboards.
verified_against:
- kubernetes/apps/flux-system/flux-operator/app/helmrelease.yaml
- kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml
- kubernetes/components/common/alerts/alertmanager/
- kubernetes/flux/cluster/ks.yaml
- kubernetes/CLAUDE.md
- .github/workflows/scanning-deprecated-kube-resources.yaml
- kubernetes/apps/flux-system/flux-instance/app/kustomization.yaml
- kubernetes/apps/flux-system/flux-instance/app/ocirepository.yaml
- kubernetes/apps/flux-system/flux-instance/app/github/
- kubernetes/apps/flux-system/flux-instance/app/grafanadashboard.yaml
- kubernetes/apps/flux-system/flux-instance/app/grafanafolder.yaml
- kubernetes/apps/flux-system/flux-operator/app/ocirepository.yaml
- kubernetes/components/common/alerts/github/
- kubernetes/components/common/vars/cluster-settings.yaml
- kubernetes/mod.just
- kubernetes/bootstrap/readme.md
drift_risk: Performance patches (concurrent counts, memory limits, OOMWatch, in-memory
  kustomize, DisableChartDigestTracking, CancelHealthCheckOnNewRevision) are inline
  patches in the FluxInstance HR — re-evaluate on operator upgrade or hardware change.
  MissingRollbackTarget recovery requires `helm uninstall` outside GitOps — pattern
  preserved here; docs/flux-readme.md and docs/migration/STATUS.md are already deleted (the
  whole top-level docs/ tree is gone), so this note is the canonical home for the procedure.
---

# flux-gitops — current state

## Metadata (observation-form, schema validation)

- [area] flux-gitops
- [status] current
- [confidence] high
- [verified_at] 2026-08-03

## Summary

The cluster runs Flux via the Flux Operator pattern: a single `FluxInstance` CR (in `kubernetes/apps/flux-system/flux-instance/`) declares the four controllers, GitRepository sync target, and root Kustomization. No classic `flux bootstrap` step. The Operator reconciles the FluxInstance. Both HelmReleases take their chart from an `OCIRepository` sibling (`flux-operator/app/ocirepository.yaml`, `flux-instance/app/ocirepository.yaml`).

The reconciliation root is `kubernetes/flux/cluster/ks.yaml` — a single `cluster-apps` Kustomization that scans `./kubernetes/apps` with `prune=true`. It carries TWO child-Kustomization patches: one injects shared HelmRelease defaults into every HelmRelease, the other injects `cluster-settings` substitution into every child Kustomization with an opt-out `labelSelector` (`substitution.flux.home.arpa/disabled notin (true)`).

Reconciliation is both pull- and push-driven. The 1h GitRepository interval is the fallback poll; a Flux `Receiver` (`flux-instance/app/github/receiver.yaml`), exposed at `flux-webhook.${PUBLIC_DOMAIN}` through envoy-external, reconciles the `flux-system` GitRepository and the `cluster-apps` Kustomization immediately on git push. The FluxInstance app also declares the Flux Grafana dashboards (`grafanadashboard.yaml` + `grafanafolder.yaml`, folder "Flux System").

Flux reconciliation alerts are delivered to Pushover through a native Flux `Provider` `type: alertmanager` (in `components/common/alerts/alertmanager/`) that posts to the in-cluster Alertmanager (`alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/`), which in turn routes to Pushover via its `AlertmanagerConfig`. The GitHub commit-status Provider/Alert (`components/common/alerts/github/`) serves a different function and is kept separate.

## Components

- [component] flux-operator — manages the FluxInstance lifecycle (kubernetes/apps/flux-system/flux-operator/, chart via app/ocirepository.yaml)
- [component] flux-instance — declares controllers, sync target, and performance patches (kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml, chart via app/ocirepository.yaml)
- [component] flux-webhook Receiver — GitHub push webhook for immediate reconcile of GitRepository `flux-system` + Kustomization `cluster-apps`; Receiver + HTTPRoute (envoy-external, `flux-webhook.${PUBLIC_DOMAIN}`) + ExternalSecret in kubernetes/apps/flux-system/flux-instance/app/github/
- [component] Flux Grafana dashboards — GrafanaDashboard `flux-cluster` (sourced from fluxcd/flux2-monitoring-example) + GrafanaFolder "Flux System", declared in the FluxInstance app (grafanadashboard.yaml, grafanafolder.yaml)
- [component] cluster-apps Kustomization — single root reconciler, `prune=true`, injects HelmRelease defaults AND cluster-settings substitution via two child-Kustomization patches (kubernetes/flux/cluster/ks.yaml)
- [component] alertmanager alerts component — per-namespace Flux `Provider` (`type: alertmanager`) + `Alert` bundle that posts Flux reconciliation errors into the in-cluster Alertmanager (kubernetes/components/common/alerts/alertmanager/). Wired into `components/common/alerts/kustomization.yaml` alongside `github`.
- [component] github alerts component — Flux `Provider` `type: github` + `Alert` posting commit statuses back to the repo (kubernetes/components/common/alerts/github/), credential via the `flux-github-token` ExternalSecret (1Password `github` / `.flux_github_pat`)
- [component] Pluto deprecated-API scanning — weekly cron (Fri 00:00 UTC) + workflow_dispatch, `pluto detect-files -d kubernetes`, on-failure auto-creates GitHub issue assigned to repo owner (.github/workflows/scanning-deprecated-kube-resources.yaml)

## Claims (verified against repo)

- [claim] "Cluster-wide substitution variables live in the `cluster-settings` ConfigMap (`kubernetes/components/common/vars/cluster-settings.yaml`) and are injected into every child Kustomization by a dedicated second patch on the root `cluster-apps` Kustomization, with an opt-out `labelSelector` `substitution.flux.home.arpa/disabled notin (true)`. The full variable set is PUBLIC_DOMAIN, LAN_SUBNET, ROUTER_IP, LB_IP_POOL_START, LB_IP_POOL_STOP, NAS_IP, ENVOY_INTERNAL_IP, K8S_GATEWAY_IP, PLEX_IP, IOT_SUBNET, POD_CIDR, SVC_CIDR, CLUSTER_DNS_IP. There is NO ${TIMEZONE} variable — container timezone is owned by the k8tz mutating webhook, not by substitution" (evidence: repo, ref: kubernetes/components/common/vars/cluster-settings.yaml:6-25 + kubernetes/flux/cluster/ks.yaml:56-70 + kubernetes/CLAUDE.md, verified: 2026-08-03)

- [claim] "Flux runs four controllers: source-controller, kustomize-controller, helm-controller, notification-controller — declared in FluxInstance.spec.values.instance.components" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:20-24, verified: 2026-08-03)
- [claim] "GitRepository sync points at <https://github.com/zhorvath83/home-ops.git>, ref refs/heads/main, path kubernetes/flux/cluster, 1h interval — the interval is a fallback poll, the webhook Receiver is the primary trigger" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:25-30 + flux-instance/app/github/receiver.yaml:14-22, verified: 2026-08-03)
- [claim] "A Flux `Receiver` reconciles GitRepository `flux-system` and Kustomization `cluster-apps` on GitHub push; it is exposed at `flux-webhook.${PUBLIC_DOMAIN}` on envoy-external and its HMAC token comes from 1Password `github` / `.flux_github_webhook_token` via ExternalSecret" (evidence: repo, ref: flux-instance/app/github/receiver.yaml:1-23 + github/httproute.yaml + github/externalsecret.yaml, verified: 2026-08-03)
- [claim] "The FluxInstance app declares GrafanaDashboard `flux-cluster` and GrafanaFolder `flux-system`, wired through flux-instance/app/kustomization.yaml" (evidence: repo, ref: flux-instance/app/grafanadashboard.yaml + grafanafolder.yaml + kustomization.yaml:8-9, verified: 2026-08-03)
- [claim] "Flux Operator manifests pinned (version constraint 2.x, artifact v0.57.0); Renovate-tracked via inline annotation" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:15-17, verified: 2026-08-03)
- [claim] "cluster-apps Kustomization in namespace flux-system has prune=true, interval=1h, scans ./kubernetes/apps via GitRepository sourceRef name=flux-system" (evidence: repo, ref: kubernetes/flux/cluster/ks.yaml:5-15, verified: 2026-08-03)
- [claim] "HelmRelease defaults are injected via a child-Kustomization patch on cluster-apps: install.crds=CreateReplace, install.strategy.name=RetryOnFailure, rollback.cleanupOnFail=true, timeout=10m, upgrade.cleanupOnFail=true, upgrade.crds=CreateReplace, upgrade.strategy.name=RemediateOnFailure, upgrade.remediation.remediateLastFailure=true, upgrade.remediation.retries=2 — per-HR overrides for these fields are anti-pattern" (evidence: repo, ref: kubernetes/flux/cluster/ks.yaml:21-52, verified: 2026-08-03)
- [claim] "FluxInstance applies performance patches via spec.values.instance.kustomize.patches: --concurrent=10 (then =20 for kustomize-controller), --requeue-dependency=5s, cpu: 2 AND memory: 2Gi limits for kustomize/helm/source controllers, in-memory kustomize builds (emptyDir medium=Memory), OOMWatch on helm-controller (95% threshold, 500ms interval), DisableChartDigestTracking, CancelHealthCheckOnNewRevision" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:34-108, cpu+memory limits at :58-61, verified: 2026-08-03)
- [claim] "FluxInstance disables cluster-level NetworkPolicy creation (instance.cluster.networkPolicy=false); the cluster-wide Cilium baseline allow-cluster-egress + allow-dns-egress applies instead" (evidence: repo, ref: flux-instance/app/helmrelease.yaml:18-19, verified: 2026-08-03)
- [claim] "Recovery procedure for HRs stuck with MissingRollbackTarget or similar uninstall artefacts: `helm uninstall <release> -n <ns>` followed by `flux reconcile hr <name> -n <ns> --force`. Plain `flux reconcile` alone is insufficient" (evidence: behavior, ref: THIS NOTE is the canonical home; kubernetes/bootstrap/readme.md:59-67 summarises it and delegates back here. The former refs docs/flux-readme.md and docs/migration/STATUS.md are deleted, verified: 2026-08-03)
- [claim] "Alternative recovery when an HR is stuck mid-operation ('another operation (install/upgrade/rollback) is in progress') but a usable previous revision still exists: `helm history <release> -n <ns>` to list revisions, `helm rollback <release> <revision> -n <ns>` to revert, then `flux reconcile helmrelease <release> -n <ns>`. Use this before resorting to `helm uninstall` — the rollback path keeps history intact. External reference: <https://support.d2iq.com/hc/en-us/articles/8295311458964-Resolving-issues-with-HelmReleases-that-are-failed>" (evidence: behavior, ref: THIS NOTE is the canonical home; kubernetes/bootstrap/readme.md:61-65, verified: 2026-08-03)
- [claim] "Operational entry points for Flux are encapsulated as `just k8s` recipes (flux-reconcile, flux-check, sync-hr/ks/es, sync, list-failed-hrs, restart-failed-hrs, apply-ks, delete-ks) in kubernetes/mod.just; documentation is the recipe set itself, not duplicated prose" (evidence: repo, ref: kubernetes/mod.just:20,39,46,54,63,70,76,82,97,109, verified: 2026-08-03)
- [claim] "The Flux Alert exclusionList has five entries: `error.*lookup github\\.com`, `error.*lookup raw\\.githubusercontent\\.com`, `dial.*tcp.*timeout`, `waiting.*socket`, `dial.*tcp.*unreachable`" (evidence: repo, ref: kubernetes/components/common/alerts/alertmanager/alert.yaml:24-29, verified: 2026-08-03)

## Drift Risk

- [drift] Performance patches in FluxInstance (concurrent counts, cpu/memory limits, OOMWatch parameters, in-memory kustomize, DisableChartDigestTracking, CancelHealthCheckOnNewRevision) are inline JSON patches inside the HelmRelease spec — re-evaluate on flux-operator-manifests upgrade or hardware/topology change
- [drift] MissingRollbackTarget recovery requires imperative `helm uninstall` outside the GitOps flow. The whole top-level `docs/` tree that used to hold the narrative (docs/flux-readme.md, docs/helm-readme.md, docs/migration/STATUS.md) is deleted, so THIS note is the only remaining home for the procedure — losing it loses the knowledge
- [drift] HelmRelease defaults patch (in cluster-apps) is the single point of truth for shared install/rollback/upgrade behavior — per-HR overrides for those fields are flagged anti-pattern in `kubernetes/CLAUDE.md`, but enforced only by code review (no automated check)
- [drift] The cluster-settings substitution opt-out label (`substitution.flux.home.arpa/disabled`) is a silent failure mode: a Kustomization carrying it gets no ${VAR} expansion, and the symptom is a literal `${VAR}` in a rendered manifest rather than an error

## Open Questions / Gaps

- [gap] (Resolved 2026-07-05) Pushover provider model unified: Flux reconciliation alerts route through a single native `type: alertmanager` Provider into the kube-prometheus-stack Alertmanager, which routes to Pushover via its AlertmanagerConfig + the observability `alertmanager` ExternalSecret (1Password `pushover` item). One path, one credential source.
- [gap] Live cluster verification (FluxInstance Ready, controllers running, GitRepository latest revision) not performed — repo evidence only

## Relations

- depends_on [[external-secrets]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- part_of [[home-ops-platform]]
- supersedes [[flux-readme]]

## Update 2026-07-05

Flux alerting migrated to Alertmanager. See roadmap alertmanager-introduction.

**After**: Flux reconciliation errors flow through a native Flux Provider of type alertmanager (`components/common/alerts/alertmanager/provider.yaml`, address `http://alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/`) plus an Alert covering FluxInstance/GitRepository/HelmRelease/HelmRepository/Kustomization/OCIRepository with exclusionList (github.com and raw.githubusercontent.com lookup, dial tcp timeout, waiting socket, dial tcp unreachable). The component is wired into `components/common/alerts/kustomization.yaml` alongside `github` and fans out to every namespace pulling in `components/common`. Alertmanager routes to Pushover via its AlertmanagerConfig (pushover receiver, HTML template, sendResolved) plus the observability `alertmanager` ExternalSecret (1Password `pushover` item, PUSHOVER_ALERTMANAGER_TOKEN and PUSHOVER_USER_KEY).

**Networking (AD-023 V3 baseline)**: the Flux notification-controller to Alertmanager:9093 east-west path is granted by a per-app CiliumNetworkPolicy (`kubernetes/apps/observability/kube-prometheus-stack/app/ciliumnetworkpolicy.yaml`, second document, `alertmanager` ingress from `flux-system/notification-controller`). The Alertmanager pod carries `egress.home.arpa/allow-world` for api.pushover.net (observability is NOT free-world under the V3 baseline).

**Unchanged**: the GitHub commit status Provider and Alert at components/common/alerts/github — different function, kept as-is.

**Verified live**: a throwaway Flux Kustomization with a bad path (reason ArtifactFailed) generated an error event that the notification-controller dispatched to the alertmanager Provider; it arrived in the Alertmanager API as FluxKustomizationArtifactfailed (severity error, default pushover receiver) and delivered to Pushover.

**Note**: the FluxInstance and FluxOperator HelmReleases and the cluster-apps root Kustomization patch (shared HelmRelease defaults) are unchanged by this roadmap; only the notification Provider and Alert model changed.

## Update 2026-08-03 — staleness re-verification

Full re-verification against the live repo as part of the `area-reference-staleness-audit`
roadmap item. Previous `verified_at` was 2026-07-05. Verdict on arrival: MAJOR-DRIFT.

- [correction] `${TIMEZONE}` was listed as a cluster-settings substitution variable. It is not in
  the ConfigMap at all — container timezone is owned cluster-wide by the k8tz mutating webhook.
  Three real variables were also missing from the list: LB_IP_POOL_START, LB_IP_POOL_STOP, IOT_SUBNET.
- [correction] The GitHub webhook `Receiver` (push-triggered reconcile, `flux-webhook.${PUBLIC_DOMAIN}`
  on envoy-external) was entirely absent from the note. It is a core flux-gitops mechanism and the
  main reason the verdict was MAJOR rather than MINOR drift.
- [correction] The Flux GrafanaDashboard/GrafanaFolder and the two chart `OCIRepository` sources
  (flux-operator, flux-instance) were also unmentioned; all four are now components and in
  `verified_against`.
- [correction] The cluster-settings substitution is a dedicated SECOND patch on cluster-apps with an
  opt-out `labelSelector` (`substitution.flux.home.arpa/disabled notin (true)`) — the note described
  only the root postBuild block.
- [correction] The Alert `exclusionList` has five entries, not four; `dial.*tcp.*unreachable` was missing.
- [correction] The FluxInstance resources patch sets `cpu: 2` as well as `memory: 2Gi`.
- [correction] Three `verified_against`/claim references pointed at deleted files: docs/flux-readme.md,
  docs/helm-readme.md, docs/migration/STATUS.md. The whole top-level `docs/` tree is gone; this note
  is now the canonical home for the HelmRelease recovery procedures, with a repo-side pointer at
  kubernetes/bootstrap/readme.md:59-67.
- [removed] The `intel-gpu-resource-driver` component entry was deleted from this note. It is a
  kube-system DRA driver, not a Flux component, so it never belonged in this area — and its recorded
  chart version (v0.10.1) was stale anyway (live: tag 0.11.0 in
  kubernetes/apps/kube-system/intel-gpu-resource-driver/app/ocirepository.yaml:13). Carried over to
  the k8s-workloads area-reference so the fact is not lost.
- [observation] Every remaining claim was re-checked and held. Four items the audit worker could not
  settle were settled by the reviewer: the Alertmanager `egress.home.arpa/allow-world` pod label
  (kube-prometheus-stack/app/helmrelease.yaml:85), the ExternalSecret key names
  PUSHOVER_ALERTMANAGER_TOKEN / PUSHOVER_USER_KEY (externalsecret.yaml:17-18), and the intel chart
  version above. Live cluster state remains unverified by design (repo-only audit).
