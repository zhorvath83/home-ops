---
title: grafana-operator-migration
type: progress
permalink: home-ops/docs/progress/grafana-operator-migration
topic: Execution state for the grafana-operator-migration roadmap (operator/instance
  split, decentralized dashboard/datasource CRs, blackbox-exporter, Pocket-ID SSO)
status: in-progress
roadmap: '[[grafana-operator-migration]]'
related_areas:
- observability
- iam
- networking
- k8s-workloads
- flux-gitops
decision_link: '[[AD-023-cnp-threat-model-audit]]'
tags:
- progress
- observability
- grafana
- grafana-operator
- blackbox-exporter
- sso
---

# grafana-operator-migration — execution progress

## Metadata (observation-form)

- [topic] Execution state for the grafana-operator-migration roadmap
- [status] in-progress
- [roadmap] [[grafana-operator-migration]] (docs/roadmap)
- [priority] medium

## Execution model (decided with human, 2026-07-09)

- [decision] Delivery: direct commits to 'main' (no feature branch/PR), matching repo norm. Deploy happens on commit-to-main (Flux GitOps watches refs/heads/main).
- [decision] Exposure: Grafana stays LAN-only permanently — HTTPRoute attaches to 'envoy-internal' only, never 'envoy-external'. Overrides roadmap D6/P2 (both gateways). Safer (no internet-exposed Grafana window between P2 and P5).
- [decision] Cutover trigger: P2 is committed to main by the AI only after explicit human approval.

## Deviations from the roadmap spec (corrections)

