---
title: alertmanager-introduction
type: roadmap
permalink: home-ops/docs/roadmap/alertmanager-introduction
status: planned
confidence: high
area: observability
created: '2026-07-05'
summary: 'Introduce Prometheus Alertmanager into the minified kube-prometheus-stack
  and migrate Flux reconciliation alerting off the custom flux-provider-pushover relay
  onto Alertmanager, following the onedr0p/bjw-s reference pattern. Phased so there
  is never an alerting gap. Decisions locked: phased replace (retire relay at the
  end), internal-gateway Alertmanager UI, no heartbeat/dead-man''s-switch yet, extended
  rule scope (node + nodeExporterAlerting + OOMKilled + general).'
tags:
- roadmap
- observability
- alerting
- alertmanager
- flux
---

# Roadmap: Alertmanager introduction + Flux alert migration

## Metadata (observation-form)

- [area] observability
- [status] planned
- [confidence] high
- [created] 2026-07-05
- [complexity] medium-large (three phases, spans observability + flux-system + components/common)

## Why

Today the minified `kube-prometheus-stack` ships Alertmanager **disabled**. Several
default rule groups are already enabled (`k8s`, `kubernetesApps`, `kubeStateMetrics`,
`prometheus`, `prometheusOperator`) so Prometheus is **evaluating alert rules that go
nowhere** — there is no notification sink for metric-based alerts. Only Flux
reconciliation failures page, and they do so through a **custom self-authored relay**
(`ghcr.io/zhorvath83/flux-provider-pushover`) fed by a Flux generic-webhook Provider.

Enabling Alertmanager instantly activates the already-present rules, and the Flux
notification-controller has a **native `type: alertmanager` Provider** that lets Flux
events flow into the same Alertmanager. That collapses two Pushover paths into one and
retires a maintained container image.

## Locked decisions (from planning session 2026-07-05)

- [decision] Relay end-state = **phased replace, eventual retirement**. Stand up Alertmanager in parallel, add the Flux type:alertmanager Provider, verify, THEN delete the custom relay + generic Provider + flux-alerts Alert. No alerting gap at any point.
- [decision] Alertmanager UI = **internal gateway route only** (`alertmanager.${PUBLIC_DOMAIN}` on envoy-internal, like grafana/logs). LAN-only.
- [decision] Heartbeat / dead-man's-switch = **skipped for now** (no external uptime monitor). Watchdog can be wired later as a follow-up if healthchecks.io / gatus / Uptime-Kuma appears.
- [decision] Rule scope = **extended**: keep current groups, additionally enable `general` (Watchdog + InfoInhibitor), `node`, `nodeExporterAlerting`, `nodeExporterRecording`; add a custom OOMKilled PrometheusRule.
- [decision] GitHub commit-status Provider/Alert (`components/common/alerts/github/`) is a different function (commit statuses) and **stays untouched**.

## Reference alignment (what bjw-s + onedr0p do)

- [reference] Both enable Alertmanager via `alertmanager.route.main` (Gateway API, envoy-internal) + `alertmanager.alertmanagerSpec` with `alertmanagerConfiguration.name: alertmanager`, `externalUrl`, and a 1Gi PVC.
- [reference] Both ship an `AlertmanagerConfig` CR (`monitoring.coreos.com/v1alpha1`) named `alertmanager`: default receiver = pushover (rich HTML template, sendResolved), a `blackhole` receiver for InfoInhibitor, a Watchdog route to a heartbeat, and inhibitRules (critical inhibits warning on same alertname+namespace). We drop the heartbeat route/receiver per decision.
- [reference] Both ship an `ExternalSecret` named `alertmanager` targeting secret `alertmanager-secret` with pushover token + userkey pulled from 1Password.
- [reference] Neither customizes `defaultRules` (full chart defaults, multi-node). Our repo stays minified but widens the enabled set per the extended-scope decision.
- [reference] Custom PrometheusRules: OOMKilled (both), ZFS (both), DockerHub rate-limit (onedr0p). We take **OOMKilled only** (ZFS/DockerHub not applicable here).
- [reference] **onedr0p replaces its custom Flux to Pushover path exactly the way we plan**: `kubernetes/components/alerts/alertmanager/` holds a Flux `Provider` `type: alertmanager` (address `http://alertmanager-operated.<ns>.svc.cluster.local:9093/api/v2/alerts/`) + an `Alert` covering all Flux event kinds. Canonical template for Phase 2.

## Target end-state

