---
title: external-dns-alerting
type: roadmap
permalink: home-ops/docs/roadmap/external-dns-alerting
topic: external-dns failure alerting — PrometheusRule on the already-scraped external-dns
  metrics, routed by the existing Alertmanager -> Pushover plane
status: planned
priority: medium
scope: Two PrometheusRule alerts for external-dns (ExternalDNSAbsent on absent(up),
  ExternalDNSSoftErrors on the consecutive-soft-errors gauge), a promtool unit-test
  suite, and the kustomization wiring — nothing else.
rationale: 'A 3-day external-dns soft-error loop (consecutive soft errors: 2108) ran
  silent because no PrometheusRule covers external-dns and per-loop soft errors are
  invisible to Flux alerting; the metrics are already scraped, so the gap is one rule
  file.'
related_areas:
- observability
- networking
options:
- Consecutive-soft-errors gauge alert (chosen — official best-practice signal, catches
  the exact incident class)
- Community staleness alert on last_sync age (rejected — live-verified permanent false
  firing on a no-op-stable cluster)
- Registry/source error-counter alerts (rejected — same failure increments the gauge;
  net-reduction)
- Grafana alerting (rejected — repo standard is PrometheusRule + Alertmanager)
tags:
- external-dns
- alerting
- prometheusrule
- observability
- networking
---

# ExternalDNS alerting

PrometheusRule-based alerting for external-dns, closing the gap that let a three-day soft-error
loop run completely silent. Rides the existing Alertmanager -> Pushover plane — no new notification
machinery, no chart change (the ServiceMonitor already exists and the metrics are already scraped).

## Metadata (observation-form)

- [topic] external-dns failure alerting — PrometheusRule on the already-scraped external-dns metrics, routed by the existing Alertmanager -> Pushover plane
- [status] planned
- [priority] medium
- [area] networking / observability
- [created] 2026-10-07

## Why — the 2026-10 incident (live evidence, not recollection)

- [observation] external-dns v0.23.0 ran a soft-error loop for ~3 days: `external_dns_controller_consecutive_soft_errors` climbed to 2108 on the current pod and 1520 on the previous pod (max_over_time[5d]); `count_over_time((... > bool 0)[5d:1h])` = 92 hours with errors on the current pod + 27 on the old one. The "2108" in the incident report is this gauge value (log tail reads "Failed to do run once: ... (consecutive soft errors: N)") — not a Cloudflare error code, which is undocumented and unverified anyway.
- [observation] Nothing alerted because no PrometheusRule exists for external-dns, and the failure mode is invisible to Flux alerting: a per-reconcile-loop soft error is not a reconciliation failure, so the Flux type:alertmanager Provider cannot fire either.
- [observation] Hard errors (controller exit -> CrashLoopBackOff) are already covered by the enabled kubernetesApps default rule group; the uncovered case is exactly the silent soft-error retry loop.
- [observation] The loop was resolved by commit 76bc51714 (annotation migration to the v0.23 prefix); the gauge reads 0 and the last applied sync was 93s before the check (2026-10-07).

## Live metric verification basis (promtool on prometheus-kube-prometheus-stack-0, 2026-10-07)

