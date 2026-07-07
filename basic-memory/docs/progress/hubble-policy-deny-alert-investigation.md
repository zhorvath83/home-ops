---
title: hubble-policy-deny-alert-investigation
type: progress
permalink: home-ops/docs/progress/hubble-policy-deny-alert-investigation
topic: Make the HubblePolicyDeny alert investigation-ready — drop-metric label enrichment
  (destination_ip + traffic_direction + workload), notification cleanup, and a retroactive
  flow-log backend for the policy-name gap
status: done
verified_at: 2026-07-07
priority: medium
scope: Three stacked tiers. Tier 0 cleans the alert rule and notification (no infra
  change). Tier 1 enriches the existing hubble_drop_total metric with destination_ip,
  traffic_direction and workload labels via a Cilium helm change (agent restart).
  Tier 2 stands up a persistent Hubble flow-log backend (VictoriaLogs) so retroactive
  denies carry the denying policy name + destination port — none of which exist as
  Prometheus metric labels in Cilium 1.19.5.
rationale: The current HubblePolicyDeny alert is investigation-hostile. Its annotation
  renders an empty destination (-> /) because hubble_drop_total only carries pod-identity
  labels and external destinations have no pod identity. It ships 8 scraper labels
  (container, endpoint, instance, job, namespace, node, pod, service) that describe
  the cilium-agent scrape target, not the denied flow, because the shared pushover
  message template iterates all .Labels.SortedPairs. And it cannot name the denying
  policy or destination port at all — those do not exist as metric labels in this
  Cilium release, and the Hubble in-memory flow buffer ages out in ~minutes so overnight
  denies are not retroactively queryable.
options:
- Tier 0 — alert rule + notification cleanup (no infra change; PrometheusRule only)
- Tier 1 — enrich hubble_drop_total labelsContext with destination_ip, traffic_direction,
  workload names (Cilium helm change; cilium-agent restart)
- Tier 2 — persistent Hubble flow-log backend to VictoriaLogs (retroactive policy
  name + destination port; closes the v1.19.5 metric-label gap)
related_areas:
- observability
- networking
decision_link: AD-023-cnp-threat-model-audit
---

# HubblePolicyDeny alert — investigation-ready redesign

## Metadata (observation-form, schema validation)

- [topic] Make the HubblePolicyDeny alert investigation-ready — drop-metric label enrichment + notification cleanup + retroactive flow-log backend
- [status] done
- [priority] medium
- [progress] Tracking + session summaries will live in a docs/progress sibling once work starts; this note is the plan.

## Background — current state (evidence-backed)

- [observation] Alert rule: `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/hubble-policy-deny.yaml` — `alert: HubblePolicyDeny`, `expr: increase(hubble_drop_total{reason="POLICY_DENIED"}[5m]) > 0`, severity critical. Annotation renders `{{ $labels.destination_namespace }}/{{ $labels.destination_pod }}` which are empty for external destinations -> renders `-> /`.
- [observation] Metric config (live `cilium-config` ConfigMap, key `hubble-metrics`): `dns drop:labelsContext=source_namespace,source_pod,destination_namespace,destination_pod tcp flow port-distribution icmp httpV2`. `hubble-network-policy-correlation-enabled=true`.
- [observation] Live label set of `hubble_drop_total{reason="POLICY_DENIED"}` carries: `source_namespace`, `source_pod`, `destination_namespace`, `destination_pod` (empty-string for external IP), `reason`, `protocol`, plus 8 scraper labels (`container, endpoint, instance, job, namespace, node, pod, service`).
- [observation] Notification: `alertmanagerconfig.yaml` pushover receiver, message template iterates `.Labels.SortedPairs` and prints every label — so all 8 scraper labels appear in the phone notification.
- [observation] The Hubble in-memory flow buffer does not retain overnight flows — `hubble observe --since 18h` returned empty during the 2026-07-07 maintainerr deny investigation. Retention is minutes-scale, not hours.

## Evidence — Cilium 1.19.5 Hubble metric capabilities (source-cited)