- Alertmanager running in `observability`, 1Gi local-hostpath PVC, internal-gateway route.
- One `AlertmanagerConfig` (pushover + blackhole + InfoInhibitor route + inhibitRules).
- `alertmanager-secret` via ExternalSecret from 1Password.
- Extended default rules + OOMKilled custom rule.
- Flux reconciliation errors delivered through Alertmanager (Flux `type: alertmanager` Provider), not the custom relay.
- Retired: `flux-provider-pushover` app, generic `pushover` Provider, `flux-alerts` Alert.
- Kept: GitHub commit-status Provider/Alert.

---

## MANUAL PREREQUISITE (human, before Phase 1 deploy)

- [prereq] In the **Pushover dashboard**, create a new Application named `Alertmanager` and copy its API token. In **1Password**, open the existing `pushover` item (the one already backing the relay) and add a field `PUSHOVER_ALERTMANAGER_TOKEN` with that token. Do NOT reuse `PUSHOVER_FLUXCD_API_KEY` — keep sources distinguishable in Pushover. `PUSHOVER_USER_KEY` already exists and is reused as-is.
- [note] This step cannot be done by the executor AI (external dashboard + secret manager). Hard gate for Phase 1: the ExternalSecret will not become Ready without `PUSHOVER_ALERTMANAGER_TOKEN`.

---

## Phase 1 — Alertmanager + config + rules (parallel, no Flux change yet)

All paths under `kubernetes/apps/observability/kube-prometheus-stack/app/`.

### 1.1 Edit `helmrelease.yaml`

- [step] Replace the `AlertManager - DISABLED` block (currently `alertmanager.enabled: false`) with:

```yaml
    alertmanager:
      enabled: true
      route:
        main:
          enabled: true
          hostnames:
            - "alertmanager.${PUBLIC_DOMAIN}"
          parentRefs:
            - name: envoy-internal
              namespace: networking
              sectionName: https
      alertmanagerSpec:
        alertmanagerConfiguration:
          name: alertmanager
        externalUrl: "https://alertmanager.${PUBLIC_DOMAIN}"
        podMetadata:
          labels:
            ingress.home.arpa/gateways: "true"
            ingress.home.arpa/prometheus: "true"
        resources:
          requests:
            cpu: 5m
            memory: 48Mi
          limits:
            memory: 128Mi
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: democratic-csi-local-hostpath
              accessModes:
                - "ReadWriteOnce"
              resources:
                requests:
                  storage: 1Gi
```

- [step] In `defaultRules.rules`, flip to `true`: `general`, `node`, `nodeExporterAlerting`, `nodeExporterRecording`. Leave the rest as-is. (`general` gives Watchdog + InfoInhibitor, which the AlertmanagerConfig routes/inhibits.)
- [check] Mirror AD-023 labels + the exact envoy-internal `sectionName`/`namespace` from `../grafana/app/helmrelease.yaml` and `../victoria-logs/app/helmrelease.yaml`. The gateway namespace in this repo is `networking` (not `network` as in upstream references) — confirm before commit.

### 1.2 New file `externalsecret.yaml`

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: alertmanager
spec:
  refreshInterval: 12h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: alertmanager-secret
    creationPolicy: Owner
    template:
      data:
        pushover_api_token: "{{ .PUSHOVER_ALERTMANAGER_TOKEN }}"
        pushover_api_userkey: "{{ .PUSHOVER_USER_KEY }}"
  dataFrom:
    - extract:
        key: pushover
```

### 1.3 New file `alertmanagerconfig.yaml`

Adapted from onedr0p/bjw-s, heartbeat removed:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/monitoring.coreos.com/alertmanagerconfig_v1alpha1.json
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: alertmanager
spec:
  route:
    groupBy:
      - alertname
      - job
    groupWait: 1m
    groupInterval: 5m
    repeatInterval: 12h
    receiver: pushover
    routes:
      - receiver: blackhole
        matchers:
          - name: alertname
            value: InfoInhibitor
            matchType: =
      - receiver: pushover
        matchers:
          - name: severity
            value: critical
            matchType: =
  inhibitRules:
    - equal:
        - alertname
        - namespace
      sourceMatch:
        - name: severity
          value: critical
          matchType: =
      targetMatch:
        - name: severity
          value: warning
          matchType: =
  receivers:
    - name: blackhole
    - name: pushover
      pushoverConfigs:
        - html: true
          sendResolved: true
          sound: gamelan
          ttl: 86400s
          priority: |-
            {{ if eq .Status "firing" }}1{{ else }}0{{ end }}
          title: >-
            [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .CommonLabels.alertname }}
          message: |-
            {{- range .Alerts }}
              {{- if ne .Annotations.description "" }}
                {{ .Annotations.description }}
              {{- else if ne .Annotations.summary "" }}
                {{ .Annotations.summary }}
              {{- else }}
                Alert description not available
              {{- end }}
              {{- if gt (len .Labels.SortedPairs) 0 }}
                <small>
                  {{- range .Labels.SortedPairs }}
                    <b>{{ .Name }}:</b> {{ .Value }}
                  {{- end }}
                </small>
              {{- end }}
            {{- end }}
          token:
            name: alertmanager-secret
            key: pushover_api_token
          userKey:
            name: alertmanager-secret
            key: pushover_api_userkey
          urlTitle: View in Alertmanager
```

