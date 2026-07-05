---
title: alertmanager-introduction
type: roadmap
permalink: home-ops/docs/roadmap/alertmanager-introduction
status: done
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
- [status] done
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
- [decision] Heartbeat / dead-man's-switch = **skipped for now** (no external uptime monitor). Watchdog is routed to blackhole in steady state; wire it to a heartbeat later as a follow-up if healthchecks.io / gatus / Uptime-Kuma appears.
- [decision] Rule scope = **extended**: keep current groups, additionally enable `general` (Watchdog + InfoInhibitor + TargetDown), `node`, `nodeExporterAlerting`, `nodeExporterRecording`; add a custom OOMKilled PrometheusRule.
- [decision] GitHub commit-status Provider/Alert (`components/common/alerts/github/`) is a different function (commit statuses) and **stays untouched**.

## Reference alignment (what bjw-s + onedr0p do)

- [reference] Both enable Alertmanager via `alertmanager.route.main` (Gateway API, envoy-internal) + `alertmanager.alertmanagerSpec` with `alertmanagerConfiguration.name: alertmanager`, `externalUrl`, and a 1Gi PVC. The `route.main` Gateway-API support is a chart feature present in the version we run (v86.3.2) — the sibling `../grafana/app/helmrelease.yaml` uses the identical `route.main` shape, so it is proven in this repo.
- [reference] Both ship an `AlertmanagerConfig` CR (`monitoring.coreos.com/v1alpha1`) named `alertmanager`: default receiver = pushover (rich HTML template, sendResolved), a `blackhole` receiver for InfoInhibitor/Watchdog, and inhibitRules (critical inhibits warning on same alertname+namespace). References route Watchdog to an external heartbeat; we blackhole it (no heartbeat yet).
- [reference] Both ship an `ExternalSecret` named `alertmanager` targeting secret `alertmanager-secret` with pushover token + userkey pulled from 1Password.
- [reference] Neither customizes `defaultRules` (full chart defaults, multi-node). Our repo stays minified but widens the enabled set per the extended-scope decision.
- [reference] Custom PrometheusRules: OOMKilled (both), ZFS (both), DockerHub rate-limit (onedr0p). We take **OOMKilled only** (ZFS/DockerHub not applicable here).
- [reference] **onedr0p replaces its custom Flux to Pushover path exactly the way we plan**: `kubernetes/components/alerts/alertmanager/` holds a Flux `Provider` `type: alertmanager` (address `http://alertmanager-operated.<ns>.svc.cluster.local:9093/api/v2/alerts/`) + an `Alert` covering all Flux event kinds. Canonical template for Phase 2.

## AD-023 network model — READ before 1.1 and 1.5 (repo-specific, references do NOT have this)

This cluster runs a Cilium label-driven network baseline (V3 flip). It differs from the
reference repos, which have no default-deny. Two consequences the executor MUST handle:

- [netmodel] **Egress to the public internet is NOT in the baseline.** Pods in `flux-system` and `cert-manager` get world egress for free (second spec of `allow-world-egress`), which is why the current relay reaches Pushover. **Alertmanager lives in `observability`, which does NOT** — so the Alertmanager pod MUST carry `egress.home.arpa/allow-world: "true"` or it cannot reach `api.pushover.net` and Pushover delivery silently fails. (Reference file: `kubernetes/apps/kube-system/cilium/netpols/allow-world-egress.yaml`.)
- [netmodel] **Ingress is default-deny once a pod is selected by any ingress policy.** Labeling Alertmanager with `ingress.home.arpa/gateways` + `ingress.home.arpa/prometheus` (needed for the UI route + prometheus scrape) makes it ingress default-deny for everything else. The Flux notification-controller (Phase 2) posting to `alertmanager-operated:9093` is neither a gateway nor prometheus, so it needs an **explicit per-app `CiliumNetworkPolicy`** (step 1.5). The two `ingress.home.arpa/*` grants come from cluster-wide policies (`ingress-from-gateways`, `ingress-from-prometheus`); Cilium unions all ingress allow rules.
- [netmodel] In-cluster egress (pod→pod, kube-apiserver) is allowed by the `allow-cluster-egress` baseline; the `allow-world` label ADDS world egress without opting out of cluster egress. No DNS rule needed (`allow-dns-egress` applies to all pods).

## Target end-state

- Alertmanager running in `observability`, 1Gi local-hostpath PVC, internal-gateway route, world-egress label for Pushover.
- One `AlertmanagerConfig` (pushover + blackhole for InfoInhibitor & Watchdog + inhibitRules).
- `alertmanager-secret` via ExternalSecret from 1Password.
- Extended default rules + OOMKilled custom rule.
- One per-app CiliumNetworkPolicy granting flux notification-controller → Alertmanager:9093.
- Flux reconciliation errors delivered through Alertmanager (Flux `type: alertmanager` Provider), not the custom relay.
- Retired: `flux-provider-pushover` app, generic `pushover` Provider, `flux-alerts` Alert.
- Kept: GitHub commit-status Provider/Alert.