- [observation] Valid `labelsContext` label set is GLOBAL (identical for drop, flow, policy, dns) — defined once in `pkg/hubble/metrics/api/context.go` lines 64-80: `source_ip, source_pod, source_namespace, source_workload, source_workload_kind, source_app, destination_ip, destination_pod, destination_namespace, destination_workload, destination_workload_kind, destination_app, traffic_direction`. Anything outside this set is rejected at parse time.
- [observation] The `drop` metric (`hubble_drop_total`) CAN expose destination IP: `drop:labelsContext=destination_ip` (label `destination_ip`) OR `drop:destinationContext=ip` (label `destination`). Same context engine as `flow` (`drop/handler.go:28-50`). This corrects the assumption that the drop metric had no IP option.
- [observation] `reporter` label does NOT exist in Cilium 1.19.5 (checked proto, handlers, context). The side-orientation signal is `traffic_direction` with values `ingress` / `egress` / `unknown` (`context.go:337-343`) — the flow direction as observed by Hubble. Exact egress-enforcement-vs-ingress-enforcement semantics are UNVERIFIED; traffic_direction is the documented available signal.
- [observation] HARD LIMITS in v1.19.5 — none of these exist as metric labels: `policy_match_name`, `policy_match_type`, `policy_match_direction`, `destination_port`, `destination_service_name`, `destination_service_port`, `drop_reason`. The `policy` metric (`hubble_policy_verdicts_total`) exposes only fixed `direction` / `match` (= match TYPE e.g. l3_l4/l7_dns, NOT a name) / `action` + the shared labelsContext set. The denying policy NAME is only available in Hubble flow logs (`hubble observe --print-policy-names`).
- [observation] `hubble-network-policy-correlation-enabled` exists (default true) in `pkg/hubble/parser/cell/config.go` (parser layer); it does NOT gate any Prometheus label and does not produce `policy_match_name` (which does not exist regardless of the flag).
- [observation] Restart: `hubble.metrics.enabled` is static, bound to cilium-agent lifecycle (read at startup from `--config-dir=/tmp/cilium/config-map`); no hot-reload for the static list. This repo already sets `rollOutCiliumPods: true` (`kubernetes/apps/kube-system/cilium/app/helmrelease.yaml:90`), so the helm-values edit updates the `cilium-config` ConfigMap and its checksum annotation auto-rolls the cilium-agent DaemonSet on the next Flux reconcile — the new config is NOT inert and needs no manual rollout. L3/L4 forwarding + policy enforcement continue across restart (eBPF maps persist); only brief L7-proxy unavailable + delayed flow/metrics processing. Single-node: no L3/L4 dataplane blip, short L7 interruption only if L7-proxied traffic is on the node at restart time.
- [observation] Cardinality: IP-context series are NOT auto-pruned (only `pod` / `namespace+pod` contexts are pruned ~1 min after pod deletion — `metrics.rst:1145-1153`). Each unique destination IP becomes a distinct series. No official Cilium cardinality warning for IP-context exists; the risk is inferred from label-value mechanics. For a single-node home cluster with a bounded set of external API destinations, this is manageable but must be monitored.

## Tier 0 — alert rule + notification cleanup (no infra change)

### Goal

Strip scraper noise, render the empty-destination case intelligibly, and embed the
investigation command directly in the alert so the on-call has a one-line next step.

### Scope / files

- `kubernetes/apps/observability/kube-prometheus-stack/app/prometheusrules/hubble-policy-deny.yaml` (edit; new recording-rule pattern for this repo)
- No Cilium change. No restart. Reconciles via Flux on the existing prometheusrules PrometheusRule.

### Design

Introduce a recording rule that drops the 8 scraper labels once, then alert on the
clean recording rule. PromQL has no `label_drop` function; the idiomatic way to strip labels in a recording
rule is aggregation with `without`. New pattern for this repo (no existing `record:`
rule in `prometheusrules/`), so this also establishes the convention.

Recording rule (proposed):

```yaml
- record: hubble_policy_denied_increase5m
  expr: |
    sum without (container, endpoint, instance, job, namespace, node, pod, service) (
      increase(hubble_drop_total{reason="POLICY_DENIED"}[5m])
    )
```

Alert rule (proposed, replaces the current single rule):