- [observation] Scrape path exists: chart-rendered ServiceMonitor external-dns (`serviceMonitor.enabled: true`, kubernetes/apps/networking/external-dns/app/helmrelease.yaml:35-36); job label `external-dns`, namespace networking.
- [observation] Verified present in v0.23.0: external_dns_controller_consecutive_soft_errors, external_dns_controller_last_sync_timestamp_seconds, external_dns_controller_last_reconcile_timestamp_seconds, external_dns_controller_no_op_runs_total, external_dns_controller_verified_records, external_dns_registry_errors_total, external_dns_source_errors_total, external_dns_registry_endpoints_total, external_dns_registry_records, external_dns_source_endpoints_total, external_dns_source_records, external_dns_http_request_duration_seconds{,_count,_sum}, external_dns_provider_cache_apply_changes_calls, external_dns_build_info. The external_dns_webhook_provider_* series are webhook-provider-only — unused with the Cloudflare provider.
- [observation] NOT present — do not alert on them: external_dns_controller_stale, external_dns_errors_total, external_dns_provider_errors_total. Several community/blog references cite these; they do not exist in v0.23.0 and would silently never fire.
- [observation] consecutive_soft_errors semantics (source-verified): gauge, +1 per failed reconcile, resets to 0 on the first success (kubernetes-sigs/external-dns PR #5502, in v0.23.0). A Cloudflare batch-apply failure is classified soft (submitChanges returns NewSoftErrorf) and increments external_dns_registry_errors_total too — gauge and counter are the same failure seen twice.
- [observation] external_dns_controller_last_sync_timestamp_seconds advances ONLY on syncs that applied changes: changes(...[2d]) = 7 while the controller reconciles every ~1m (no_op_runs_total climbs continuously). This kills the canonical community staleness alert (onedr0p/buroa/joryirving: `time() - external_dns_controller_last_sync_timestamp_seconds > 60`, for: 5m) — it would fire permanently on this stable cluster. Verified live, not assumed.

## Design — two alerts, group external-dns.rules

1. **ExternalDNSAbsent** — `absent(up{job="external-dns"})`, for: 15m, severity critical. Repo idiom (VolSyncComponentAbsent, FluxInstanceAbsent). Catches pod/scrape death.
2. **ExternalDNSSoftErrors** — `external_dns_controller_consecutive_soft_errors > 0`, for: 5m (about 5 consecutive failed loops at the 1m reconcile interval), severity warning. Matches the official operational-best-practices table: alert when the gauge is "> 0 for more than one reconcile cycle". Would have fired ~6 minutes into the incident, with re-notification per the existing 12h repeatInterval.

Both severities reach Pushover through the existing default receiver (warning falls through to the default route; critical-inhibits-warning on alertname+namespace is already configured). No AlertmanagerConfig change.

## Rejected alternatives (with reasons)

- Community staleness rule (last_sync age > 60s) — permanent false firing on a no-op-stable cluster; live-verified above, not copied.
- Separate registry/source error-counter alerts — the same failure increments the consecutive gauge (net-reduction); the counters stay investigation signals, not alerts.
- verified_records unexpected-drop alert — recommended upstream but speculative here; revisit if a record-drift incident ever occurs (YAGNI).
- Grafana alerting — the repo standard is PrometheusRule + Alertmanager.
- Flux-side alerting — categorically cannot see per-loop soft errors.

## Implementation plan

1. New kubernetes/apps/networking/external-dns/app/prometheusrule.yaml — name external-dns, group external-dns.rules, summary + description annotations (rendered by the AM Pushover template), wired into app/kustomization.yaml.
2. Sibling prometheusrule_test.yaml per the promtool unit-test bar: fire case (value > 0 sustained through the for window), no-fire boundary (0 / fresh reset), absent-up case; the _test.yaml is NOT listed in kustomization resources.
3. Validate: just k8s test-prom-rules + pre-commit (yamlfmt/yamllint).
4. Post-reconcile live check: both rules loaded and evaluating in Prometheus (loaded rules API / UI).

## Acceptance criteria

- AC1 — promtool test suite green (fire / no-fire boundary / absent cases covered).
- AC2 — after Flux reconcile, both rules visible and active in the live Prometheus rule API.
- AC3 — zero AlertmanagerConfig / notification-plane change.
- AC4 — severity routing verified from the existing config only (warning -> default pushover receiver).

## References

- external-dns metrics docs — https://kubernetes-sigs.github.io/external-dns/latest/docs/monitoring/metrics/
- operational best practices (recommended-alert table) — https://kubernetes-sigs.github.io/external-dns/latest/docs/advanced/operational-best-practices/
- consecutive_soft_errors metric PR — https://github.com/kubernetes-sigs/external-dns/pull/5502
- community staleness pattern surveyed and rejected on live evidence — onedr0p/home-ops kubernetes/apps/network/cloudflare-dns/app/prometheusrule.yaml; buroa/home-ops; joryirving/home-ops