### 1.4 New dir `prometheusrules/` (oomkilled.yaml + kustomization.yaml)

`oomkilled.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/monitoring.coreos.com/prometheusrule_v1.json
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: oom-alert
spec:
  groups:
    - name: oom
      rules:
        - alert: OOMKilled
          annotations:
            description: Container {{ $labels.container }} in pod {{ $labels.namespace }}/{{ $labels.pod }} has been OOMKilled {{ $value }} times in the last 10 minutes.
          expr: (kube_pod_container_status_restarts_total - kube_pod_container_status_restarts_total offset 10m >= 1) and ignoring (reason) min_over_time(kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}[10m]) == 1
          labels:
            severity: critical
```

`prometheusrules/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./oomkilled.yaml
```

### 1.5 Edit `ciliumnetworkpolicy.yaml`

- [step] Add a CiliumNetworkPolicy for the alertmanager endpoint (`app.kubernetes.io/name: alertmanager`) allowing **ingress** from (a) the envoy-internal gateway on 9093 (UI) and (b) the flux-system notification-controller on 9093 (needed in Phase 2; pre-provisioning now is harmless).
- [check] Do NOT hand-invent selectors. Read BM `docs/areas/networking` + the `security-review`/`networking-platform` skill and mirror an existing cross-namespace ingress post-V3-flip. The AD-023 `ingress.home.arpa/gateways` pod label from 1.1 may already cover the gateway path; the flux-system to alertmanager path likely needs an explicit rule.

### 1.6 Edit `kustomization.yaml`

- [step] Add `./externalsecret.yaml`, `./alertmanagerconfig.yaml`, `./prometheusrules` to `resources`. Keep existing entries.

### 1.7 Commit + reconcile + VERIFY (Phase 1 gate)

- [verify] After commit + push: `just k8s flux-reconcile` (or `flux reconcile ks kube-prometheus-stack`).
- [verify] `kubectl -n observability get externalsecret alertmanager` Ready=True (else the 1Password prereq is missing). Direct Secret reads are DENIED — use ExternalSecret status, not `kubectl get secret`.
- [verify] `kubectl -n observability get alertmanager,pods -l app.kubernetes.io/name=alertmanager` pod Running/Ready, PVC Bound.
- [verify] `kubectl -n observability get prometheusrule` shows `oom-alert` + the newly enabled default groups.
- [verify] Reach `https://alertmanager.${PUBLIC_DOMAIN}` from LAN; Status shows the pushover receiver config.
- [verify] **End-to-end Pushover test**: confirm a real alert reaches the phone. Watchdog (always-firing, from `general`) is the cleanest signal. Alternatively fire a synthetic alert with `amtool alert add`. Record the method in the progress note.

---

## Phase 2 — Flux reconciliation errors via Alertmanager

New dir `kubernetes/components/common/alerts/alertmanager/` (mirrors onedr0p `components/alerts/alertmanager/`).

### 2.1 `provider.yaml`

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/notification.toolkit.fluxcd.io/provider_v1beta3.json
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: alertmanager
spec:
  type: alertmanager
  address: http://alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/
```

### 2.2 `alert.yaml`

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/notification.toolkit.fluxcd.io/alert_v1beta3.json
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: alertmanager
spec:
  providerRef:
    name: alertmanager
  eventSeverity: error
  eventSources:
    - kind: FluxInstance
      name: "*"
    - kind: GitRepository
      name: "*"
    - kind: HelmRelease
      name: "*"
    - kind: HelmRepository
      name: "*"
    - kind: Kustomization
      name: "*"
    - kind: OCIRepository
      name: "*"
  exclusionList:
    - "error.*lookup github\\.com"
    - "error.*lookup raw\\.githubusercontent\\.com"
    - "dial.*tcp.*timeout"
    - "waiting.*socket"
  suspend: false
```

### 2.3 `kustomization.yaml`

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./alert.yaml
  - ./provider.yaml
