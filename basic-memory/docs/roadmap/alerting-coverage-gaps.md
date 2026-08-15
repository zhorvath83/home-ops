---
title: alerting-coverage-gaps
type: roadmap
permalink: home-ops/docs/roadmap/alerting-coverage-gaps
topic: Prometheus alerting coverage gaps identified via a comparative audit against
  billimek/k8s-gitops PrometheusRules — Kopia maintenance staleness, ExternalSecret
  sync failures, speedtest-exporter metrics left unalerted, and Docker Hub pull rate-limit
  risk.
status: proposed
priority: medium
scope: 'Four independently shippable PrometheusRule additions, each backed by metrics
  already scraped in the cluster today (no new exporter/component required): the volsync-system
  KopiaMaintenance CR (kopia-daily-maintenance), the external-secrets controller,
  the observability speedtest-exporter, and cAdvisor container image metrics for the
  docker.io-sourced workloads already in the repo.'
rationale: A GitHub code search over billimek/k8s-gitops (github.com/search?q=repo:billimek/k8s-gitops+%22kind:+PrometheusRule%22)
  surfaced 21 PrometheusRule manifests; cross-checking each against our 13 existing
  PrometheusRule manifests found four gaps where we already run the component and
  scrape its metrics, but never wired an alert on it. Each was verified against repo
  file:line before being carried here — not speculative. The Kopia maintenance CR
  (kopiamaintenance.yaml) can fail silently (no timestamp metric of its own; only
  the Job completion time from kube-state-metrics proves it ran) with no alert catching
  it; ESO already ships a Grafana dashboard/folder (grafanadashboard.yaml, grafanafolder.yaml)
  but no PrometheusRule; speedtest-exporter already has a serviceMonitor configured
  (helmrelease.yaml:76) with zero alerts; and 5 manifests (including the security-critical
  crowdsec chart) pull directly from docker.io with no rate-limit-risk alert.
related_areas:
- volsync-backup
- external-secrets
- observability
options:
- Ship all four phases in one PR since each is a small, independent PrometheusRule
  addition with metrics already flowing — lowest overhead, one round of promtool unit
  tests.
- Phase them separately by owning area (volsync-system, external-secrets, observability)
  so each area's CLAUDE.md-scoped review stays focused — higher process overhead for
  the same net change.
tags:
- roadmap
- observability
- alerting
- volsync-backup
- external-secrets
- prometheus
---

# alerting-coverage-gaps — four PrometheusRule additions surfaced by comparison against billimek/k8s-gitops

## Metadata (observation-form, schema validation)

- [topic] Four PrometheusRule gaps (Kopia maintenance staleness, ExternalSecret sync errors, speedtest-exporter, Docker Hub rate-limit risk) found by comparing our alert coverage against billimek/k8s-gitops
- [status] proposed
- [priority] medium
- [area] volsync-backup / external-secrets / observability
- [created] 2026-08-15

## Verification basis (how this item was built)

- Source: a GitHub code search (`repo:billimek/k8s-gitops "kind: PrometheusRule"`) via `gh api search/code`, followed by downloading all 21 matched files from `raw.githubusercontent.com` and reading each alert's `expr`/severity.
- Method: every candidate was checked against our own repo (file:line) before inclusion — items where the underlying component or metric doesn't exist in our stack (Ceph, OPNsense/Unbound, NFS+KEDA scalers, CloudNativePG, Gatus, UPS/NUT, the billimek-specific "kei" app) were discarded as not applicable. Items already covered by the kube-prometheus-stack `defaultRules` (node-exporter host alerts — `defaultRules.rules.node/nodeExporterAlerting/nodeExporterRecording: true` in `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml`) were discarded as redundant.
- The four items below are the ones where we run the exact component and scrape the exact metric family, but carry no alert on it.

## What we gain

- A silent Kopia maintenance failure (compaction/GC never running) surfaces before it turns into a slow-motion backup-integrity problem, instead of only being caught by `VolSyncVolumeOutOfSync`/`VolSyncMissedInterval`, which watch sync, not maintenance.
- An ExternalSecret stuck in a failed sync state (e.g. after a 1Password Connect credential rotation) raises an alert instead of being discovered only when a dependent app breaks.
- Internet-link degradation (slow speedtest, high ping, or the exporter itself going dark) becomes visible instead of only living in a Grafana dashboard nobody is watching.
- The docker.io-sourced workloads (crowdsec chart notably — a security-critical, always-on component) get an early warning before an anonymous/authenticated Docker Hub pull-rate limit turns into an `ImagePullBackOff` during a node reboot or Renovate-driven upgrade.

## What to do (phased; each phase independently shippable)

### Phase 1 — Kopia maintenance staleness alert (volsync-system)

- Add a rule beside `kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml` (or a new file under the same directory) that keys off `kube_job_status_completion_time` for the Jobs the `KopiaMaintenance` CR `kopia-daily-maintenance` (kubernetes/apps/volsync-system/volsync/maintenance/kopiamaintenance.yaml) creates on its 6-hourly schedule (`30 */6 * * *`), mirroring billimek's `kopiur-custom.yaml` pattern (`time() - max(max_over_time(kube_job_status_completion_time{...}[2d])) > threshold`).
- **Verify before implementing**: billimek's fork splits maintenance into separate quick/full Job name patterns (`nas-q-.*` / `nas-f-.*`); our operator is the perfectra1n/volsync fork with a single `trigger.schedule` on the CR — confirm at implementation time whether it creates one Job type or a quick/full split, and derive the actual Job name pattern from a live `kubectl get jobs -n volsync-system` rather than assuming billimek's naming.
- Threshold: our schedule runs 4x/day (every 6h), so the staleness window should be tighter than billimek's 12h/48h (which matches a different maintenance cadence) — derive it from our own schedule, not copied.

