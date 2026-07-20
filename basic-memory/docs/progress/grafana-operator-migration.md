---
title: grafana-operator-migration
type: progress
permalink: home-ops/docs/progress/grafana-operator-migration
topic: Execution state for the grafana-operator-migration roadmap (operator/instance
  split, decentralized dashboard/datasource CRs, blackbox-exporter, Kanidm SSO)
status: done
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
- [status] done
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
- [P5] Kanidm OIDC SSO — HUMAN GATE (client + groups + 1Password fields).
- [P6] BM docs: observability/iam area notes, cnp-per-app-audit, roadmap status → done.

### Open VERIFY items (carried to P2+)

- Operator-generated Grafana instance Service name/port (roadmap assumes grafana-service:3000 — confirm against live Grafana CR in P2).
- grafana-data emptyDir default behavior.
- cilium live dashboard ConfigMap names (P3 configMapRef sourcing).
- volsync R1 VAR_REPLICATIONDESTNAME behavior (P3 vendored ConfigMap).
- victoria-logs chart dashboards.grafanaOperator.* schema passthrough (P3, D13 caveat).
- Kanidm OIDC discovery endpoint paths (P5).


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
- [follow-up] P5 Kanidm OIDC SSO — HUMAN GATE.
- [follow-up] P6 BM docs (observability/iam areas, cnp-per-app-audit, roadmap status -> done).

### Next (gated — awaiting approval)

- [P3] Dashboard/folder CR fan-out per owning app. P2 instance is live and verified — P3 prerequisite satisfied.


## Session 3 — P3 dashboard/folder fan-out (2026-07-09/10, committed 5ecda15bc)

### Scope (decided with human)

- [decision] P3 scope = full parity, 23 dashboards: 17 url/grafana.com imports (kps k8s-views x4 + k8s-volumes + node-exporter-full + openwrt, speedtest, flux x4, envoy x2, external-dns, cert-manager, volsync) + 6 configMapRef imports of chart-emitted ConfigMaps (cilium x2, external-secrets, tuppr, victoria-logs x2). 8 folders, one per owner namespace (D4): observability (existing from P2) + 7 new cross-namespace (flux-system, networking, cert-manager, volsync-system, kube-system, external-secrets, system-upgrade).
- [decision] Chart-emitted dashboards use configMapRef (uniform, avoids per-chart grafanaOperator-schema verification) rather than flipping each chart's grafanaOperator mode.

### Schema verified (Context7 /grafana/grafana-operator — No Assumptions)

- GrafanaDashboard: grafanaCom{id,revision} for gnetId; url for URL imports; configMapRef{name,key}; datasources[{inputName,datasourceName}] remaps templated datasources; folderRef = same-namespace GrafanaFolder CR name; allowCrossNamespaceImport default false.
- GrafanaFolder: title, instanceSelector (immutable), allowCrossNamespaceImport, uid (immutable).
- Cross-namespace import requires allowCrossNamespaceImport: true on BOTH the Grafana instance CR AND each cross-ns dashboard/folder CR. Added to instance/grafana.yaml (was same-ns-only in P2). Operator is cluster-scoped (no WATCH_NAMESPACE restriction).
- No CR field for non-datasource template variables (e.g. VAR_*) -> volsync R1 applies.

### Changes committed (5ecda15bc, 31 files: 18 new + 13 modified)

- 11 GrafanaDashboard files (23 dashboards) + 7 new GrafanaFolder files across 11 owning apps; 11 app kustomization.yaml updated to reference them.
- instance/grafana.yaml: + spec.allowCrossNamespaceImport: true (no pod redeploy — field only affects operator matching logic; pod stayed 1/1, no downtime).
- cilium helmrelease: removed both now-dead annotations.grafana_folder: Cilium blocks (dashboards + operator.dashboards), kept enabled: true so the CMs persist as configMapRef sources.
- All 23 dashboards carry datasources[{inputName: DS_PROMETHEUS, datasourceName: Prometheus}] remap (same convention the old kiwigrid sidecar used).
- Omitted the old `# renovate: depName="..."` annotations: quoted space-containing depName with no datasource= does not match the repo generic regex customManager, and no grafana-operator grafanaCom customManager exists -> they were inert.

### Live verify (operator-CR level, all green)

- 23/23 GrafanaDashboard DashboardSynchronized=True ("applied to 1 instances").
- 8/8 GrafanaFolder FolderSynchronized=True; folder tree = D4 owner-namespace structure (Cert Manager, External Secrets, Flux System, Cilium, Networking, Observability, System Upgrade, VolSync).
- 2/2 GrafanaDatasource (prometheus default + alertmanager) carried from P2, unchanged.
- Grafana instance complete/success; pod 1/1, single 'grafana' container (no kiwigrid sidecar regression).
- DS_PROMETHEUS remap confirmed matching: cilium-dashboard ConfigMap uses templating var DS_PROMETHEUS.
- Transient reconcile race: external-dns "GrafanaFolder networking not found" errors at 22:00:28-34 (dashboard reconciled before the folder CR registered in the operator cache); self-healed by 22:00:35 (DashboardSynchronized=True, lastResync 22:00:35). No flapping after.
- pre-commit (yamlfmt, yamllint, gitleaks, k8s-secret scan) all Passed on the 31 files.

### Follow-up (out of P3 scope, logged not implemented)

- [follow-up] volsync R1: VAR_REPLICATIONDESTNAME template variable has no CR field; imported via grafanaCom with DS_PROMETHEUS remap only. UI-verify whether the dashboard renders data; if empty, fall back to a vendored ConfigMap with the variable defaulted (roadmap R1).
- [follow-up] Renovate grafana-operator grafanaCom dashboard revision bumping: no customManager exists for the new GrafanaDashboard grafanaCom{id,revision} shape; the old depName annotations were not functional. Add a customManager if dashboard revision auto-update is desired.
- [follow-up] Grafana 13 background plugin installer hardening (Session 2, unchanged).
- [follow-up] P4 blackbox-exporter + kps probeSelectorNilUsesHelmValues: false.
- [follow-up] P5 Kanidm OIDC SSO — HUMAN GATE.
- [follow-up] P6 BM docs (observability/iam areas, cnp-per-app-audit, roadmap status -> done).

### Next (gated)

- [P4] blackbox-exporter app (nas.lan ICMP + NFS tcp/2049 probes) + kps probeSelectorNilUsesHelmValues: false. Independent; the blackbox 7587 dashboard CR is a P3/P4 touchpoint.


## Session 4 — P4: blackbox-exporter + kps probeSelector (2026-07-10)

**Scope**: deploy prometheus-blackbox-exporter (chart 11.15.1 / app v0.28.0) in observability to probe nas.lan (ICMP) and nas.lan:2049 (NFS) via prometheus-operator Probe CRs; flip kps probeSelector to match-all.