```

### 2.4 Edit `kubernetes/components/common/alerts/kustomization.yaml`

- [step] Add `./alertmanager` to `resources` (alongside `./pushover` and `./github`). This deploys the Provider+Alert into every namespace pulling in the common component — same fan-out as `pushover`/`github`.
- [note] The address is a fixed cluster-DNS name to observability; a per-namespace Provider is fine (Flux resolves the cross-namespace Service URL), mirroring how the generic `pushover` Provider already points at the flux-system relay Service from every namespace.

### 2.5 Commit + reconcile + VERIFY (Phase 2 gate)

- [verify] `kubectl get provider,alert -A | grep alertmanager` present, Ready=True.
- [verify] Generate a benign Flux error and confirm it reaches Pushover **via Alertmanager** (Alertmanager UI shows the Flux alert; phone gets it). Safe way: throwaway test Kustomization/HelmRelease with a bad ref on a branch, revert after.
- [verify] During Phase 2 BOTH paths (old relay + new Alertmanager) are active — expected, confirms no gap before Phase 3.

---

## Phase 3 — Retire the custom relay (only after Phase 2 verified)

### 3.1 Remove the relay app

- [step] Delete `kubernetes/apps/flux-system/flux-provider-pushover/` (git rm the dir).
- [step] Remove its reference in `kubernetes/apps/flux-system/kustomization.yaml` (or the aggregating ks). Confirm `grep -rn flux-provider-pushover kubernetes/` returns nothing.

### 3.2 Remove the generic Pushover Provider + flux-alerts Alert

- [step] Delete `kubernetes/components/common/alerts/pushover/` (provider.yaml, alert.yaml, externalsecret.yaml, kustomization.yaml).
- [step] Edit `kubernetes/components/common/alerts/kustomization.yaml`: remove `./pushover`. Keep `./github` and `./alertmanager`.

### 3.3 Keep GitHub commit-status untouched

- [keep] `kubernetes/components/common/alerts/github/` stays exactly as-is.

### 3.4 Commit + reconcile + VERIFY (Phase 3 gate)

- [verify] `kubectl -n flux-system get deploy | grep flux-provider-pushover` gone (pruned).
- [verify] `kubectl get provider,alert -A` shows only `alertmanager` + `github-status`; no `pushover`/`flux-alerts`.
- [verify] `kubectl get externalsecret -A | grep -i pushover` shows only the observability `alertmanager` ES; `flux-pushover-secret` + `flux-provider-pushover-secret` pruned.
- [verify] Trigger one more Flux error — Pushover still delivers (solely via Alertmanager). No regression.

### 3.5 Optional follow-ups (NOT this roadmap unless asked)

- [followup] Grafana Alertmanager datasource (grafana helmrelease datasources: `type: alertmanager`, url `http://alertmanager-operated.observability.svc.cluster.local:9093`).
- [followup] Dead-man's-switch: if healthchecks.io / gatus / Uptime-Kuma is added, add a Watchdog to heartbeat route + receiver + secret.
- [followup] Consider enabling `kubernetesResources`/`kubernetesStorage` default groups once node/general rules prove stable.

---

## Documentation updates (Phase 3 close-out)

- [doc] Update BM `docs/areas/observability`: Alertmanager ENABLED (route, PVC, rules), flux-alerts relay retired, alerting unified. Bump `verified_at`.
- [doc] Update BM `docs/areas/flux-gitops`: replace the flux-alerts/flux-provider-pushover model with the `type: alertmanager` Provider model; note GitHub commit-status unchanged; resolve the existing "Pushover provider model split" open question.
- [doc] Optionally add an AD note capturing "why Alertmanager over the custom relay".

## Verification tooling notes for the executor

- [tool] Read-only `kubectl`/`flux` and read-only `just k8s`/`just volsync` are pre-allowed. Cluster-mutating actions need per-invocation approval.
- [tool] `kubectl get secret <name> -o yaml` on Secret contents is DENIED. Debug via ExternalSecret status, ClusterSecretStore, events.
- [tool] Local edits do not change the cluster until committed AND pushed AND reconciled. `flux reconcile` does not apply the local working tree.
- [tool] Stage commits with explicit pathspecs per file, never `git add -A`.
- [tool] Suggested commits: P1 `✨ feat(observability): enable Alertmanager + AlertmanagerConfig + OOMKilled rule`; P2 `✨ feat(flux): route reconciliation alerts through Alertmanager`; P3 `🔥 remove(flux): retire custom flux-provider-pushover relay`; docs `📝 docs(areas): Alertmanager alerting model`.

## Relations

- part_of [[observability]]
- relates_to [[flux-gitops]]
- depends_on [[external-secrets]]
- relates_to [[networking]]
