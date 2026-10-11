---
title: external-dns-alerting
type: progress
permalink: home-ops/docs/progress/external-dns-alerting
tags:
- external-dns
- alerting
- prometheusrule
- observability
- networking
---

# Progress — external-dns-alerting (PrometheusRule alerting for external-dns)

Roadmap item completed 2026-10-11 and moved from `docs/roadmap/external-dns-alerting`.
Implemented directly on main (GitHub flow, commits 3cb4bcc + 72b679c3a), reconciled by Flux
and verified live in the Prometheus rule API.

## Metadata (observation-form)

- [status] done — pushed to main, cluster-apps reconciled at 72b679c3a, both rules loaded and inactive in live Prometheus
- [priority] medium
- [area] networking / observability
- [created] 2026-10-07
- [completed] 2026-10-11
- [branch] main
- [moved_from] docs/roadmap/external-dns-alerting

## Why — the 2026-10 incident (live evidence)

- [observation] external-dns v0.23.0 ran a soft-error loop for ~3 days: `external_dns_controller_consecutive_soft_errors` climbed to 2108 on the current pod (max_over_time[5d]); ~92 hours with errors (count_over_time on `> bool 0`). Nothing alerted: no PrometheusRule covered external-dns, and per-loop soft errors are invisible to Flux alerting (a soft error is not a reconciliation failure).
- [observation] Hard errors (CrashLoopBackOff) are covered by the kubernetesApps default rule group; the uncovered class was exactly the silent soft-error retry loop.

## What was implemented

- [observation] `kubernetes/apps/networking/external-dns/app/prometheusrule.yaml` — group `external-dns.rules`, two alerts, wired into `app/kustomization.yaml`:
  - **ExternalDNSAbsent** (critical, for 15m) — `absent(up{job="external-dns"})`; fires only when the target vanishes from discovery. An up==0 scrape failure is a present series and must NOT fire — TargetDown (general rules, live-verified) owns that plane.
  - **ExternalDNSSoftErrors** (warning, for 5m) — `external_dns_controller_consecutive_soft_errors > 0`; gauge +1 per failed reconcile, reset to 0 on first success; for 5m is ~5 consecutive failed loops at the ~1m reconcile interval.
- [observation] `kubernetes/apps/networking/external-dns/app/prometheusrule_test.yaml` — 6 promtool cases: absent fire (asserts absent() carries the job matcher label into exp_labels — a hard promtool requirement, verified by negative test), up==1 no-fire, up==0 present no-fire, sustained>0 fire, flat-0 no-fire, reset-within-for no-fire. The _test.yaml is not listed in kustomization resources.

## Verification (2026-10-11)

- [observation] AC1 — `just k8s test-prom-rules` green over all 16 suites (promtool 3.15.0), incl. the new external-dns cases; pre-commit all-Passed on the commit gate.
- [observation] AC2 — after `flux reconcile kustomization cluster-apps --with-source` applied main@72b679c3a: PrometheusRule `external-dns` in networking (age 63s), and the live Prometheus rule API shows group `external-dns.rules` with both alerts loaded, state inactive; live data plane: `up{job="external-dns"}` present, gauge 0 on pod external-dns-5df8d5898d-47wwh.
- [observation] AC3 — zero AlertmanagerConfig / notification-plane change; both severities ride the existing default pushover receiver (repeatInterval 12h, critical-inhibits-warning on alertname+namespace).
- [observation] AC4 — severity routing asserted from existing config only (warning falls through the default route).

## Design record (from the roadmap, decisions preserved)

- Community staleness rule on last_sync age — rejected: live-verified permanent false firing on a no-op-stable cluster (last_sync advances only on applied changes).
- Registry/source error-counter alerts — rejected: same failure increments the consecutive gauge (net-reduction); counters stay investigation signals.
- Non-existent metrics (external_dns_controller_stale, external_dns_errors_total, external_dns_provider_errors_total) — never alert on them; they do not exist in v0.23.0.
- Bare absent() is fail-visible: if the job label ever changes, Absent fires loudly rather than never.

## Side-fix shipped with the item

- [observation] `mise.lock` was stale: the .mise.toml bump to prometheus 3.15.0 never got a lock refresh, so mise refused to resolve promtool (3.14.0 URLs under the 3.15.0 version) — `just k8s test-prom-rules` and its pre-commit hook were broken. Fixed by `mise lock` regeneration (commit 3cb4bcc), promtool 3.15.0 installed and suite green.

## References

- external-dns metrics docs — https://kubernetes-sigs.github.io/external-dns/latest/docs/monitoring/metrics/
- operational best practices (recommended-alert table) — https://kubernetes-sigs.github.io/external-dns/latest/docs/advanced/operational-best-practices/
- consecutive_soft_errors metric PR — https://github.com/kubernetes-sigs/external-dns/pull/5502

relates_to [[networking]]
relates_to [[observability]]