---

## MANUAL PREREQUISITE (human — DONE 2026-07-05)

- [prereq] In the **Pushover dashboard**, create a new Application named `Alertmanager` and copy its API token. In **1Password**, open the existing `pushover` item and add a field `PUSHOVER_ALERTMANAGER_TOKEN` with that token. `PUSHOVER_USER_KEY` already exists and is reused as-is. **Status: completed by the user on 2026-07-05** — the `PUSHOVER_ALERTMANAGER_TOKEN` field exists in the `pushover` 1Password item. This is a hard gate for Phase 1: the ExternalSecret will not become Ready without it.

---

## Phase 1 — Alertmanager + config + rules (parallel, no Flux change yet)

All paths under `kubernetes/apps/observability/kube-prometheus-stack/app/`.

### 1.1 Edit `helmrelease.yaml`

- [step] Replace the `AlertManager - DISABLED` block (currently `alertmanager.enabled: false`, around lines 55-59) with:

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
            # AD-023: envoy-routed UI (gateways CCNP) + prometheus scrape (prometheus CCNP)
            # + internet egress for api.pushover.net (allow-world CCNP — observability is NOT free-world).
            ingress.home.arpa/gateways: "true"
            ingress.home.arpa/prometheus: "true"
            egress.home.arpa/allow-world: "true"
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

- [step] In `defaultRules.rules`, flip to `true`: `general`, `node`, `nodeExporterAlerting`, `nodeExporterRecording`. Leave the rest as-is. (`general` gives Watchdog + InfoInhibitor + TargetDown.)
- [note] No manual Prometheus→Alertmanager wiring is needed: the operator auto-populates the Prometheus CR `spec.alerting.alertmanagers` when `alertmanager.enabled: true`. Do not look for a separate config step.
- [check] The gateway namespace in this repo is `networking` (not `network` as in the upstream references) — confirm against `../grafana/app/helmrelease.yaml` `route.main` before commit.

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

Adapted from onedr0p/bjw-s; heartbeat removed, Watchdog routed to blackhole (no external monitor yet):

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
            value: Watchdog
            matchType: =
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

### 1.5 Edit `ciliumnetworkpolicy.yaml` — APPEND a second document

The file currently holds one CNP (prometheus egress to the OpenWRT router). Keep it, and append the alertmanager ingress policy as a second `---` document in the SAME file (the kustomization already references `./ciliumnetworkpolicy.yaml`, no kustomization change needed). This grants the Flux notification-controller → Alertmanager path used in Phase 2; provisioning it now is harmless.

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cilium.io/ciliumnetworkpolicy_v2.json
# alertmanager (AD-023): envoy + prometheus ingress via the matching CCNPs; this CNP adds the
# flux notification-controller east-west rule (Flux reconciliation alerts → Alertmanager API, Phase 2).
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: alertmanager
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: alertmanager
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: flux-system
            app: notification-controller
      toPorts:
        - ports:
            - port: "9093"
              protocol: TCP
```

- [note] `app.kubernetes.io/name: alertmanager` is the operator-created Alertmanager pod label (same convention as the prometheus selector in `ingress-from-prometheus`). `app: notification-controller` is the verified pod label of the Flux notification-controller in flux-system. Do NOT set `metadata.namespace` on this file — the ks `targetNamespace: observability` places it (matches the sibling prometheus CNP).

### 1.6 Edit `kustomization.yaml`

- [step] Add `./externalsecret.yaml`, `./alertmanagerconfig.yaml`, `./prometheusrules` to `resources`. Keep existing entries. (`./ciliumnetworkpolicy.yaml` is already listed — the appended doc rides along.)

### 1.7 Commit + reconcile + VERIFY (Phase 1 gate)

- [verify] After commit + push: `just k8s flux-reconcile` (or `flux reconcile ks kube-prometheus-stack`).
- [verify] `kubectl -n observability get externalsecret alertmanager` Ready=True (else the 1Password prereq is missing). Direct Secret content reads are DENIED by policy — use ExternalSecret status only.
- [verify] `kubectl -n observability get alertmanager,pods -l app.kubernetes.io/name=alertmanager` pod Running/Ready, PVC Bound.
- [verify] `kubectl -n observability get httproute` shows an alertmanager route; `kubectl -n observability get ciliumnetworkpolicy` shows the `alertmanager` policy.
- [verify] `kubectl -n observability get prometheusrule` shows `oom-alert` + the newly enabled default groups (general/node/etc.).
- [verify] Reach `https://alertmanager.${PUBLIC_DOMAIN}` from LAN; the Status page shows the loaded config (pushover receiver).
- [verify] **End-to-end Pushover test** (proves both the AlertmanagerConfig AND the world-egress label): inject a synthetic alert rather than relying on Watchdog (which is blackholed). Port-forward and use amtool, e.g. `kubectl -n observability exec <alertmanager-pod> -- amtool alert add test_alert severity=critical --alertmanager.url=http://localhost:9093` (or `amtool` from a workstation against the port-forwarded API). Confirm the phone receives it. If it does not: check the Alertmanager pod logs for a dial timeout to `api.pushover.net` → that means the `egress.home.arpa/allow-world` label did not take. Record the method + result in the progress note.

