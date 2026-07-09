---
title: grafana-operator-migration
type: roadmap
permalink: home-ops/docs/roadmap/grafana-operator-migration
topic: Re-implement Grafana with grafana-operator (operator/instance split, decentralized
  dashboard/datasource CRs, Pocket-ID SSO) + blackbox-exporter probing nas.lan ICMP
  + NFS tcp/2049
status: planned
priority: medium
scope: Execution-grade roadmap. Contains the full YAML of every new/changed manifest,
  the per-app dashboard placement table, CNP rewrites under AD-023, the Pocket-ID
  OIDC wiring, per-phase verify commands and acceptance criteria. An executor should
  work through P0-P6 without design decisions; live-state checks are marked VERIFY,
  human-only steps are marked HUMAN GATE, undecided items live under Follow-ups.
rationale: Aligns with bjw-s-labs/home-ops and onedr0p/home-ops best practice (operator/instance
  split, dashboards-as-CRs co-located with owning apps), removes the kiwigrid sidecars
  and the grafana pod's kube-apiserver egress, and turns dashboard/datasource state
  fully declarative. No Grafana plugins at all (VictoriaLogs stays in vmui, D13) -
  zero startup internet dependency. SSO via Pocket-ID closes Grafana's IAM exception
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
- 'P5: SSO - Pocket-ID OIDC (HUMAN GATE: client + groups + 1Password fields)'
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
---

# Grafana re-implementation on grafana-operator + blackbox-exporter — execution-grade roadmap

## Metadata (observation-form, schema validation)

- [topic] Re-implement Grafana with grafana-operator (operator/instance split, decentralized dashboard/datasource CRs) + new blackbox-exporter probing nas.lan (ICMP) and its NFS service (TCP 2049)
- [status] planned
- [progress] Execution state will live in [[grafana-operator-migration]] (docs/progress) — create it at P1 start from this note's phase list
- [priority] medium

## Goal

Replace the standalone `grafana` Helm chart deployment (`kubernetes/apps/observability/grafana/`) with the **grafana-operator** pattern used by bjw-s-labs/home-ops and onedr0p/home-ops: the operator deployed by HelmRelease, the Grafana instance as a `Grafana` CR, datasources/dashboards/folders as `GrafanaDatasource`/`GrafanaDashboard`/`GrafanaFolder` CRs **co-located with the app that owns them**. Add a **blackbox-exporter** app (prometheus-blackbox-exporter chart) with `Probe` CRs for nas.lan reachability (ICMP) and the NFS service (TCP 2049), modeled on bjw-s.

The end state also closes Grafana's IAM exception: **SSO via Pocket-ID OIDC** (iam area "Path A"), per the standing policy that no app ships without an IAM policy (see docs/areas/iam §3).

An executor should be able to work through P0–P6 without making design decisions. Anything the executor must check against the live cluster or chart values is explicitly marked **VERIFY**. Anything undecided is under Open questions / Follow-ups. Steps requiring the human (Pocket-ID UI, 1Password fields) are marked **HUMAN GATE** — in agent mode these are escalation points.

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
- [decision] **D5 — SSO via Pocket-ID OIDC IS in scope (P5)**: Grafana becomes an OIDC-native app (iam Path A: Pocket-ID client + `grafana_users`/`grafana_administrators` groups + `auth.generic_oauth`). Role mapping: `grafana_administrators` → GrafanaAdmin, `grafana_users` → Viewer, `role_attribute_strict` (no mapped group = no access). The admin login form STAYS enabled as documented break-glass (`disable_login_form: false`) with creds from the existing `grafana-secret`. SSO lands as its own phase AFTER the cutover is verified, because it depends on a HUMAN GATE (Pocket-ID client creation + 1Password fields).
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

IAM note: blackbox-exporter has NO route/UI (scrape-only, like speedtest-exporter) — per docs/areas/iam §3 its IAM policy is satisfied by the CNP + prometheus-only ingress; no OIDC/forward-auth applies.

Commit (example): `✨ feat(blackbox-exporter): probe nas.lan ICMP + NFS tcp/2049`