### Phase 2 — ExternalSecret sync-error alert (external-secrets)

- Add a `prometheusrule.yaml` under `kubernetes/apps/external-secrets/external-secrets/app/` (sibling to the existing `grafanadashboard.yaml`/`grafanafolder.yaml`, which prove the metrics are already scraped).
- Adapt billimek's `externalsecret_status_condition{condition="Ready",status="False"} == 1` expression; confirm the exact metric name/labels against the installed external-secrets chart version's `/metrics` output (Renovate may have moved the version since billimek's snapshot).

### Phase 3 — speedtest-exporter alert set (observability)

- Add a `prometheusrule.yaml` under `kubernetes/apps/observability/speedtest-exporter/app/` — the `serviceMonitor` is already configured (helmrelease.yaml:76, `/metrics` path) so no scrape wiring is needed.
- Port billimek's four alerts: `SpeedtestExporterAbsent` (target discovery), `SpeedtestSlowInternetDownload`/`SpeedtestSlowInternetUpload` (`speedtest_download_bandwidth_bytes`/`speedtest_upload_bandwidth_bytes` aggregated `max_over_time` across servers), `SpeedtestHighPingLatency` (`speedtest_ping_latency_seconds` `min_over_time`).
- Thresholds (50 MB/s down/up, 20ms ping) are billimek's own link characteristics — recalibrate against our actual contracted bandwidth before shipping, or the alert will either never fire or fire constantly.

### Phase 4 — Docker Hub rate-limit risk alert (`DockerhubRateLimitRisk`, observability)

- Add a rule (e.g. alongside the existing `kube-prometheus-stack/app/prometheusrules/` custom rules) using billimek's `count(time() - container_last_seen{image=~"(docker.io).*",container!=""} < 30) > 100` pattern — this is a pure cAdvisor metric already scraped via kubelet, so no new component is needed.
- Our docker.io footprint today is 5 manifests (`pingvin-share-x` → `docker.io/nginx`, `crowdsec` → `docker.io/crowdsecurity/crowdsec`, `suggestarr` → `docker.io/ciuse99/suggestarr`, `isponsorblocktv` → `docker.io/controldns/ctrld`), all single-replica — the `> 100` container-count threshold from billimek's larger cluster is almost certainly wrong for our scale; rebuild the expression around a scrape/pull-frequency signal appropriate to a single-node homelab rather than copying the threshold verbatim.

## Acceptance criteria

- A forced Kopia maintenance CronJob suspend (or a deliberately stale test fixture) fires the new staleness alert within its `for:` window, and a normal run does not.
- An ExternalSecret with an intentionally broken 1Password reference flips its `Ready` condition to `False` and fires the alert within 5m; a healthy ExternalSecret does not.
- The speedtest alert set has a passing `promtool` unit test suite (`<basename>_test.yaml` per `kubernetes/CLAUDE.md` convention) with recalibrated thresholds, positive+negative+boundary cases per alert.
- The Docker Hub alert's expression and threshold are rebuilt (not copied) against our actual container count and pull cadence, with a documented rationale for the chosen threshold.
- All four rules ship with sibling `_test.yaml` fixtures and pass `just k8s test-prom-rules`.

## Risks / what could break

- **Kopia maintenance alert (Phase 1):** guessing the Job-name regex instead of verifying it live risks an alert that never matches anything (silently useless) rather than failing loudly. Mitigation: verify Job naming via live `kubectl get jobs` before writing the `expr`.
- **ExternalSecret alert (Phase 2):** if the installed ESO chart version renamed or removed `externalsecret_status_condition`, the alert silently never fires. Mitigation: confirm the metric exists in the live `/metrics` output first.
- **speedtest thresholds (Phase 3):** uncalibrated thresholds either never fire (false confidence) or fire constantly (alert fatigue) — must be set from our actual link speed, not billimek's.
- **Docker Hub threshold (Phase 4):** the `> 100` container threshold is meaningless at our single-node scale; shipping it unchanged would make the alert permanently inert. Mitigation: redesign around our actual container count/pull frequency.

## Explicitly out of scope

- Node-exporter host-level alerts (HostOutOfMemory, HostHighCpuLoad, ZfsOfflinePool, etc.) — already covered by the kube-prometheus-stack `defaultRules` (node/nodeExporterAlerting/nodeExporterRecording), confirmed enabled in `kube-prometheus-stack/app/helmrelease.yaml`.
- Ceph, OPNsense/Unbound, NFS+KEDA scaler, CloudNativePG, Gatus, and UPS/NUT alerts from billimek — none of these components exist in our stack.
- Alertmanager meta-alerting (`AlertGroupExceedsMaxAlerts`/`MassiveAlertStorm`) — considered and discarded as low priority at our current alert volume; revisit if alert-fatigue becomes a real problem.
- Envoy Gateway alert expansion beyond the existing `EnvoyProxyDown` — tracked separately in [[gateway-guardrails-response-headers]] if pursued.

## Related

- relates_to [[volsync-backup]] — Phase 1 extends the existing VolSync alert set with maintenance staleness.
- relates_to [[external-secrets]] — Phase 2 adds the platform's first PrometheusRule.
- relates_to [[observability]] — Phases 3 and 4 both live in the observability alerting surface; ties into the kube-prometheus-stack `defaultRules` baseline already documented there.