---

## Phase 2 — Flux reconciliation errors via Alertmanager

New dir `kubernetes/components/common/alerts/alertmanager/` (mirrors onedr0p `components/alerts/alertmanager/`). No netpol change here — the flux→AM ingress CNP was already added in 1.5.

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
- [note] The Provider address is a fixed cluster-DNS name to observability; a per-namespace Provider is fine (Flux resolves the cross-namespace Service URL), mirroring how the generic `pushover` Provider already points at the flux-system relay Service from every namespace.

### 2.5 Commit + reconcile + VERIFY (Phase 2 gate)

- [verify] `kubectl get provider,alert -A | grep alertmanager` present, Ready=True.
- [verify] Generate a benign Flux error and confirm it reaches Pushover **via Alertmanager** (Alertmanager UI shows the incoming Flux alert; phone gets it). Safe way: point a throwaway test Kustomization/HelmRelease at a bad ref on a branch, revert after.
- [verify] If the Flux alert appears in notification-controller logs as "sent" but never shows in Alertmanager, suspect the 1.5 ingress CNP (notification-controller blocked at :9093) — check `kubectl -n flux-system logs deploy/notification-controller` for a connection error to alertmanager-operated.
- [verify] During Phase 2 BOTH paths (old relay + new Alertmanager) are active — expected, confirms no gap before Phase 3.

---

## Phase 3 — Retire the custom relay (only after Phase 2 verified)

### 3.1 Remove the relay app

- [step] Delete the directory `kubernetes/apps/flux-system/flux-provider-pushover/`.
- [step] Edit `kubernetes/apps/flux-system/kustomization.yaml` and remove the line `- ./flux-provider-pushover/ks.yaml` (verified present at line 12). Confirm `grep -rn flux-provider-pushover kubernetes/` returns nothing.

### 3.2 Remove the generic Pushover Provider + flux-alerts Alert

- [step] Delete the directory `kubernetes/components/common/alerts/pushover/` (provider.yaml, alert.yaml, externalsecret.yaml, kustomization.yaml).
- [step] Edit `kubernetes/components/common/alerts/kustomization.yaml`: remove `- ./pushover`. Keep `- ./github` and `- ./alertmanager`.

### 3.3 Keep GitHub commit-status untouched

- [keep] `kubernetes/components/common/alerts/github/` stays exactly as-is.

### 3.4 Commit + reconcile + VERIFY (Phase 3 gate)

- [verify] `kubectl -n flux-system get deploy | grep flux-provider-pushover` gone (pruned).
- [verify] `kubectl get provider,alert -A` shows only `alertmanager` + `github-status`; no `pushover`/`flux-alerts`.
- [verify] `kubectl get externalsecret -A | grep -i pushover` shows only the observability `alertmanager` ES; `flux-pushover-secret` + `flux-provider-pushover-secret` pruned.
- [verify] Trigger one more Flux error — Pushover still delivers (solely via Alertmanager). No regression.

### 3.5 Optional follow-ups (NOT this roadmap unless asked)

- [followup] **DONE (2026-07-05, commit `20e119601`)** Grafana Alertmanager datasource — implemented in grafana helmrelease as `type: alertmanager`, `implementation: prometheus`, `handleGrafanaManagedAlerts: false`, url `http://kube-prometheus-stack-alertmanager.observability.svc.cluster.local:9093` (the chart ClusterIP service, matching the existing Prometheus datasource naming; the `alertmanager-operated` headless service also exists). `grafana.ini.unified_alerting.enabled` flipped to true so the Alerting UI can browse the external Alertmanager (legacy alerting engine stays off). The grafana→AM:9093 east-west path was added as a second `fromEndpoints` entry to the existing alertmanager CNP (no new cluster-wide label).
- [followup] **DONE (2026-07-05, commits `20e119601` + `a9788ec40`)** Dead-man's-switch via healthchecks.io — Watchdog route repointed from blackhole to a new `heartbeat` receiver using `webhookConfigs[].urlSecret` (alertmanager-secret/watchdog_ping_url). The ping URL lives in 1Password item `alertmanager` field `ALERTMANAGER_WATCHDOG_PING_URL`, surfaced into the existing `alertmanager` ExternalSecret via a second `dataFrom` extract + a `template.data` key — no new Secret/ExternalSecret. The ping UUID never enters the repo. InfoInhibitor stays on blackhole. Cadence: heartbeat-trick — `groupInterval: 5m` + `repeatInterval: 1m` (repeat_interval < group_interval makes AM notify on every group_interval flush → 5m cadence). The initial `repeatInterval: 5m` was wrong: with group_interval == repeat_interval == 5m, AM's strict "more than" repeat check (elapsed > repeat_interval, NOT >=) fails at the 5m flush (5m > 5m is false) and only passes at the 10m flush, producing a 10m cadence; fixed in `a9788ec40`, verified live at 5m. healthchecks.io check (period 5m, grace ~10m, notification channel) confirmed by user.
- [followup] Consider enabling `kubernetesResources`/`kubernetesStorage` default groups once node/general rules prove stable.