Acceptance:
- pod Running with NET_RAW only; CNP VALID
- `kubectl -n observability get probe nas nfs` exist; Prometheus targets page shows both probe jobs UP
- PromQL `probe_success{job=~"nas|nfs"}` returns 1 for both targets (Grafana Explore)
- Test the alert path: block is optional — at minimum confirm the rule loaded: `kubectl -n observability get prometheusrule | grep blackbox`
- Dashboard 7587 renders in the Observability folder

## Phase P5 — SSO: Pocket-ID OIDC (iam Path A; after P2 is verified stable)

**HUMAN GATE (before any commit):**
1. Pocket-ID UI: create OIDC client `Grafana`, callback URL `https://grafana.<public-domain>/login/generic_oauth`.
2. Pocket-ID UI: create groups `grafana_users` and `grafana_administrators`; add the admin user to `grafana_administrators`.
3. 1Password: add `GRAFANA_OAUTH_CLIENT_ID` + `GRAFANA_OAUTH_CLIENT_SECRET` fields to the existing `grafana` item.

Then, in one commit:

1. **VERIFY Pocket-ID endpoint paths** from the discovery document (`curl -s https://id.<public-domain>/.well-known/openid-configuration | jq '{authorization_endpoint, token_endpoint, userinfo_endpoint}'`) and use those exact URLs below.

2. `instance/externalsecret.yaml` — extend the template:

```yaml
        oauth-client-id: "{{ .GRAFANA_OAUTH_CLIENT_ID }}"
        oauth-client-secret: "{{ .GRAFANA_OAUTH_CLIENT_SECRET }}"
```

3. `instance/grafana.yaml` — add to `spec.config` (URLs from step 1; shown with the expected Pocket-ID paths):

```yaml
    auth:
      disable_login_form: "false"   # break-glass admin login (D5)
    auth.generic_oauth:
      enabled: "true"
      name: Pocket-ID
      scopes: "openid profile email groups"
      auth_url: "https://id.${PUBLIC_DOMAIN}/authorize"
      token_url: "https://id.${PUBLIC_DOMAIN}/api/oidc/token"
      api_url: "https://id.${PUBLIC_DOMAIN}/api/oidc/userinfo"
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
    # Pocket-ID OIDC — server-side token/userinfo/JWKS calls to the public issuer host
    - toFQDNs:
        - matchName: "id.${PUBLIC_DOMAIN}"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

   VERIFY after deploy: if login fails at the token exchange, run `hubble observe --pod observability/grafana --verdict DROPPED` — in-cluster the hostname resolves through k8s-gateway split DNS to the internal Envoy VIP; the toFQDNs rule covers whatever IP DNS returns, but confirm the hairpin path actually flows.

Commit (example): `✨ feat(grafana): pocket-id oidc login (grafana_users/administrators groups)`

Acceptance:
- Sign-in page shows "Sign in with Pocket-ID"; passkey login succeeds for a `grafana_administrators` member and lands with Grafana admin rights
- A Pocket-ID user in NEITHER group is rejected (`role_attribute_strict`)
- Break-glass: direct admin login with the 1Password admin creds still works
- ExternalSecret Ready with the two new keys; CNP still VALID

## Phase P6 — Docs & knowledge base

1. Update BM `docs/areas/observability`: grafana section (operator model, stateless, CR contract, CNP changes, Pocket-ID SSO), new blackbox-exporter component, kps probeSelector line; bump `verified_at`.
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
- [criterion] SSO: Pocket-ID login works with group-based roles (`grafana_administrators` → GrafanaAdmin, `grafana_users` → Viewer, others rejected); break-glass admin form still functional — Grafana no longer an IAM exception (docs/areas/iam §3)
- [criterion] blackbox-exporter probing nas.lan (icmp) + nas.lan:2049 (tcp): `probe_success == 1` for both; BlackboxProbeFailed alert loaded and routed severity=critical
- [criterion] Renovate: Grafana Operator group bumps HR tag + 00-crds pin together; blackbox chart tracked via the oci:// manager
- [criterion] BM notes updated (observability area, cnp-per-app-audit progress, this roadmap → status done via progress note)

## Follow-ups (explicitly OUT of scope)

- [follow-up] Retire the break-glass admin login form (`disable_login_form: true`) once Pocket-ID SSO has proven stable over a few weeks
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