- [observation] KS namespace: the 'grafana' Flux Kustomization object lives in namespace 'observability' (not 'flux-system') — the parent kubernetes/apps/observability/kustomization.yaml sets 'namespace: observability' and kustomize applies it to child Flux Kustomization CRs. The new grafana-operator / grafana-instance KS objects inherit this. All roadmap acceptance commands using 'flux get ks -n flux-system ...' must use '-n observability'.
- [observation] ${PUBLIC_DOMAIN} / ${NAS_IP} substitution is injected into every child Kustomization automatically by the root cluster-apps Kustomization patch (kubernetes/flux/cluster/ks.yaml postBuild.substituteFrom: cluster-settings, labelSelector substitution.flux.home.arpa/disabled notin (true)). No per-app postBuild needed.
- [observation] grafana-operator chart values (helm show values oci://ghcr.io/grafana/helm-charts/grafana-operator --version 5.24.0) expose podLabels (line 153), resources (180), serviceMonitor (212) directly — no Flux postRenderer patch needed.
- [observation] cilium chart dashboards: TWO blocks (dashboards: at kube-system/cilium/app/helmrelease.yaml:29 and operator.dashboards: at :73), both enabled+annotations.grafana_folder: Cilium; NO hubble.metrics.dashboards: block (roadmap referenced one that does not exist). Handle in P3 via configMapRef.
- [observation] victoria-logs: dashboards.grafanaOperator.enabled=false confirmed; flip in P3 (or skip per D13 caveat).

## P0 — Preflight (DONE 2026-07-09, read-only)

- [done] CRDs present: grafanas / grafanadashboards / grafanadatasources / grafanafolders .grafana.integreatly.org (created 2026-05-18).
- [done] Current grafana healthy: pod grafana-6846c77fcc-4x6gd 3/3 Running (grafana + 2 kiwigrid sidecars); Flux KS 'grafana' (ns observability) Ready @ sha 33a28be3.
- [done] nas.lan resolves in-cluster to 192.168.1.10 -> use 'nas.lan' (not ${NAS_IP}) in P4 Probe targets.
- [done] Chart OCI ref confirmed: oci://ghcr.io/grafana-community/helm-charts/grafana 12.7.2; operator bootstrap pin: 00-crds.yaml:31-35 @ 5.24.0.

## P1 — Deploy the operator (IN PROGRESS)

New files: kubernetes/apps/observability/grafana/operator/ (kustomization, ocirepository, helmrelease, ciliumnetworkpolicy); append 'grafana-operator' Flux Kustomization doc to grafana/ks.yaml (keep existing 'grafana' doc until P2); add 'Grafana Operator' Renovate group to .renovate/groups.json5.

Acceptance (verify after commit-to-main + Flux reconcile):
- flux get ks -n observability grafana-operator -> Ready
- kubectl -n observability get deploy grafana-operator -> Available
- record actual operator pod labels; adjust CNP endpointSelector if live app.kubernetes.io/name differs
- kubectl -n observability get cnp grafana-operator -> VALID
- old grafana still serving (pod 3/3, UI loads)

Next: P2 cutover — STOP and request explicit human approval (production Grafana downtime).

## Relations

- implements [[grafana-operator-migration]]
- decided_in [[AD-023-cnp-threat-model-audit]]
- continues [[alertmanager-introduction]]
- relates_to [[observability]]
- relates_to [[iam]]


## Session 1 — P1 deploy + verify (2026-07-09)

### Done (P1)

- Created [file] kubernetes/apps/observability/grafana/operator/{kustomization,ocirepository,helmrelease,ciliumnetworkpolicy}.yaml — operator deploy unit (OCIRepository oci://ghcr.io/grafana/helm-charts/grafana-operator tag 5.24.0, minimal-spec HelmRelease with serviceMonitor.enabled + AD-023 podLabels + resources, custom-egress CNP).
- Modified [file] kubernetes/apps/observability/grafana/ks.yaml — appended second Flux Kustomization document 'grafana-operator' (targetNamespace observability, wait: true, no dependsOn). Existing 'grafana' document left intact until P2.
- Modified [file] .renovate/groups.json5 — added 'Grafana Operator' group (matchDatasources docker+helm, matchPackageNames /grafana-operator/, minimumGroupSize 1) so HelmRelease OCIRepository tag + bootstrap 00-crds.yaml CRD pin bump in lockstep.
- Code commit c056d6c76 on main: '✨ feat(grafana): deploy grafana-operator alongside chart grafana'. Pushed to origin/main. Pre-commit hooks all Passed (yamlfmt, yamllint, gitleaks, etc.).
- Flushed root cluster-apps KS (flux reconcile --with-source) → child grafana-operator KS reconciled.

### Verify (live, post-deploy) — ALL PASS

- [observation] flux get ks -n observability grafana-operator → Ready, Applied revision refs/heads/main@sha1:c056d6c7.
- [observation] kubectl -n observability get deploy grafana-operator → 1/1 Available.
- [observation] operator pod grafana-operator-b7f59bd49-sbmqd 1/1 Running, IP 10.244.0.81, node k8s-cp0.
- [VERIFY resolved] operator pod label app.kubernetes.io/name = grafana-operator — exactly matches CNP endpointSelector.matchLabels. No CNP adjustment needed. Full pod labels: component=operator, instance=grafana-operator, managed-by=Helm, name=grafana-operator, part-of=grafana-operator, version=v5.24.0, plus injected ingress.home.arpa/prometheus=true and egress.home.arpa/custom-egress=true.
- [observation] kubectl -n observability get cnp grafana-operator → VALID True ("Policy validation succeeded").
- [observation] old grafana unchanged: grafana-6846c77fcc-4x7gd 3/3 Running (grafana + 2 kiwigrid sidecars), age 24h; grafana KS Ready. Additive deploy confirmed — zero impact on existing Grafana.
- [observation] sibling observability KS all Ready at c056d6c7: grafana, grafana-operator, kube-prometheus-stack, speedtest-exporter, victoria-logs, victoria-logs-collector.

### Next (gated — NOT started this session)

- [P2] Atomic cutover: instance/ + datasource CRs, delete app/, replace 'grafana' KS doc with 'grafana-instance' (dependsOn grafana-operator + kube-prometheus-stack + onepassword-connect/external-secrets), CNP rewrite to envoy-internal-only. Requires explicit human approval (brief Grafana downtime).
- [P3] Dashboard/folder CR fan-out (17 dashboards + cilium configMapRef + blackbox 7587). After P2 instance live.
- [P4] blackbox-exporter app + kps probeSelectorNilUsesHelmValues: false.
- [P5] Pocket-ID OIDC SSO — HUMAN GATE (client + groups + 1Password fields).
- [P6] BM docs: observability/iam area notes, cnp-per-app-audit, roadmap status → done.

### Open VERIFY items (carried to P2+)

- Operator-generated Grafana instance Service name/port (roadmap assumes grafana-service:3000 — confirm against live Grafana CR in P2).
- grafana-data emptyDir default behavior.
- cilium live dashboard ConfigMap names (P3 configMapRef sourcing).
- volsync R1 VAR_REPLICATIONDESTNAME behavior (P3 vendored ConfigMap).
- victoria-logs chart dashboards.grafanaOperator.* schema passthrough (P3, D13 caveat).
- Pocket-ID OIDC discovery endpoint paths (P5).