```yaml
- alert: HubblePolicyDeny
  expr: hubble_policy_denied_increase5m > 0
  for: 0m
  labels:
    severity: critical
  annotations:
    summary: "Cilium policy denied a packet (Hubble)"
    description: >-
      Policy-denied drop on {{ $labels.source_namespace }}/{{ $labels.source_pod }}
      (dir: {{ $labels.traffic_direction | default "n/a" }})
      -> {{ $labels.destination_pod | default "" | regexf "(.+)" . | default "external/non-pod destination" }}
      (proto: {{ $labels.protocol }}, reason: {{ $labels.reason }}).
      Investigate: hubble observe --from-pod {{ $labels.source_namespace }}/{{ $labels.source_pod }}
      --verdict DROPPED --print-policy-names --last 200
```

### Notes / caveats for review

- The graceful empty-destination rendering above uses a placeholder idiom; the exact
  Go templating to emit "external/non-pod destination" when destination_pod is empty
  needs validation against the Prometheus alert template engine (the regexf/default
  chain is illustrative, not verified). A simpler verified form: keep a fixed
  annotation string and rely on the labels block; the destination_ip label from Tier 1
  is what actually makes the destination concrete.
- The runbook command in the annotation assumes the source pod is still live and in
  the Hubble buffer; for overnight/aged-out flows it returns empty — that gap is what
  Tier 2 closes.
- Does not touch the pushover template (shared across all alerts); label_drop at the
  alert is the surgical fix.

### Acceptance criteria

- [x] PrometheusRule applies clean — yamllint + yamlfmt clean locally; Flux HelmRelease kube-prometheus-stack READY=True (2026-07-07). [verified 2026-07-07]
- [x] Firing alert (live test) labels = destination_ip, protocol, reason, severity, source_namespace, source_pod, source_workload, traffic_direction — scraper labels (container/endpoint/instance/job/namespace/node/pod/service) absent. [verified 2026-07-07 live]
- [x] Alertmanager alert routed to pushover receiver carried only flow-relevant labels (recording rule stripped scraper labels upstream). [verified 2026-07-07 live]
- [x] Annotation rendered: "hubble observe --from-pod selfhosted/backrest-... --verdict DROPPED --print-policy-names --last 200" — copy-pasteable, source pod filled. [verified 2026-07-07 live]

## Tier 1 — enrich hubble_drop_total labelsContext (Cilium helm change; agent restart)

### Goal

Put the concrete destination (IP) and the flow direction (ingress/egress) into the
metric the alert already uses, plus stable workload names for alert-label continuity
across pod restarts (pod names carry an rs-hash that changes on restart, breaking
grouping).

### Scope / files

- `kubernetes/apps/kube-system/cilium/app/helmrelease.yaml` — the `hubble.metrics.enabled` list, `drop:` entry (line ~50).
- Reconciles via Flux -> cilium helm upgrade -> cilium-config ConfigMap updated.
- Requires cilium-agent restart to take effect (static config). This repo already has
  `rollOutCiliumPods: true`, so the helm upgrade that changes `drop:` rolls the
  cilium-agent automatically on the next Flux reconcile — no manual rollout decision
  needed. The only real knob is timing the reconcile for a low-traffic window.

### Proposed edit

```yaml
# before
- drop:labelsContext=source_namespace,source_pod,destination_namespace,destination_pod
# after
- drop:labelsContext=source_namespace,source_pod,source_workload,source_ip,destination_namespace,destination_pod,destination_workload,destination_ip,traffic_direction
```

All added labels are in the v1.19.5 global valid set (`pkg/hubble/metrics/api/context.go:64-80`).
`destination_ip` is populated for external (non-pod) destinations; `traffic_direction`
emits ingress/egress/unknown; `*_workload` are stable across restarts.

### Restart / dataplane impact

- L3/L4 forwarding + policy enforcement continue across the agent restart (eBPF maps
  persist). No dataplane blip for L3/L4 on the single node.
- Brief L7-proxy (Envoy) unavailable during the restart window — affects any traffic
  L7-proxied at that instant. Window is seconds.
- `rollOutCiliumPods: true` is already set in this repo (`helmrelease.yaml:90`): the
  helm-values change to `drop:` updates the cilium ConfigMap, whose checksum annotation
  rolls the cilium-agent DaemonSet automatically on reconcile. Activation is immediate;
  no manual rollout or natural-restart wait is needed.

### Cardinality

- `destination_ip` adds one series per unique destination IP. Bounded for a home
  cluster (finite external API set) but IPs from DNS rotate over time — monitor
  Prometheus series count (`prometheus_tsdb_head_series`) after rollout. No auto-prune
  for IP-context series (only pod-context is pruned).