---

## Documentation updates (Phase 3 close-out)

- [doc] Update BM `docs/areas/observability`: Alertmanager ENABLED (route, PVC, rules, allow-world label), flux-alerts relay retired, alerting unified. Bump `verified_at`.
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

---

## Completion — 2026-07-05

Roadmap executed end-to-end across three phases with verification gates between each. All commits on `main`:

- **Phase 1** (`401d50021` + `cbf182f4e`): enabled Alertmanager in kube-prometheus-stack (internal-gateway route `alertmanager.${PUBLIC_DOMAIN}`, 1Gi local-hostpath PVC, AD-023 labels `ingress.home.arpa/gateways` + `ingress.home.arpa/prometheus` + `egress.home.arpa/allow-world`), `alertmanager` ExternalSecret from 1Password `pushover` item (PUSHOVER_ALERTMANAGER_TOKEN + PUSHOVER_USER_KEY), `alertmanager` AlertmanagerConfig (pushover default receiver, Watchdog/InfoInhibitor→blackhole, severity=critical→pushover, inhibitRules), extended default rules (`general` + `node` + `nodeExporterAlerting` + `nodeExporterRecording`), custom `oom-alert` PrometheusRule, and the alertmanager ingress CiliumNetworkPolicy (flux notification-controller→:9093, provisioned in Phase 1 for Phase 2). Verified: ExternalSecret Ready, Alertmanager pod Running 2/2, PVC Bound, HTTPRoute present, CNP VALID, PrometheusRules present, Prometheus auto-wired to Alertmanager, loaded config shows pushover receiver. End-to-end synthetic `test_alert` (severity=critical) delivered to Pushover — confirms both AlertmanagerConfig and the allow-world egress label.
- **Phase 1 add-on** (`cbf182f4e`): added Alertmanager to the Homepage dashboard (Observability group, `alertmanager.svg` icon, pod-selector status).
- **Phase 2** (`94a2f3359`): added `components/common/alerts/alertmanager/` (Flux `Provider` `type: alertmanager` → `http://alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/` + `Alert` covering FluxInstance/GitRepository/HelmRelease/HelmRepository/Kustomization/OCIRepository with the same exclusionList as the retired relay), wired into `components/common/alerts/kustomization.yaml`. Fan-out confirmed: 12 namespaces carry the alertmanager Provider+Alert. End-to-end Flux error (throwaway `alertmanager-test` Kustomization, bad path → ArtifactFailed) flowed notification-controller→Alertmanager API (`FluxKustomizationArtifactfailed` active, severity=error→default pushover receiver) and delivered to Pushover.
- **Phase 3** (`93a8b58ab`): retired the custom relay — deleted `apps/flux-system/flux-provider-pushover/` and `components/common/alerts/pushover/`, removed both from their parent kustomizations. GitHub commit-status Provider/Alert kept untouched. Pruning verified cluster-wide: relay Deployment gone, `pushover` Provider + `flux-alerts` Alert + `flux-pushover-secret` + `flux-provider-pushover-secret` ExternalSecrets pruned, only `alertmanager` + `github`/`github-status` remain. Regression test (same throwaway Kustomization, old relay now gone) confirmed Pushover still delivers — solely via Alertmanager, no alerting gap.

**Side note**: the kube-prometheus-stack chart was already at tag `87.10.1` in the repo (Renovate-tracked) when this roadmap landed; the BM `docs/areas/observability` note (verified 2026-06-20) still said v86.3.2 — corrected in the area-note update.

**Follow-ups (out of scope here, per roadmap 3.5)**: Grafana Alertmanager datasource (needs grafana→AM:9093 east-west CNP entry); dead-man's-switch if an uptime monitor is added (replace Watchdog→blackhole with Watchdog→heartbeat webhook receiver); consider `kubernetesResources`/`kubernetesStorage` default rule groups once node/general rules prove stable.