**App files** (kubernetes/apps/observability/blackbox-exporter/): ks.yaml (dependsOn kube-prometheus-stack), app/{kustomization, ocirepository (oci://ghcr.io/prometheus-community/charts/prometheus-blackbox-exporter tag 11.15.1), helmrelease, probes, prometheusrule, grafanadashboard, ciliumnetworkpolicy}.yaml. Parent observability/kustomization.yaml lists ./blackbox-exporter/ks.yaml; kps helmrelease gained probeSelectorNilUsesHelmValues: false.

Key decisions (No-Assumptions verified before writing):
- Chart uses `pod.labels` (NOT podLabels) for pod labels; config.modules default ships ONLY http_2xx -> added icmp + tcp_connect explicitly.
- securityContext: drop ALL + add NET_RAW for ICMP (chart default drops ALL); runAsUser 1000, readOnlyRootFilesystem, runAsNonRoot.
- fullnameOverride: prometheus-blackbox-exporter -> deterministic service name for the Probe prober URL.
- AD-023: allow-world EXCEPTS RFC1918 (192.168/16), so nas.lan (192.168.1.10) needs custom-egress + per-app CNP with toCIDRSet 192.168.1.10/32 (icmps type 8 + tcp/2049), NOT allow-world. Prometheus scrape ingress via the cluster CCNP (ingress.home.arpa/prometheus).
- nas.lan resolves in-cluster to 192.168.1.10 (CoreDNS 10.245.0.10).
- Dashboard gnetId 7587 binds its datasource via the DS_SIGNCL-PROMETHEUS input (NOT DS_PROMETHEUS) -> datasources.inputName = DS_SIGNCL-PROMETHEUS, datasourceName = Prometheus.
- kps: added probeSelectorNilUsesHelmValues: false (completes the sm/pm/rule/probe quartet -> all four selectors match-all).

**Bug found + fixed (loop-until-verified)**: Probe CR spec.prober.url must be a BARE host[:port], not http://... -- the prometheus-operator rejects full URLs ("invalid proberSpec ... should be of the format hostname or hostname:port"). First deploy: operator skipped both Probes, probe_success empty, no up{nas|nfs}. Fix commit a8c08dbe: prober.url = prometheus-blackbox-exporter.observability.svc.cluster.local:9115 (no scheme); added a comment documenting the footgun.

Commits: ebdf73c5 (feat: blackbox-exporter + probeSelector), a8c08dbe (fix: bare host prober.url). Pushed to main; Flux deployed.

**Live verify (all pass)**:
- blackbox-exporter HR Ready (chart 11.15.1); KS Ready (rev a8c08dbe); pod Running 1/1.
- Pod labels: app.kubernetes.io/name=prometheus-blackbox-exporter, ingress.home.arpa/prometheus=true, egress.home.arpa/custom-egress=true; capabilities drop ALL + add NET_RAW.
- CNP prometheus-blackbox-exporter: 2 egress rules (192.168.1.10/32 icmps type 8 + tcp/2049); endpointSelector matches the live pod label; VALID.
- Prometheus CR probeSelector={}, serviceMonitorSelector={} (match-all); kps helm upgrade succeeded (rev v29).
- probe_success{instance=nas.lan, job=nas}=1 (ICMP); probe_success{instance=nas.lan:2049, job=nfs}=1 (NFS); up=1 both.
- BlackboxProbeFailed PrometheusRule loaded (rulefile observability-blackbox-exporter-*.yaml, group blackbox-exporter, 1 rule, severity=critical -> Pushover); not firing (probes succeed -> correct).
- Dashboard 7587 DashboardSynchronized=True (uid xtkCtBkiz, folder observability).

**Follow-ups**: none new for P4.

**Next**: P5 -- Kanidm OIDC SSO (HUMAN GATE: create Kanidm client "Grafana" + groups grafana_users/grafana_administrators + 1Password fields GRAFANA_OAUTH_CLIENT_ID/GRAFANA_OAUTH_CLIENT_SECRET, then extend instance/externalsecret + grafana.yaml auth.generic_oauth + instance CNP egress to idm.<domain>).


## Session 5 — P5: Kanidm OIDC SSO (2026-07-09/10, commits 83bb79cc6, d3a4ecf44, 518aa4b03, 6598ada5f, f990d45e4, 703dd9e03)

**Scope**: close Grafana's IAM exception — make Grafana OIDC-native against Kanidm (iam Path A). HUMAN GATE items (Kanidm client + groups + 1Password fields) done by the human.

### Done (P5)

- [done] Kanidm OIDC client "Grafana" created (client_id `777facef-f5f4-44d3-abaf-e00884bfa35a`), redirect `https://grafana.${PUBLIC_DOMAIN}/login/generic_oauth`.
- [done] `instance/grafana.yaml`: added `spec.config.auth.generic_oauth` (enabled, name, scopes `openid email profile groups`, auth/token/userinfo at the public issuer `idm.${PUBLIC_DOMAIN}` per AD-023, `email_attribute_name: email:primary`, `allow_sign_up: true`). Client id/secret injected via env `GF_AUTH_GENERIC_OAUTH_CLIENT_ID/SECRET` from `grafana-secret`.
- [done] `instance/externalsecret.yaml`: template emits the OIDC keys; instance CNP already carries `egress.home.arpa/allow-gateways` for the token/userinfo hairpin through envoy.
- [done] Role mapping: `role_attribute_path: contains(groups[*], 'grafana_admins') && 'Admin' || 'None'`, `role_attribute_strict: true`, `skip_org_role_sync: false`.

### Deviations from roadmap D5 (intentional, decided with human)

- [decision] Group is `grafana_admins` → Admin (everyone else → None), NOT `grafana_users`/`grafana_administrators` with Viewer/GrafanaAdmin.
- [decision] Local login form is **hidden** (`disable_login_form: true`), NOT kept as break-glass. The `admin-user`/`admin-password` in `grafana-secret` remain as the **grafana-operator provisioning credential** (operator auths to the Grafana API with them), not a human login path.
- [decision] Secret keys renamed to `GRAFANA_OIDC_CLIENT_ID`/`GRAFANA_OIDC_CLIENT_SECRET` (1Password item `grafana`), not `GRAFANA_OAUTH_*`.

### Fixes during P5 rollout

- [observation] `allowCrossNamespaceImport` as a top-level Grafana CR field was invalid → removed (d3a4ecf44). Cross-ns import is set on the dashboard/folder CRs (P3) + `spec.allowCrossNamespaceImport` on the instance.
- [observation] `auth.generic_oauth` is a dotted grafana.ini section → must be a first-level key under `spec.config` (518aa4b03).
- [observation] ExternalSecret template must explicitly emit the OIDC keys (6598ada5f).

## Session 6 — SSO/plugin/empty-UI debugging + fixes (2026-07-10, commits 4ba4c9ce8 + reloader-removal; SSO secret fixes by human)

### SSO "Login failed / Failed to get token from provider" — RESOLVED

- [root-cause] The token exchange reached Kanidm and was rejected: grafana log `[auth.oauth.token.exchange] failed to exchange code to token: oauth2: "Invalid client secret"`; Kanidm log `invalid client secret` on `POST /api/oidc/token` from the grafana pod IP. NOT a network/CNP/hairpin issue (a different client's token exchange succeeded over the same path). The `OIDC_CLIENT_SECRET` value in 1Password did not match the Kanidm client secret.
- [fix] Human re-synced the secret value (1Password ↔ Kanidm) + pod restart (ephemeral DB re-seeds admin from env). SSO login works.

### Plugin preinstall noise — RESOLVED (commit 4ba4c9ce8)

- [root-cause] Grafana 13 core `plugin.backgroundinstaller` attempts 5 default preinstall app plugins (lokiexplore, exploretraces, pyroscope, metricsdrilldown app, + elasticsearch version check) from grafana.com at startup → blocked by CNP → HubblePolicyDeny. Confirmed NOT bundled in the image (`/var/lib/grafana/plugins` empty; only core datasources bundled). 4 apps need backends absent from this cluster; metrics-drilldown unused.
- [fix] `preinstall_disabled: "true"` under `spec.config.plugins` — stops the startup fetch (D13). Resolves the delegated cnp-per-app-audit finding.

### Login form not actually hidden — FIXED (commit 4ba4c9ce8)

- [root-cause] Config used `auth.disable_login` — a non-existent grafana.ini key (no-op) → the user/pass form stayed visible despite intent.
- [fix] Corrected to `disable_login_form: "true"`. Confirmed via Grafana docs (Context7).

### "Everything empty in the Grafana UI" — RESOLVED (was a stale browser session, backend healthy)

- [investigation] Traced through operator auth flapping, ephemeral-DB wipes, and `NoMatchingInstance`/`EmptyAPIReply` on dashboard CRs. Root fragility: `grafana-data` is emptyDir; every `grafana-secret` change flips the operator's `checksum/secrets` pod-template annotation → pod recreated → DB wiped → instance briefly "not ready" → dashboard/datasource/folder reconcilers skip. The many secret changes during this session caused repeated recreations.
- [evidence] Once the pod stabilized: 24 dashboards + 8 folders + 2 datasources all `ApplySuccessful`, `GrafanaReady=True`. In-pod API queries (using the pod's own env creds — secret never exposed) confirmed data present: legacy `/api/search` = 24, unified-storage search `totalHits: 32` (24+8), `/api/dashboards/uid/xtkCtBkiz` = 200, SSO user (id=2) = Admin in org 1. The Grafana 13 `dashboard-service "starting from scratch"` log is benign (index works).
- [root-cause] The user's empty view was a **stale browser session** from a login during the provisioning window (user id=2 created/last-seen 15:24, mid-restart). Hard-refresh / re-login showed everything. Confirmed OK by user.

### reloader annotation — added then removed

- [observation] Added `reloader.stakater.com/auto` (4ba4c9ce8), then found it **redundant**: the grafana-operator's `checksum/secrets` pod-template annotation already recreates the pod on `grafana-secret` changes, so reloader would cause a double restart. Removed (human commit).

### Secret key rename (human)

- [observation] OIDC keys renamed `OIDC_CLIENT_ID/SECRET` → `GRAFANA_OIDC_CLIENT_ID/SECRET` across `grafana.yaml` env + `externalsecret.yaml` template + 1Password fields; live `grafana-secret` keys and env references verified consistent (ExternalSecret SecretSynced).

### Migration status: COMPLETE

- [done] P0–P6 complete. Functional end state verified live. Docs updated: [[observability]] + [[iam]] area notes, [[cnp-per-app-audit]] finding closed, roadmap status → done.

### Open follow-ups (optional, non-blocking)

- [follow-up] Renovate customManager for grafanaCom dashboard revisions: no manager understands the `grafanaCom: {id, revision}` shape, so the 17 URL-imported dashboard revisions are manually pinned (same as pre-migration — NOT a regression). Add a regex customManager (`datasource=grafana-dashboards`, id→depName, revision→currentValue) if auto-bump is wanted. Deferred — manual pin is acceptable/safer for a homelab.
- [resolved] volsync dashboard (VAR_REPLICATIONDESTNAME): renders data — OK per user (2026-07-10). No vendored-ConfigMap fallback needed.


## Update — 2026-07-10 (later): dashboard revisions — pinned URL form + Renovate auto-update (B2, bjw-s-aligned)

- [context] A "drop the pin" step was briefly done (grafanaCom id-only → latest), then reviewing bjw-s-labs/home-ops showed the reference repo PINS every revision and auto-updates via Renovate. Adopted that pattern (B2), which the roadmap's best-practice alignment favors.
- [done] All 12 dashboards converted from `grafanaCom: {id, revision}` to the pinned URL form `url: https://grafana.com/api/dashboards/<id>/revisions/<rev>/download` (6 files: external-dns, cert-manager, kube-prometheus-stack ×7, speedtest-exporter, blackbox-exporter, volsync).
- [done] Added the home-operations `grafanaDashboards` Renovate preset to `.renovaterc.json5` extends: `github>home-operations/renovate-presets//managers/grafanaDashboards.json5#2.1.0`. It defines a `grafana-dashboards` custom datasource + a regex customManager matching `dashboards/<id>/revisions/<rev>/download` → opens reviewed revision-bump PRs (`chore(grafana-dashboards): update dashboard X (43 ➔ 44)`).
- [outcome] Deterministic/reproducible from git AND low-maintenance (reviewed auto-bump PRs). Best of both — supersedes the "manual pin" follow-up and the transient "pins dropped" step.


---

## Archived roadmap — design reference

> Originally `docs/roadmap/grafana-operator-migration.md` (type: roadmap, status: done). Merged into this progress note on 2026-07-11 after the grafana-operator migration completed. The execution-grade design (P0–P6 phases, full manifest YAML, decisions D1–D13) is preserved verbatim below.

### Original roadmap frontmatter

```yaml
title: grafana-operator-migration
type: roadmap
permalink: home-ops/docs/roadmap/grafana-operator-migration
topic: Re-implement Grafana with grafana-operator (operator/instance split, decentralized
  dashboard/datasource CRs, Kanidm SSO) + blackbox-exporter probing nas.lan ICMP
  + NFS tcp/2049
status: done
priority: medium
scope: Execution-grade roadmap. Contains the full YAML of every new/changed manifest,
  the per-app dashboard placement table, CNP rewrites under AD-023, the Kanidm
  OIDC wiring, per-phase verify commands and acceptance criteria. An executor should
  work through P0-P6 without design decisions; live-state checks are marked VERIFY,
  human-only steps are marked HUMAN GATE, undecided items live under Follow-ups.
rationale: Aligns with bjw-s-labs/home-ops and onedr0p/home-ops best practice (operator/instance
  split, dashboards-as-CRs co-located with owning apps), removes the kiwigrid sidecars
  and the grafana pod's kube-apiserver egress, and turns dashboard/datasource state
  fully declarative. No Grafana plugins at all (VictoriaLogs stays in vmui, D13) -
  zero startup internet dependency. SSO via Kanidm closes Grafana's IAM exception
  per the standing no-app-without-IAM policy. Blackbox-exporter adds LAN service probing
  (NAS + NFS) wired into the existing Alertmanager->Pushover path.
options:
- 'P0: preflight - CRDs, baseline, nas.lan DNS check'
- 'P1: deploy grafana-operator alongside the chart grafana + renovate group'
- 'P2: atomic instance cutover - Grafana CR + datasource CRs + CNP rewrite, delete
  chart app/'
- 'P3: dashboard fan-out - co-located GrafanaDashboard/GrafanaFolder CRs per owning
  app'
- 'P4: blackbox-exporter app + Probe CRs + kps probeSelector flag'
- 'P5: SSO - Kanidm OIDC (HUMAN GATE: client + groups + 1Password fields)'
- 'P6: BM docs updates (observability + iam areas, cnp-per-app-audit, progress note)'
related_areas:
- observability
- iam
- networking
- k8s-workloads
- flux-gitops
decision_link: AD-023-cnp-threat-model-audit
tags:
- roadmap
- observability
- grafana
- grafana-operator
- blackbox-exporter
- sso
```

### Original roadmap body

# Grafana re-implementation on grafana-operator + blackbox-exporter — execution-grade roadmap

## Metadata (observation-form, schema validation)

- [topic] Re-implement Grafana with grafana-operator (operator/instance split, decentralized dashboard/datasource CRs) + new blackbox-exporter probing nas.lan (ICMP) and its NFS service (TCP 2049)
- [status] done
- [progress] Execution state will live in [[grafana-operator-migration]] (docs/progress) — create it at P1 start from this note's phase list
- [priority] medium

## Goal

Replace the standalone `grafana` Helm chart deployment (`kubernetes/apps/observability/grafana/`) with the **grafana-operator** pattern used by bjw-s-labs/home-ops and onedr0p/home-ops: the operator deployed by HelmRelease, the Grafana instance as a `Grafana` CR, datasources/dashboards/folders as `GrafanaDatasource`/`GrafanaDashboard`/`GrafanaFolder` CRs **co-located with the app that owns them**. Add a **blackbox-exporter** app (prometheus-blackbox-exporter chart) with `Probe` CRs for nas.lan reachability (ICMP) and the NFS service (TCP 2049), modeled on bjw-s.

The end state also closes Grafana's IAM exception: **SSO via Kanidm OIDC** (iam area "Path A"), per the standing policy that no app ships without an IAM policy (see docs/areas/iam §3).

An executor should be able to work through P0–P6 without making design decisions. Anything the executor must check against the live cluster or chart values is explicitly marked **VERIFY**. Anything undecided is under Open questions / Follow-ups. Steps requiring the human (Kanidm UI, 1Password fields) are marked **HUMAN GATE** — in agent mode these are escalation points.

## Definitions (use these exact strings everywhere)

- [observation] Instance-selector contract: every GrafanaDashboard/GrafanaDatasource/GrafanaFolder CR carries `instanceSelector.matchLabels: {dashboards: grafana}`; the Grafana CR carries `metadata.labels: {dashboards: grafana}`. Cross-namespace CRs additionally carry `allowCrossNamespaceImport: true`.
- [observation] Datasource display names (preserve current names so dashboard refs keep working): `Prometheus` (default), `Alertmanager`. There is NO VictoriaLogs datasource (D13) — logs are consumed in the VictoriaLogs vmui at logs.${PUBLIC_DOMAIN}.
- [observation] gnetId→URL conversion: `https://grafana.com/api/dashboards/<gnetId>/revisions/<revision>/download`.
- [observation] AD-023 labels used here: `ingress.home.arpa/gateways`, `ingress.home.arpa/prometheus`, `egress.home.arpa/custom-egress` — value always `"true"`.
- [observation] Cluster vars available via Flux postBuild substitution: `${PUBLIC_DOMAIN}`, `${NAS_IP}` (= 192.168.1.10), see kubernetes/components/common/vars/cluster-settings.yaml.

## Current state (evidence)

- [observation] Current grafana: official chart `oci://ghcr.io/grafana-community/helm-charts/grafana` 12.7.2, stateless (persistence disabled), admin creds via ExternalSecret `grafana-secret` (keys `admin-user`/`admin-password`, 1Password item `grafana`), datasources + ~20 dashboards inlined in HelmRelease values, kiwigrid sidecars discover ConfigMap dashboards cluster-wide (kubernetes/apps/observability/grafana/app/helmrelease.yaml)
- [observation] Sidecar-labeled ConfigMap producers today: victoria-logs chart (`grafana_dashboard: "1"` label + `grafana_folder: Observability` annotation, victoria-logs/app/helmrelease.yaml:51-58) and cilium chart (`dashboards.enabled` + `hubble.metrics.dashboards.enabled`, `grafana_folder: Cilium`, kube-system/cilium/app/helmrelease.yaml:29-32,73-76)
- [observation] victoria-logs chart already has a `dashboards.grafanaOperator.enabled: false` switch — it can emit GrafanaDashboard CRs natively (victoria-logs/app/helmrelease.yaml:57-58)
- [observation] **grafana-operator CRDs are ALREADY in the bootstrap chain**: kubernetes/bootstrap/helmfile.d/00-crds.yaml:31-35 pins `oci://ghcr.io/grafana/helm-charts/grafana-operator` 5.24.0 with a renovate annotation. `just cluster-bootstrap crds` renders and applies them.
- [observation] kube-prometheus-stack values set `serviceMonitorSelectorNilUsesHelmValues/podMonitorSelectorNilUsesHelmValues/ruleSelectorNilUsesHelmValues: false` but NOT `probeSelectorNilUsesHelmValues` — Probe CRs would be silently ignored (kube-prometheus-stack/app/helmrelease.yaml:486-488)
- [observation] The `# renovate: depName="..."` annotations on gnetId dashboards are DEAD — the inline-annotation custom manager regex requires `datasource=<x> depName=<y>` and these lines have no `datasource=`; dashboard revisions have always been manually pinned (.renovate/customManagers.json5:22-23)
- [observation] grafana CNP today: narrow-world egress (grafana.com, storage.googleapis.com, raw.githubusercontent.com, gravatar.com) + in-cluster datasources (9090/9093/9428) + kube-apiserver:6443 for the kiwigrid sidecars (grafana/app/ciliumnetworkpolicy.yaml)
- [observation] Homepage discovers grafana via `gethomepage.dev/*` annotations on the HTTPRoute (name currently misspelled "Grafanaa")

## Design decisions (all made — do not reopen during implementation)

- [decision] **D1 — operator/instance split**: `kubernetes/apps/observability/grafana/` gets `operator/` and `instance/` subdirs; `ks.yaml` declares two Flux Kustomizations — `grafana-operator` (`wait: true`) and `grafana-instance` (`dependsOn: grafana-operator, kube-prometheus-stack, onepassword-connect`). Matches both reference repos and the repo's CRD-before-CR convention.
- [decision] **D2 — stateless instance (NO PVC)**: diverges from bjw-s/onedr0p (both use 5Gi PVC). Rationale: current grafana is already stateless and GitOps-pure — every datasource/dashboard is declarative; anything worth keeping must become a CR in git. `grafana-data` stays an emptyDir (operator default when no `persistentVolumeClaim` is set — VERIFY after deploy). No VolSync wiring needed.
- [decision] **D3 — dashboards/datasources co-located with the owning app** (bjw-s/onedr0p pattern; consistent with how ServiceMonitors are already distributed per platform). Full placement table in P3. Safe at bootstrap because the CRDs are in 00-crds.yaml.
- [decision] **D4 — thematic GrafanaFolder CRs, one owner per namespace**: `folderRef` is namespace-scoped, so each folder CR lives in the namespace of the dashboards that reference it. Folder set: Kubernetes + System (in kube-prometheus-stack/app), Observability (in grafana/instance), Networking (in envoy-gateway/app), Flux (in flux-instance/app), Storage (in volsync/app), Cilium (in cilium/app), Cert Manager (in cert-manager/app). Never create two folders with the same title in different namespaces.
- [decision] **D5 — SSO via Kanidm OIDC IS in scope (P5)**: Grafana becomes an OIDC-native app (iam Path A: Kanidm client + `grafana_users`/`grafana_administrators` groups + `auth.generic_oauth`). Role mapping: `grafana_administrators` → GrafanaAdmin, `grafana_users` → Viewer, `role_attribute_strict` (no mapped group = no access). The admin login form STAYS enabled as documented break-glass (`disable_login_form: false`) with creds from the existing `grafana-secret`. SSO lands as its own phase AFTER the cutover is verified, because it depends on a HUMAN GATE (Kanidm client creation + 1Password fields).
- [decision] **D6 — standalone HTTPRoute manifest**, NOT the Grafana CR's `spec.httpRoute` field: we need `gethomepage.dev/*` annotations and both gateways; the CR field only exposes `spec`. Fixes the "Grafanaa" typo → `Grafana`.
- [decision] **D7 — operator-managed default grafana image** (no image override, no MutatingAdmissionPolicy): grafana version follows operator releases, which Renovate tracks via the chart tag. docker.io pulls are fine in this cluster.
- [decision] **D8 — intentionally NOT carried over**: kiwigrid sidecars (+ their kube-apiserver egress — security win), `downloadDashboards` init container, `deleteDatasources`, `rbac.pspEnabled`, `testFramework`, `GF_EXPLORE_ENABLED` (default true), `grafana.ini` `unified_alerting`/`alerting` blocks (Grafana 11+ defaults), empty `plugins: []`, dead `# renovate: depName=` dashboard annotations.
- [decision] **D9 — blackbox-exporter**: prometheus-community `prometheus-blackbox-exporter` chart via OCIRepository + HelmRelease; modules `icmp` + `tcp_connect` only (no http_2xx until an HTTP probe target exists); `NET_RAW` capability for ICMP; two Probe CRs (`nas` icmp → `nas.lan`, `nfs` tcp_connect → `nas.lan:2049`); chart-level ServiceMonitor + PrometheusRule (`BlackboxProbeFailed`, severity=critical → existing Alertmanager route delivers to Pushover); Grafana dashboard 7587 r3.
- [decision] **D10 — kps gains `probeSelectorNilUsesHelmValues: false`** next to the existing three selector lines.
- [decision] **D11 — Renovate group "Grafana Operator"**: new entry in .renovate/groups.json5 matching `/grafana-operator/` (minimumGroupSize 1, mirror the Envoy Gateway entry at lines 74-81) so the HelmRelease OCIRepository tag and the 00-crds.yaml bootstrap pin bump in one PR.
- [decision] **D12 — datasource CRs ship in the same cutover commit as the instance** (P2), so Grafana never comes up empty; dashboard CRs follow in P3 (same PR recommended — stateless instance repopulates as CRs reconcile).
- [decision] **D13 — NO VictoriaLogs datasource/plugin in Grafana**: logs stay in the VictoriaLogs vmui (logs.${PUBLIC_DOMAIN}, internal gateway). The plugin was the only runtime-downloaded plugin — dropping it removes the startup internet dependency entirely (no GF_INSTALL_PLUGINS) and narrows the grafana CNP: no grafana.com / storage.googleapis.com egress, no victoria-logs:9428 egress. Revert path if in-Grafana log correlation is ever wanted: one GrafanaDatasource CR (with `plugins:`) + re-adding the two CNP rules — see Follow-ups.

## Target file tree (end state)

```
kubernetes/apps/observability/grafana/
├── ks.yaml                          # two Flux Kustomizations: grafana-operator, grafana-instance
├── operator/
│   ├── kustomization.yaml
│   ├── ocirepository.yaml           # oci://ghcr.io/grafana/helm-charts/grafana-operator @ 5.24.0
│   ├── helmrelease.yaml
│   └── ciliumnetworkpolicy.yaml     # operator: apiserver + grafana:3000 + dashboard-URL fetch egress
└── instance/
    ├── kustomization.yaml
    ├── externalsecret.yaml          # MOVED unchanged from app/ (grafana-secret)
    ├── grafana.yaml                 # Grafana CR
    ├── grafanafolder.yaml           # folder: Observability
    ├── httproute.yaml               # both gateways + homepage annotations
    ├── servicemonitor.yaml          # carries current metricRelabelings drops
    └── ciliumnetworkpolicy.yaml     # instance: plugin CDN + gravatar + datasources; ingress from operator

kubernetes/apps/observability/blackbox-exporter/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── ocirepository.yaml           # oci://ghcr.io/prometheus-community/charts/prometheus-blackbox-exporter
    ├── helmrelease.yaml
    ├── probes.yaml                  # Probe: nas (icmp), nfs (tcp_connect :2049)
    ├── grafanadashboard.yaml        # 7587 r3 → folder Observability
    └── ciliumnetworkpolicy.yaml     # egress to ${NAS_IP}/32

DELETED: kubernetes/apps/observability/grafana/app/   (entire directory)
```

Plus per-app `grafanadashboard.yaml`/`grafanadatasource.yaml`/`grafanafolder.yaml` files listed in P3, each added to its directory's `kustomization.yaml`.

## Phase P0 — Preflight (no commits)

1. `kubectl get crd grafanas.grafana.integreatly.org grafanadashboards.grafana.integreatly.org grafanadatasources.grafana.integreatly.org grafanafolders.grafana.integreatly.org`
   - If missing → run `just cluster-bootstrap crds` (renders 00-crds.yaml, applies all pinned CRDs — safe, versions are Renovate-current), then re-check.
2. `flux get ks -n flux-system grafana` and `kubectl -n observability get pods -l app.kubernetes.io/name=grafana` — current grafana healthy (baseline).
3. Snapshot for later diff: `kubectl -n observability get cm,secret,svc -l app.kubernetes.io/instance=grafana`.
4. DNS sanity for P4: from any existing pod with shell, confirm `nas.lan` resolves in-cluster (e.g. `kubectl -n observability exec deploy/grafana -- getent hosts nas.lan` — any pod works). If it does NOT resolve, P4 Probe targets use `${NAS_IP}` instead of `nas.lan` (Flux substitutes in Probe manifests too).

Acceptance: all 4 CRDs present; current grafana Ready; nas.lan resolution answer recorded in the progress note.

## Phase P1 — Deploy the operator (old grafana untouched)

New files. `operator/kustomization.yaml` lists ocirepository, helmrelease, ciliumnetworkpolicy.

`operator/ocirepository.yaml` — keep tag in lockstep with 00-crds.yaml (both 5.24.0 today; D11 group keeps them moving together):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: grafana-operator
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 5.24.0
  url: oci://ghcr.io/grafana/helm-charts/grafana-operator
```

`operator/helmrelease.yaml` (minimal-spec policy: only chartRef/interval/values):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: grafana-operator
spec:
  chartRef:
    kind: OCIRepository
    name: grafana-operator
  interval: 30m
  values:
    serviceMonitor:
      enabled: true
    # VERIFY against `helm show values oci://ghcr.io/grafana/helm-charts/grafana-operator --version 5.24.0`:
    #  - pod-label key (podLabels / labels) → set ingress.home.arpa/prometheus + egress.home.arpa/custom-egress
    #  - resources key → requests {cpu: 10m, memory: 64Mi}, limits {memory: 256Mi} (repo resource policy)
    # If the chart cannot set pod labels, use a Flux postRenderers kustomize patch on the Deployment (nextcloud-style, allowed as last resort).
```

`operator/ciliumnetworkpolicy.yaml` — the operator (a) watches CRs via the API server, (b) provisions via the Grafana HTTP API, (c) downloads `url:`-sourced dashboards itself:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cilium.io/ciliumnetworkpolicy_v2.json
# grafana-operator (AD-023): custom-egress — apiserver watch/reconcile, Grafana provisioning API,
# and url:-sourced dashboard downloads (grafana.com + raw.githubusercontent.com). DNS via cluster CCNP.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: grafana-operator
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: grafana-operator   # VERIFY live pod labels after first deploy
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            app.kubernetes.io/name: grafana
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
    - toFQDNs:
        - matchName: "grafana.com"
        - matchPattern: "*.grafana.com"
        - matchName: "raw.githubusercontent.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

`ks.yaml` — REPLACE the current single Kustomization with two (the old `grafana` Kustomization object stays until P2; in P1 append `grafana-operator` as a second document, keep the old one):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: grafana-operator
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: grafana-operator
  interval: 1h
  path: ./kubernetes/apps/observability/grafana/operator
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: observability
  timeout: 5m
  wait: true
```

Also in P1: add the Renovate group (D11) to `.renovate/groups.json5`:

```json5
{
  description: "Grafana Operator group (Flux chart + bootstrap CRDs, lockstep)",
  groupName: "Grafana Operator",
  matchPackageNames: ["/grafana-operator/"],
  group: { commitMessageTopic: "{{{groupName}}} group" },
  minimumGroupSize: 1,
},
```

Commit (example): `✨ feat(grafana): deploy grafana-operator alongside chart grafana`

Acceptance:
- `flux get ks -n flux-system grafana-operator` Ready
- `kubectl -n observability get deploy grafana-operator` Available; pod labels recorded; CNP `kubectl -n observability get cnp grafana-operator` VALID
- Old grafana still serving (`grafana.${PUBLIC_DOMAIN}` loads)

## Phase P2 — Instance cutover + datasources (ONE atomic commit)

In one commit: create `instance/`, delete `grafana/app/` entirely, replace the old `grafana` Kustomization in `ks.yaml` with `grafana-instance`, and add the datasource CRs at their owners. Flux prunes the old HelmRelease/OCIRepository/CNP; expect a few minutes of UI downtime (acceptable, homelab).

`ks.yaml` — second document (after grafana-operator):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: grafana-instance
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: grafana
  dependsOn:
    - name: grafana-operator
    - name: kube-prometheus-stack
    - name: onepassword-connect
      namespace: external-secrets
  interval: 1h
  path: ./kubernetes/apps/observability/grafana/instance
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: observability
  timeout: 5m
  wait: false
```

`instance/externalsecret.yaml`: move `app/externalsecret.yaml` unchanged (target secret `grafana-secret`, keys `admin-user`/`admin-password`).

`instance/grafana.yaml` — maps every kept `GF_*`/grafana.ini setting into `spec.config`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafana_v1beta1.json
apiVersion: grafana.integreatly.org/v1beta1
kind: Grafana
metadata:
  name: grafana
  labels:
    dashboards: grafana
spec:
  config:
    analytics:
      check_for_updates: "false"
      check_for_plugin_updates: "false"
      reporting_enabled: "false"
      feedback_links_enabled: "false"
    date_formats:
      use_browser_locale: "true"
    log:
      mode: console
    metrics:
      enabled: "true"
    news:
      news_feed_enabled: "false"
    plugins:
      plugin_admin_enabled: "false"
    security:
      allow_embedding: "true"
    server:
      root_url: "https://grafana.${PUBLIC_DOMAIN}"
      enable_gzip: "true"
  disableDefaultAdminSecret: true
  disableDefaultSecurityContext: All
  deployment:
    spec:
      strategy:
        type: Recreate
      template:
        metadata:
          labels:
            app.kubernetes.io/name: grafana
            ingress.home.arpa/gateways: "true"
            ingress.home.arpa/prometheus: "true"
            egress.home.arpa/custom-egress: "true"
        spec:
          containers:
            - name: grafana
              env:
                - name: GF_SECURITY_ADMIN_USER
                  valueFrom:
                    secretKeyRef:
                      name: grafana-secret
                      key: admin-user
                - name: GF_SECURITY_ADMIN_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: grafana-secret
                      key: admin-password
              resources:
                requests:
                  cpu: 10m
                  memory: 180Mi
                limits:
                  memory: 1Gi
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop: ["ALL"]
                seccompProfile:
                  type: RuntimeDefault
              volumeMounts:
                - name: tmp
                  mountPath: /tmp
          securityContext:
            runAsNonRoot: true
            runAsUser: 472
            runAsGroup: 472
            fsGroup: 472
          volumes:
            - name: tmp
              emptyDir: {}
```

- VERIFY after deploy: `grafana-data` is an emptyDir in the generated Deployment (operator default with no PVC). If the operator does NOT default it, add `- name: grafana-data\n  emptyDir: {}` to `volumes`.
- No `persistentVolumeClaim` block (D2). No plugins anywhere (D13) — no `GF_INSTALL_PLUGINS`, no startup downloads.

`instance/httproute.yaml` (D6):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: Grafana
    gethomepage.dev/group: Observability
    gethomepage.dev/icon: grafana.svg
spec:
  hostnames:
    - "grafana.${PUBLIC_DOMAIN}"
  parentRefs:
    - name: envoy-external
      namespace: networking
      sectionName: https
    - name: envoy-internal
      namespace: networking
      sectionName: https
  rules:
    - backendRefs:
        - name: grafana-service
          port: 3000
```

VERIFY the operator-generated Service name/port (`kubectl -n observability get svc | grep grafana`) — default is `grafana-service`:3000.

`instance/servicemonitor.yaml` — carries the current cardinality drops:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/monitoring.coreos.com/servicemonitor_v1.json
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: grafana
spec:
  selector:
    matchLabels:
      dashboards: grafana        # VERIFY: operator propagates CR labels to grafana-service; adjust to actual svc labels
  endpoints:
    - port: grafana              # VERIFY port name on grafana-service (fallback: targetPort 3000)
      metricRelabelings:
        - sourceLabels: ["__name__"]
          regex: "grafana_http_(request_duration|response_size)_seconds_bucket"
          action: drop
        - sourceLabels: ["__name__"]
          regex: "^go_.*"
          action: drop
```

`instance/ciliumnetworkpolicy.yaml` — rewrite of the old grafana CNP: **removed** kube-apiserver (no sidecars), raw.githubusercontent.com + grafana.com + storage.googleapis.com (operator fetches dashboards; no plugins per D13) and victoria-logs:9428 (no VictoriaLogs datasource, D13); **kept** gravatar + Prometheus/Alertmanager datasource egresses; **added** ingress from the operator:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cilium.io/ciliumnetworkpolicy_v2.json
# grafana instance (AD-023): envoy + prometheus ingress via CCNPs; custom-egress → this CNP is the sole
# egress source — gravatar avatars + in-cluster datasources (Prometheus/Alertmanager).
# Operator model: no sidecars (kube-apiserver gone), dashboards fetched by the operator (grafana.com/
# raw.githubusercontent.com gone), no plugins per D13 (plugin CDN + victoria-logs egress gone).
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: grafana
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: grafana
  ingress:
    # operator provisioning API calls
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            app.kubernetes.io/name: grafana-operator
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
  egress:
    - toFQDNs:
        - matchName: "gravatar.com"
        - matchPattern: "*.gravatar.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            app.kubernetes.io/name: prometheus
            app.kubernetes.io/instance: kube-prometheus-stack
      toPorts:
        - ports:
            - port: "9090"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            app.kubernetes.io/name: alertmanager
            app.kubernetes.io/instance: kube-prometheus-stack
      toPorts:
        - ports:
            - port: "9093"
              protocol: TCP
```

Datasource CRs (same commit, at their owners):

`kubernetes/apps/observability/kube-prometheus-stack/app/grafanadatasource.yaml` (+ add to that kustomization.yaml):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafanadatasource_v1beta1.json
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDatasource
metadata:
  name: prometheus
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasource:
    name: Prometheus
    type: prometheus
    access: proxy
    isDefault: true
    url: http://kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090
    jsonData:
      timeInterval: 60s
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafanadatasource_v1beta1.json
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDatasource
metadata:
  name: alertmanager
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasource:
    name: Alertmanager
    type: alertmanager
    access: proxy
    url: http://kube-prometheus-stack-alertmanager.observability.svc.cluster.local:9093
    jsonData:
      implementation: prometheus
      handleGrafanaManagedAlerts: false
```

NO victoria-logs datasource CR (D13) — the old HelmRelease's VictoriaLogs datasource + `GF_PLUGINS_PREINSTALL_SYNC` plugin are dropped, not migrated.

`instance/grafanafolder.yaml` (Observability folder, D4):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafanafolder_v1beta1.json
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaFolder
metadata:
  name: observability
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  title: Observability
```

Commit (example): `♻️ refactor(grafana): migrate instance to grafana-operator CRs`

Acceptance:
- `kubectl -n observability get grafana grafana -o jsonpath='{.status.stage} {.status.stageStatus}'` → `complete success`
- grafana pod 1/1 Running, `kubectl -n observability get cnp grafana` VALID, old chart resources gone (`helm ls -n observability` has no `grafana`)
- UI loads on `grafana.${PUBLIC_DOMAIN}`, admin login works with 1Password creds
- Both datasources (Prometheus, Alertmanager) present and healthy (UI → Connections → Data sources); NO plugin listed under Administration → Plugins beyond the built-ins (D13)
- Homepage shows the Grafana tile (annotation typo fixed)
- `kubectl -n observability get servicemonitor grafana` exists; Prometheus targets page shows grafana UP

## Phase P3 — Dashboard fan-out (same PR as P2 recommended)

Canonical GrafanaDashboard template — expand the table below mechanically; one `grafanadashboard.yaml` per app dir (multi-doc file where an app owns several), plus `grafanafolder.yaml` where the table says the folder lives. Every CR gets `instanceSelector {dashboards: grafana}` and `allowCrossNamespaceImport: true`; add each new file to its directory's `kustomization.yaml`.

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafanadashboard_v1beta1.json
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: <row.name>
spec:
  allowCrossNamespaceImport: true
  instanceSelector:
    matchLabels:
      dashboards: grafana
  folderRef: <row.folderRef>          # GrafanaFolder CR name, SAME namespace as this CR
  datasources:
    - inputName: DS_PROMETHEUS        # check each dashboard's __inputs (see below); some differ
      datasourceName: Prometheus
  url: <row.url>
```

Input-name check per dashboard: `curl -s <url> | jq '.__inputs'` — map every prometheus-type input to `Prometheus`. Known deviation: blackbox 7587 uses `DS_SIGNCL-PROMETHEUS`.

| CR name | File (dir gets the CR) | Folder (folderRef → CR name) | Source URL |
|---|---|---|---|
| k8s-views-global | observability/kube-prometheus-stack/app/grafanadashboard.yaml | Kubernetes (`kubernetes`) | https://grafana.com/api/dashboards/15757/revisions/43/download |
| k8s-views-nodes | same file | Kubernetes | https://grafana.com/api/dashboards/15759/revisions/40/download |
| k8s-views-namespaces | same file | Kubernetes | https://grafana.com/api/dashboards/15758/revisions/44/download |
| k8s-views-pods | same file | Kubernetes | https://grafana.com/api/dashboards/15760/revisions/37/download |
| k8s-volumes | same file | Kubernetes | https://grafana.com/api/dashboards/11454/revisions/14/download |
| node-exporter-full | same file | System (`system`) | https://grafana.com/api/dashboards/1860/revisions/42/download |
| openwrt | same file | System | https://grafana.com/api/dashboards/18153/revisions/2/download |
| flux-cluster | flux-system/flux-instance/app/grafanadashboard.yaml | Flux (`flux`) | https://raw.githubusercontent.com/fluxcd/flux2-monitoring-example/main/monitoring/configs/dashboards/cluster.json |
| flux-control-plane | same file | Flux | https://raw.githubusercontent.com/fluxcd/flux2-monitoring-example/main/monitoring/configs/dashboards/control-plane.json |
| flux-operator-performance | same file | Flux | https://raw.githubusercontent.com/controlplaneio-fluxcd/flux-operator/refs/heads/main/config/monitoring/dashboards/flux-performance.json |
| flux-api-performance | same file | Flux | https://raw.githubusercontent.com/controlplaneio-fluxcd/flux-operator/refs/heads/main/config/monitoring/dashboards/flux-k8s-api-performance.json |
| envoy-gateway-global | networking/envoy-gateway/app/grafanadashboard.yaml | Networking (`networking`) | https://raw.githubusercontent.com/envoyproxy/gateway/refs/heads/main/charts/gateway-addons-helm/dashboards/envoy-gateway-global.json |
| envoy-proxy-global | same file | Networking | https://raw.githubusercontent.com/envoyproxy/gateway/refs/heads/main/charts/gateway-addons-helm/dashboards/envoy-proxy-global.json |
| external-dns | networking/external-dns/app/grafanadashboard.yaml | Networking (folder CR lives in envoy-gateway/app — same namespace, folderRef works) | https://grafana.com/api/dashboards/15038/revisions/3/download |
| cert-manager | cert-manager/cert-manager/app/grafanadashboard.yaml | Cert Manager (`cert-manager`) | https://grafana.com/api/dashboards/20340/revisions/1/download |
| speedtest-exporter | observability/speedtest-exporter/app/grafanadashboard.yaml | Observability (folder CR in grafana/instance — same namespace) | https://grafana.com/api/dashboards/13665/revisions/4/download |
| volsync | volsync-system/volsync/app/grafanadashboard.yaml | Storage (`storage`) | https://grafana.com/api/dashboards/21356/revisions/3/download |
| cilium (+ per-CM siblings) | kube-system/cilium/app/grafanadashboard.yaml | Cilium (`cilium`) | configMapRef, see below |

GrafanaFolder CRs to create (template as in P2, title per D4): `kubernetes` + `system` (kube-prometheus-stack/app/grafanafolder.yaml, two docs), `flux` (flux-instance/app), `networking` (envoy-gateway/app), `cert-manager` (cert-manager/app), `storage` (volsync/app), `cilium` (cilium/app).

Special cases:

1. **cilium — configMapRef sourcing** (the chart-shipped ConfigMaps stay; only the sidecar labels become inert):
   - Enumerate live: `kubectl -n kube-system get cm | grep -i dashboard` (expect cilium-dashboard, cilium-operator-dashboard, hubble-*; each CM has one .json key — check with `kubectl -n kube-system get cm <name> -o jsonpath='{.data}' | jq keys`).
   - One GrafanaDashboard per ConfigMap: `spec.configMapRef: {name: <cm>, key: <file>.json}` instead of `url:`; no `datasources` remap needed (chart dashboards reference datasource by name — VERIFY they render; if they show "datasource not found", add the DS_PROMETHEUS remap).
   - Remove the now-dead `dashboards.annotations.grafana_folder` blocks from cilium values (both at `dashboards:` and `hubble.metrics.dashboards:`); keep `enabled: true` — the CMs are the data source for configMapRef.
2. **victoria-logs — chart-native operator mode**: in victoria-logs/app/helmrelease.yaml set `dashboards.grafanaOperator.enabled: true` and remove the `labels.grafana_dashboard` / `annotations.grafana_folder` lines. VERIFY the chart's values schema (`helm show values` for the pinned victoria-logs-single chart, `dashboards.grafanaOperator.*`) for instanceSelector/allowCrossNamespaceImport spec passthrough — set them to the standard contract. If the chart cannot set the folder, accept General folder (do not fight it). D13 caveat: there is no VictoriaLogs datasource in Grafana — if a chart-emitted dashboard requires the `victoriametrics-logs-datasource` type (not just Prometheus metrics about the server), skip that dashboard (`dashboards.grafanaOperator.enabled: false` and drop this step) rather than re-introducing the plugin.
3. **volsync — RISK R1**: dashboard 21356 has a constant input `VAR_REPLICATIONDESTNAME` (was set to `.*-rdst` in chart values). GrafanaDashboard CRs can only remap datasource inputs. After import, open the dashboard and check the replicationdestname template var; if panels are empty, fallback: vendor the JSON into a ConfigMap (kustomize `configMapGenerator` in volsync/app) with the constant baked in, and switch the CR to `configMapRef`.
4. The old renovate `depName=` comment lines are NOT carried over (dead annotations, D8). Revisions stay hand-pinned in URLs.

Commit (example): `♻️ refactor(observability): co-locate grafana dashboards as operator CRs`

Acceptance:
- `kubectl get grafanadashboard -A` — every CR shows a success condition (`.status.conditions` DashboardSynchronized True / no NoMatchingInstances)
- `kubectl get grafanafolder -A` — 8 folders synced
- UI spot-check: folder tree = Kubernetes, System, Observability, Networking, Flux, Storage, Cilium, Cert Manager; open 1 dashboard per folder and confirm panels render (especially volsync → R1, cilium → datasource binding)

## Phase P4 — blackbox-exporter (independent of P2/P3, requires P1 for the dashboard CR)

New app dir `kubernetes/apps/observability/blackbox-exporter/`; add `./blackbox-exporter/ks.yaml` to `kubernetes/apps/observability/kustomization.yaml`.

`ks.yaml` (pattern: current speedtest-exporter; no dependsOn needed — Probe/ServiceMonitor CRDs are bootstrap-installed; the GrafanaDashboard needs grafana-operator which is already live after P1):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: blackbox-exporter
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: blackbox-exporter
  interval: 1h
  path: ./kubernetes/apps/observability/blackbox-exporter/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: observability
  timeout: 5m
  wait: false
```

`app/ocirepository.yaml`: `oci://ghcr.io/prometheus-community/charts/prometheus-blackbox-exporter`, tag `11.15.1` (VERIFY latest at implementation time — Renovate tracks it afterwards); same layerSelector block as every other OCIRepository in the repo.

`app/helmrelease.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: blackbox-exporter
spec:
  chartRef:
    kind: OCIRepository
    name: blackbox-exporter
  interval: 30m
  values:
    fullnameOverride: blackbox-exporter
    image:
      registry: quay.io
    # VERIFY chart's pod-label key (podLabels vs pod.labels) via helm show values:
    podLabels:
      ingress.home.arpa/prometheus: "true"
      egress.home.arpa/custom-egress: "true"
    config:
      modules:
        icmp:
          prober: icmp
          timeout: 5s
          icmp:
            preferred_ip_protocol: ip4
        tcp_connect:
          prober: tcp
          timeout: 5s
          tcp:
            preferred_ip_protocol: ip4
    securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        add: ["NET_RAW"]   # ICMP prober
        drop: ["ALL"]
    resources:
      requests:
        cpu: 5m
        memory: 32Mi
      limits:
        memory: 64Mi
    serviceMonitor:
      enabled: true
      defaults:
        interval: 1m
        scrapeTimeout: 10s
    prometheusRule:
      enabled: true
      rules:
        - alert: BlackboxProbeFailed
          expr: probe_success == 0
          for: 15m
          labels:
            severity: critical
          annotations:
            summary: |-
              Blackbox probe failed for {{ $labels.instance }} (job {{ $labels.job }})
```

Note: `severity: critical` rides the existing Alertmanager route → Pushover; no AlertmanagerConfig change needed.

`app/probes.yaml` (use `${NAS_IP}` instead of nas.lan ONLY if P0 step 4 showed nas.lan does not resolve in-cluster):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/monitoring.coreos.com/probe_v1.json
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata:
  name: nas
spec:
  module: icmp
  prober:
    url: blackbox-exporter.observability.svc.cluster.local:9115
  targets:
    staticConfig:
      static:
        - nas.lan
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/monitoring.coreos.com/probe_v1.json
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata:
  name: nfs
spec:
  module: tcp_connect
  prober:
    url: blackbox-exporter.observability.svc.cluster.local:9115
  targets:
    staticConfig:
      static:
        - nas.lan:2049
```

`app/ciliumnetworkpolicy.yaml` — single all-protocol grant to the NAS (covers ICMP echo + TCP 2049 without Cilium ICMP-rule complexity; the NAS is a trusted LAN host):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cilium.io/ciliumnetworkpolicy_v2.json
# blackbox-exporter (AD-023): custom-egress — sole egress is the NAS (ICMP echo + NFS tcp/2049 probes).
# One unrestricted rule to ${NAS_IP}/32 instead of per-protocol rules (trusted LAN host). DNS via cluster CCNP.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: blackbox-exporter
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: prometheus-blackbox-exporter   # VERIFY live pod labels (fullnameOverride may change this)
  egress:
    - toCIDR:
        - ${NAS_IP}/32
```

`app/grafanadashboard.yaml` — folder + dashboard (bjw-s uses 7587 r3; folder is the shared Observability CR from P2, same namespace):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafanadashboard_v1beta1.json
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: blackbox-exporter
spec:
  allowCrossNamespaceImport: true
  instanceSelector:
    matchLabels:
      dashboards: grafana
  folderRef: observability
  datasources:
    - inputName: DS_SIGNCL-PROMETHEUS
      datasourceName: Prometheus
  url: https://grafana.com/api/dashboards/7587/revisions/3/download
```

kube-prometheus-stack change (D10) — in kube-prometheus-stack/app/helmrelease.yaml, next to the existing three selector lines add:

```yaml
        probeSelectorNilUsesHelmValues: false
```

IAM note: blackbox-exporter has NO route/UI (scrape-only, like speedtest-exporter) — per docs/areas/iam §3 its IAM policy is satisfied by the CNP + prometheus-only ingress; no OIDC.

Commit (example): `✨ feat(blackbox-exporter): probe nas.lan ICMP + NFS tcp/2049`

Acceptance:
- pod Running with NET_RAW only; CNP VALID
- `kubectl -n observability get probe nas nfs` exist; Prometheus targets page shows both probe jobs UP
- PromQL `probe_success{job=~"nas|nfs"}` returns 1 for both targets (Grafana Explore)
- Test the alert path: block is optional — at minimum confirm the rule loaded: `kubectl -n observability get prometheusrule | grep blackbox`
- Dashboard 7587 renders in the Observability folder

## Phase P5 — SSO: Kanidm OIDC (iam Path A; after P2 is verified stable)

**HUMAN GATE (before any commit):**
1. Kanidm UI: create OIDC client `Grafana`, callback URL `https://grafana.<public-domain>/login/generic_oauth`.
2. Kanidm UI: create groups `grafana_users` and `grafana_administrators`; add the admin user to `grafana_administrators`.
3. 1Password: add `GRAFANA_OAUTH_CLIENT_ID` + `GRAFANA_OAUTH_CLIENT_SECRET` fields to the existing `grafana` item.

Then, in one commit:

1. **VERIFY Kanidm endpoint paths** from the client's discovery document (per-client, at the Kanidm OAuth2 client's issuer under `/.well-known/openid-configuration`) and use those exact URLs below.

2. `instance/externalsecret.yaml` — extend the template:

```yaml
        oauth-client-id: "{{ .GRAFANA_OAUTH_CLIENT_ID }}"
        oauth-client-secret: "{{ .GRAFANA_OAUTH_CLIENT_SECRET }}"
```

3. `instance/grafana.yaml` — add to `spec.config` (URLs from step 1; shown with the expected Kanidm paths):

```yaml
    auth:
      disable_login_form: "false"   # break-glass admin login (D5)
    auth.generic_oauth:
      enabled: "true"
      name: Kanidm
      scopes: "openid profile email groups"
      auth_url: "https://idm.${PUBLIC_DOMAIN}/ui/oauth2"
      token_url: "https://idm.${PUBLIC_DOMAIN}/oauth2/token"
      api_url: "https://idm.${PUBLIC_DOMAIN}/oauth2/openid/grafana/userinfo"
      use_pkce: "true"
      email_attribute_path: email
      login_attribute_path: preferred_username
      name_attribute_path: name
      groups_attribute_path: groups
      role_attribute_path: "contains(groups[*], 'grafana_administrators') && 'GrafanaAdmin' || contains(groups[*], 'grafana_users') && 'Viewer'"
      role_attribute_strict: "true"
      allow_assign_grafana_admin: "true"
      auto_login: "false"
```

   and add to the grafana container `env`:

```yaml
                - name: GF_AUTH_GENERIC_OAUTH_CLIENT_ID
                  valueFrom:
                    secretKeyRef:
                      name: grafana-secret
                      key: oauth-client-id
                - name: GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
                  valueFrom:
                    secretKeyRef:
                      name: grafana-secret
                      key: oauth-client-secret
```

4. `instance/ciliumnetworkpolicy.yaml` — the token/userinfo/JWKS calls are server-side from the grafana pod to the public issuer host; add an egress rule:

```yaml
    # Kanidm OIDC — server-side token/userinfo/JWKS calls to the public issuer host
    - toFQDNs:
        - matchName: "idm.${PUBLIC_DOMAIN}"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

   VERIFY after deploy: if login fails at the token exchange, run `hubble observe --pod observability/grafana --verdict DROPPED` — in-cluster the hostname resolves through k8s-gateway split DNS to the internal Envoy VIP; the toFQDNs rule covers whatever IP DNS returns, but confirm the hairpin path actually flows.

Commit (example): `✨ feat(grafana): kanidm oidc login (grafana_users/administrators groups)`

Acceptance:
- Sign-in page shows "Sign in with Kanidm"; passkey login succeeds for a `grafana_administrators` member and lands with Grafana admin rights
- A Kanidm user in NEITHER group is rejected (`role_attribute_strict`)
- Break-glass: direct admin login with the 1Password admin creds still works
- ExternalSecret Ready with the two new keys; CNP still VALID

## Phase P6 — Docs & knowledge base

1. Update BM `docs/areas/observability`: grafana section (operator model, stateless, CR contract, CNP changes, Kanidm SSO), new blackbox-exporter component, kps probeSelector line; bump `verified_at`.
1b. Update BM `docs/areas/iam`: Grafana joins the OIDC-native (Path A) app list with its group names and break-glass note.
2. Add an entry to the AD-023 audit progress note (`docs/progress/cnp-per-app-audit`): two new custom-egress CNPs (grafana-operator, blackbox-exporter), grafana CNP narrowed (apiserver + raw.githubusercontent removed).
3. Update BM `docs/areas/k8s-workloads` only if its app inventory lists grafana explicitly.
4. Progress note `docs/progress/grafana-operator-migration`: session summaries per phase, deviations, VERIFY outcomes (pod labels, service name/port, chart value keys, R1 result).
5. Commit-doc-commit pattern per session as usual.

## Risks / explicit VERIFY inventory

- [risk] R1 — volsync dashboard 21356 constant input `VAR_REPLICATIONDESTNAME` cannot be remapped by GrafanaDashboard CRs; fallback = vendored ConfigMap (P3 step 3).
- [risk] R2 — operator/instance chart-value and generated-object names (pod labels, service name `grafana-service`, service port name, grafana-data emptyDir default, grafana-operator/blackbox chart podLabels+resources keys, victoria-logs grafanaOperator values schema) are pinned as VERIFY steps; record actuals in the progress note.
- [risk] R3 — cutover window (P2): UI down for minutes while Flux prunes the chart release and the operator provisions; stateless, nothing to migrate or lose.
- [risk] R4 — CNP: if the operator cannot reach grafana.com, `url:`-sourced dashboards stay Pending — check operator logs first (`kubectl -n observability logs deploy/grafana-operator`), then `hubble observe --verdict DROPPED` for the operator pod.
- [risk] R5 — grafana chart 12.x ships Grafana 12 (Angular removed); the operator-default grafana image may be a different major than the chart shipped. All current dashboards render on the current version; after P3 spot-check confirms parity. If a dashboard breaks on version skew, pin `deployment.spec.template.spec.containers[grafana].image` and record it as a deviation.

## Success criteria (overall)

- [criterion] Old grafana chart fully removed (no HelmRelease/OCIRepository `grafana` in observability; `helm ls -n observability` clean)
- [criterion] Grafana reachable at grafana.${PUBLIC_DOMAIN} on both gateways, admin login works, homepage tile OK
- [criterion] Both datasources (Prometheus, Alertmanager) + all dashboards from the P3 table present and rendering; folder tree matches D4; zero plugins installed (D13)
- [criterion] No pod in the cluster retains sidecar-era labels consumption (kiwigrid sidecars gone; grafana pod has NO kube-apiserver egress)
- [criterion] SSO: Kanidm login works with group-based roles (`grafana_administrators` → GrafanaAdmin, `grafana_users` → Viewer, others rejected); break-glass admin form still functional — Grafana no longer an IAM exception (docs/areas/iam §3)
- [criterion] blackbox-exporter probing nas.lan (icmp) + nas.lan:2049 (tcp): `probe_success == 1` for both; BlackboxProbeFailed alert loaded and routed severity=critical
- [criterion] Renovate: Grafana Operator group bumps HR tag + 00-crds pin together; blackbox chart tracked via the oci:// manager
- [criterion] BM notes updated (observability area, cnp-per-app-audit progress, this roadmap → status done via progress note)

## Follow-ups (explicitly OUT of scope)

- [follow-up] Retire the break-glass admin login form (`disable_login_form: true`) once Kanidm SSO has proven stable over a few weeks
- [follow-up] Revisit persistence (PVC + VolSync) only if a concrete stateful need appears (user prefs, alert silences)
- [follow-up] grafana-operator self-dashboard (chart `dashboard.enabled` + configMapRef CR) if operator observability becomes interesting
- [follow-up] http_2xx blackbox module + probes for LAN HTTP endpoints (OMV UI, router) if desired later
- [follow-up] VictoriaLogs datasource in Grafana (D13 revert) — only if in-Grafana metric↔log correlation becomes desirable: one GrafanaDatasource CR at victoria-logs/app with `plugins: [{name: victoriametrics-logs-datasource, version: <pinned>}]` + grafana CNP re-gains grafana.com/storage.googleapis.com (plugin download) and victoria-logs:9428 egress; note this re-introduces the startup plugin-download dependency (stateless instance)
- [follow-up] Dead-man's-switch / heartbeat receiver (carried over from alertmanager-introduction follow-ups)

## Relations

- relates_to [[observability]]
- relates_to [[iam]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- decided_in [[AD-023-cnp-threat-model-audit]]
- continues [[alertmanager-introduction]]