- If cardinality grows, drop `destination_ip` from labelsContext and rely on Tier 2's
  flow-log backend for the IP instead.

### Acceptance criteria

- [x] Live test: hubble_drop_total{reason="POLICY_DENIED",source_pod=backrest-...} carries destination_ip=192.0.2.123, source_ip=10.244.0.60, source_workload=backrest, traffic_direction=egress (destination_workload empty for world-IP dest = expected). [verified 2026-07-07 live]
- [x] Live Alertmanager annotation rendered "-> / [192.0.2.123]" — concrete external IP, not bare "-> /". [verified 2026-07-07 live]
- [ ] DEFERRED — needs 7d post-rollout; baseline at rollout = ~7 hubble_drop_total series incl. 2 TTL_EXCEEDED multicast. Re-check prometheus_tsdb_head_series at 2026-07-14. Fallback (drop IP labels) documented.
- [x] DaemonSet desired=1 ready=1 updated=1 after rollout; cilium-agent socket dated 2026-07-07 19:31 (today). Two rollouts occurred (Tier-1 labelsContext + cilium-secrets fix as separate commits). [verified 2026-07-07 live]

## Tier 2 — persistent Hubble flow-log backend (VictoriaLogs) — DEFERRED (2026-07-07)

> DECISION 2026-07-07: dropped from active scope. The CNP posture denies no normal traffic, so every deny is a fresh anomaly acted on immediately; the live Hubble buffer plus the Tier 0 runbook cover policy-name and port at investigation time. No retroactive/long-term flow analysis is intended — Tier 2's sole justification. Revisit only if that requirement appears. The design below is retained for that contingency.

### Goal

Close the two gaps metrics cannot: the denying policy NAME and the destination PORT,
plus make overnight/aged-out denies retroactively queryable. The Hubble in-memory
buffer is minutes-scale; this very investigation hit empty results for 18h-old flows.

### Why a separate tier and not more metric labels

- `policy_match_name`, `destination_port` do not exist as Prometheus labels in Cilium
  1.19.5 (hard limit, source-confirmed). The policy name is only in flow logs.
- Flow logs are the authoritative investigation surface: `hubble observe --print-policy-names`
  gives the denying policy + destination IP + port + verdict in one row. The problem is
  retention, not capability.

### Options (export mechanism — needs a design decision)

0. **Cilium `hubble.export` (DROPPED-only) -> `/dev/stdout` -> existing `victoria-logs-collector`** —
   set `hubble.export.static.filePath: /dev/stdout` with an `allowList` filtering to
   `verdict: DROPPED`, so only policy denies land in cilium-agent stdout. The already-deployed
   `victoria-logs-collector` DaemonSet (`collector/helmrelease.yaml`, remoteWrites to
   `victoria-logs-server:9428`) tails all pod stdout and ships to VictoriaLogs with ZERO
   new workloads. Aligns with the repo "prefer existing abstractions" principle. Trade-off:
   mixes flow JSON into cilium-agent logs (bounded by the DROPPED-only filter); verify the
   collector parses the JSON line into queryable fields. Recommended to evaluate first.

1. **Cilium `hubble.export` static file + tailer** — Cilium writes flows to a file
   (`hubble.export.fileMaxSizeMB` etc.); a sidecar/tailer (Vector/Filebeat) ships to
   VictoriaLogs. Static config, agent-lifecycle-bound (restart on change), same as
   metrics.
2. **Hubble Relay + a flow exporter** — run a small consumer against Hubble Relay
   (`hubble observe --follow -o json` piped to VictoriaLogs ingest). Decoupled from
   agent lifecycle; no agent restart for export config changes. More moving parts.
3. **Hubble UI + manual `hubble observe`** — no persistence; rely on the runbook
   command from Tier 0. Cheapest, but overnight denies remain unqueryable (status quo).

### Scope / files (mechanism-dependent; sketched for option 1)

- Cilium helmrelease: add `hubble.export` block (static file export, rotation, format json).
- A new small workload in the observability namespace (or a sidecar on the cilium-agent
  via an extra container — less idiomatic here) that tails the export file and ships to
  VictoriaLogs via its HTTP ingest API. Reuse the existing victoria-logs-server stack.
- Cilium agent restart applies (same as Tier 1). Because `rollOutCiliumPods: true` auto-rolls the agent on every cilium ConfigMap change, landing Tier 1 and Tier 2 as separate commits causes TWO rollouts — strengthening the case to combine them into one coordinated change.

