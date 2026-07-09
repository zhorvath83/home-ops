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


## Session 2 — P2 atomic cutover + verify (2026-07-09)

### Decided (user approved P2 with "mehet")

- [decision] Proceed with the P2 atomic cutover (one commit): instance/ + datasource CRs, delete app/, replace grafana KS doc with grafana-instance, CNP rewrite.

### Done (P2) — commit 0edf7772e on main, pushed

- Created [file] kubernetes/apps/observability/grafana/instance/{kustomization,externalsecret,grafana,grafanafolder,httproute,servicemonitor,ciliumnetworkpolicy}.yaml. externalsecret.yaml moved unchanged from app/. grafana.yaml = stateless Grafana CR (no PVC, no plugins), disableDefaultAdminSecret: true, admin creds via grafana-secret env vars.
- Created [file] kubernetes/apps/observability/kube-prometheus-stack/app/grafanadatasource.yaml (Prometheus default + Alertmanager; NO VictoriaLogs per D13) + added to that kustomization.
- Modified [file] kubernetes/apps/observability/grafana/ks.yaml — grafana Kustomization document replaced by grafana-instance (dependsOn grafana-operator + kube-prometheus-stack + onepassword-connect/external-secrets, path ./instance).
- Deleted [dir] kubernetes/apps/observability/grafana/app/ entirely (HelmRelease, OCIRepository, CNP, kustomization; externalsecret+kustomization recognized as renames to instance/).
- Commit message: '♻️ refactor(grafana): migrate instance to grafana-operator CRs'. Pre-commit all Passed. Pushed to origin/main.

### Deviation from roadmap spec (applied)

- [observation] httproute.yaml uses envoy-internal ONLY (LAN-only permanent decision D6), NOT both envoy-external+envoy-internal as the roadmap P2 proposed. Homepage annotation typo fixed (Grafanaa -> Grafana).

### Verify (live, post-deploy) — ALL PASS

- [observation] flux get ks -n observability grafana-instance -> Ready (revision 0edf7772). grafana-operator, kube-prometheus-stack also Ready at 0edf7772.
- [observation] kubectl get grafana.grafana.integreatly.org grafana -> STAGE=complete STAGE STATUS=success, VERSION=13.0.1.
- [observation] grafana pod grafana-deployment-5644bcb7bc-h2mpp 1/1 Running; container list = ONLY 'grafana' (NO kiwigrid sidecars — security goal achieved: no kube-apiserver egress, no plugin CDN).
- [observation] kubectl -n observability get cnp grafana -> VALID True.
- [observation] helm ls -n observability -> old 'grafana' release pruned; only 'grafana-operator' remains.
- [observation] GrafanaDatasource prometheus + alertmanager -> DatasourceSynchronized=True, reason ApplySuccessful, "successfully applied to 1 instances".
- [observation] GrafanaFolder observability -> FolderSynchronized=True, ApplySuccessful.
- [observation] grafana-service labels dashboards=grafana, port name 'grafana' port 3000 targetPort grafana-http -> matches ServiceMonitor selector (dashboards: grafana) + endpoint port 'grafana'. Prometheus active target scrapeUrl=http://10.244.0.234:3000/metrics job=grafana-service health=up.
- [observation] HTTPRoute grafana -> parentRef envoy-internal ONLY (LAN-only confirmed), conditions Accepted=True, ResolvedRefs=True. hostname grafana.horvathzoltan.me (PUBLIC_DOMAIN substituted). grafana pod /api/health -> HTTP 200.

### VERIFY resolved (post-deploy)

- [VERIFY resolved] Operator-generated Service = grafana-service, port 3000 (matches roadmap assumption). Service labels propagate the Grafana CR 'dashboards: grafana' label.
- [VERIFY resolved] grafana-data volume = EmptyDir (operator default; no PVC — D2 stateless confirmed). No 'grafana-data' emptyDir needed in grafana.yaml; operator injects it.
- [VERIFY resolved] Operator pod label app.kubernetes.io/name=grafana-operator matches the instance CNP ingress fromEndpoints rule. Operator->grafana:3000 reached after pod startup.

### Transient + non-blocking observation (logged, NOT fixed — see follow-up)

- [observation] Grafana 13.0.1 background plugin installer (logger=plugin.backgroundinstaller) runs a ONE-TIME startup burst (~31s, 21:43:56->21:44:27) attempting 5 bundled app plugins (grafana-exploretraces-app, grafana-metricsdrilldown-app, elasticsearch, grafana-lokiexplore-app, grafana-pyroscope-app) from grafana.com. All fail with connection timeout — grafana.com is correctly blocked by the instance CNP (D13). NOT perpetual (no retries after the burst). No plugins installed (D13 letter satisfied). The Grafana CR 'complete' stage initially failed at 21:43:58 with 'no route to host' (transient first-packet drop during pod startup / Cilium endpoint-identity propagation lag); self-healed to 'complete success' on the operator's next reconcile at 21:44:38.

### Follow-up (out of P2 scope, logged not implemented)

- [follow-up] Grafana 13 background plugin installer startup burst: ~5 error log lines per pod start. Documented candidate to suppress = [plugins] disable_plugins (comma-list of the 5 bundled app plugin IDs) — Context7 confirms disable_plugins 'prevents loading incl. core plugins, hides from catalog' but does NOT confirm it stops the background installer's download ATTEMPTS. NOT shipped unverified (code-generation No-Assumptions). Revisit if the startup noise becomes undesirable; verify live before committing.
- [follow-up] P3 dashboard fan-out (17 dashboards + cilium configMapRef + blackbox 7587) — gated, after P2 instance live (now satisfied).
- [follow-up] P4 blackbox-exporter + kps probeSelectorNilUsesHelmValues: false.
- [follow-up] P5 Pocket-ID OIDC SSO — HUMAN GATE.
- [follow-up] P6 BM docs (observability/iam areas, cnp-per-app-audit, roadmap status -> done).

### Next (gated — awaiting approval)

- [P3] Dashboard/folder CR fan-out per owning app. P2 instance is live and verified — P3 prerequisite satisfied.