### Acceptance criteria

- [ ] Hubble flows (verdict DROPPED, with policy names) are queryable in VictoriaLogs for denies older than the Hubble buffer window (target: >= 24h, matching the victoria-logs `retentionPeriod: 14d`).
- [ ] A denied flow row in VictoriaLogs includes: timestamp, source namespace/pod, destination IP + port, verdict, drop reason, and the denying policy name.
- [ ] The HubblePolicyDeny alert runbook points at the VictoriaLogs query as the primary retroactive investigation path, with `hubble observe` as the live-buffer fallback.

## Constraints / hard limits (do not re-litigate in implementation)

- [observation] Cilium 1.19.5 has NO metric label for: policy name, destination port, destination service name/port. Any alert/rule design that needs those MUST use flow logs (Tier 2), not metrics.
- [observation] `reporter` does not exist; use `traffic_direction`.
- [observation] `labelsContext` valid set is global and fixed at 13 labels — no per-metric additions possible.

## Open questions for review

- [x] Tier 0 (RESOLVED): accepted the fixed-annotation form — empty pod-identity renders as an empty `[ip]` slot, and Tier 1's source_ip/destination_ip carries the concrete external endpoint. No regexf/default idiom. Direction-aware runbook via `{{ if eq $labels.traffic_direction "egress" }}`.
- [x] Tier 1 (RESOLVED): `rollOutCiliumPods: true` is already set (`helmrelease.yaml:90`), so the labelsContext change activates automatically on the next reconcile; the only sub-decision is timing that reconcile for a low-traffic window to minimize the brief L7-proxy blip.
- [x] Tier 1 (RESOLVED): include `source_workload`/`destination_workload` (stable names) AND both `source_ip`+`destination_ip` so whichever side is external gets an IP, plus `traffic_direction`. Cardinality is safe because denies are rare by design; post-rollout `prometheus_tsdb_head_series` spot-check is the only guard, with IP-label removal as the documented fallback.
- [x] Tier 2 (DEFERRED): tier dropped from scope (see Decision 2026-07-07). If revived, evaluate option 0 (DROPPED-only export to the existing victoria-logs-collector) first.
- [ ] Sequencing: Tier 0 alone first (free, immediate), then Tier 1 + Tier 2 together (share one cilium restart), or all three in one coordinated change?

## Related

- relates_to [[docs/areas/observability]]
- relates_to [[networking]]
- implements [[AD-023-cnp-threat-model-audit]]
- relates_to [[docs/roadmap/hubble-ui-auth]] (Hubble UI exposure — complementary investigation surface)

## Review — 2026-07-07 (evidence-backed against live repo)

- [observation] Verified against live files: alert rule hubble-policy-deny.yaml, drop labelsContext at helmrelease.yaml:50, pushover SortedPairs template at alertmanagerconfig.yaml lines 77-83, Cilium 1.19.5 at ocirepository.yaml:14, and no existing record rule in prometheusrules/ — all match the plan evidence.
- [correction] rollOutCiliumPods: plan assumed default false. Live helmrelease.yaml:90 already sets it true, so a drop/hubble.export ConfigMap change auto-rolls cilium-agent on reconcile. Tier 1/2 restart sections and open-question 2 corrected; this also strengthens combining Tier 1 and Tier 2 into one change to avoid two auto-rollouts.
- [correction] Tier 0 recording rule used label_drop, which is not a valid PromQL function on the Prometheus backend. Replaced with idiomatic sum-without aggregation over the 8 scraper labels.
- [correction] Tier 2 gained option 0: reuse the already-deployed victoria-logs-collector by exporting DROPPED-only Hubble flows to the agent stdout stream, avoiding a new tailer workload. Recommended to evaluate before options 1-3.
- [note] Tier 0 annotation regexf/default idiom stays unverified vs the Prometheus template engine; the plan already flags the fixed-string fallback, which stands.

## Decision — 2026-07-07 (scope locked)

- [decision] Scope reduced to Tier 0 + Tier 1; Tier 2 deferred. Rationale: the CNP posture denies no normal traffic, so every deny is a fresh anomaly acted on immediately — retroactive/long-term flow analysis, Tier 2 sole justification, is not a goal.
- [decision] Severity stays critical firing at greater-than-zero with no threshold and no for-delay. A deny is by design an unexpected event, so a per-packet critical is correct signal, not alert fatigue.
- [decision] Tier 1 labelsContext enriched beyond the original plan with source_ip, so ingress denies expose the external source IP just as egress denies expose destination_ip; traffic_direction disambiguates which side is external.
- [decision] Policy name and destination port stay out of the alert body (Cilium 1.19.5 hard limit) and are recovered on a fresh deny via the annotation runbook hubble observe --print-policy-names against the still-warm live buffer. Accepted trade-off: a deny that ages out unseen loses that detail.
- [implementation] Files changed: prometheusrules/hubble-policy-deny.yaml — added recording rule hubble_policy_denied_increase5m stripping the 8 scraper labels via sum-without aggregation, alert now fires on it, enriched direction-aware annotation with a copy-paste runbook, severity kept critical. cilium/app/helmrelease.yaml — drop labelsContext extended with source_workload, source_ip, destination_workload, destination_ip, traffic_direction.
- [observation] Validation: yamllint and yamlfmt clean on both files; Go-template brace and if/end balance plus PromQL paren balance verified locally; every annotation label is covered by the Tier 1 labelsContext or base metric labels. promtool was not available for full semantic rule validation — pending dependency.

## Session — 2026-07-07 (live end-to-end verification)

- [verification] Method: picked `backrest` (selfhosted) — its CNP allows egress only to `s3.de.io.cloud.ovh.net` + `hc-ping.com` on 443 (FQDN, default-deny otherwise). Curled RFC5737 `192.0.2.123` (guaranteed off the allow-list) from the pod to generate a real POLICY_DENIED egress drop.
- [observation] Hubble captured the drop live: `selfhosted/backrest-65c95f9b97-bf8lb:44056 <> 192.0.2.123:443 (world) Policy denied DROPPED (TCP Flags: SYN)`. curl exited 28 (timeout = SYN dropped).
- [observation] Fresh `hubble_drop_total{reason="POLICY_DENIED",source_pod="backrest-..."}` carries the Tier-1 enrichment: `destination_ip="192.0.2.123"`, `source_ip="10.244.0.60"`, `source_workload="backrest"`, `traffic_direction="egress"`, value=14. The Tier-1 acceptance criterion is now confirmed on a real POLICY_DENIED deny (previously only stale pre-rollout series existed).
- [observation] Recording rule `hubble_policy_denied_increase5m` strips the 8 scraper labels — its output labelset had NO container/endpoint/instance/job/namespace/node/pod/service.
- [observation] Alert `HubblePolicyDeny` went `state=firing` (activeAt 2026-07-07T19:47:51Z) under a sustained deny (increase5m=92.6). Alertmanager received it (state=active, receiver=pushover) with the annotation rendered as designed: `Policy-denied drop (egress) selfhosted/backrest-... [10.244.0.60] -> / [192.0.2.123] (proto: TCP). Investigate: hubble observe --from-pod selfhosted/backrest-... --verdict DROPPED --print-policy-names --last 200`.
- [observation] Direction-aware runbook branch verified: `traffic_direction="egress"` on the metric (NOT the Hubble flow-log field, which showed UNKNOWN for the SYN-drop) correctly selected the `--from-pod` branch via `{{ if eq $labels.traffic_direction "egress" }}`. Resolves the plan's "UNVERIFIED semantics" caveat favorably for the metric use-case.
- [caveat] Alert sensitivity: a single sub-scrape-interval burst (3s / 14 SYNs) showed increase5m=0 (single sample, no delta) and did NOT fire. Sustained denies across 2+ scrapes (counter climbing) DID fire. This is inherent Prometheus `increase` behavior, not a rule bug — the alert reliably catches a continuously-denying app (its purpose) but may miss a one-shot sub-scrape burst. Logged as a known characteristic.
- [caveat] Side effect of the test: a real pushover notification was sent (firing + a later resolved when the denies age out of the 5m window ~5min later). No cluster state was mutated — only transient curl traffic; no kubectl apply.
- [observation] Two cilium-agent rollouts happened (Tier-1 commit b7dc0b0f9 + cilium-secrets fix 59e98a405 as separate commits) — the plan's "separate commits → two rollouts" risk realized. The L7-proxy blip ran twice. Minor; documented.
