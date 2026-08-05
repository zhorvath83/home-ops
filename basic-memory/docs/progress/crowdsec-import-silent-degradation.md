---
title: crowdsec-import-silent-degradation
type: progress-note
permalink: home-ops/docs/progress/crowdsec-import-silent-degradation
---

# crowdsec-import-silent-degradation — execution progress

## Metadata (observation-form, schema validation)

- [topic] Detect silent degradation of the blocklist-import plane — minimal (a)+(d) scope via in-cluster Pushgateway freshness metrics
- [status] in progress — phase 2 implementation on feat/crowdsec-import-freshness-signal; DRAFT PR pending
- [branch] feat/crowdsec-import-freshness-signal
- [area] crowdsec, observability, flux-gitops, networking (Cilium)
- [created] 2026-08-05
- [implements] [[crowdsec-import-silent-degradation]] roadmap (members a+d only)

## Scope (human-approved 2026-08-05, minimal)

Only roadmap members (a) feed-rot and (d) frozen/unreachable feed. Members (b) bouncer-key 403, (e) job-pod resource verification, and (f) unpaginated get_existing_ips REMAIN OPEN — explicitly out of this work.

## Acceptance criteria (explicit)

1. blocklist-import HelmRelease: METRICS_ENABLED=true + METRICS_PUSHGATEWAY_URL env pointing at the in-cluster Pushgateway (http://pushgateway.observability.svc.cluster.local:9091).
2. New in-cluster Pushgateway component (observability namespace) following the repo canonical app shape: ks.yaml + app/{kustomization,ocirepository,helmrelease,ciliumnetworkpolicy}.yaml; official prometheus-community/prometheus-pushgateway chart (v3.7.0), StatefulSet + 1Gi democratic-csi-local-hostpath PVC so metrics survive pod restart.
3. ServiceMonitor wiring the Pushgateway into kube-prometheus-stack via the chart serviceMonitor block (honorLabels default true); pod labelled ingress.home.arpa/allow-prometheus=true for the ingress-from-prometheus CCNP (scrape ingress). Push ingress (crowdsec ns -> observability:9091) via a per-app CNP; blocklist-import CNP gains an egress entry to the Pushgateway.
4. PrometheusRule (added to crowdsec/app/prometheusrule.yaml): (i) CrowdSecBlocklistImportSourceFailing on max by(source)(blocklist_import_source_status{job="crowdsec-blocklist-import"})==0, for:48h + keep_firing_for:24h, severity warning; (ii) CrowdSecBlocklistImportMetricsAbsent on absent(blocklist_import_source_status{job="crowdsec-blocklist-import"}), for:1h, severity warning.
5. promtool unit tests in crowdsec/tests/prometheusrule_test.yaml for BOTH new rules, firing AND not-firing (plus a keep_firing_for mutation pin for (i) and a for-not-met case for (ii)).

## Pushgateway stale-metric handling — miért ez a for/keep_firing_for ablak

A CronJob napi 04:00 fut; a Pushgateway megtartja az utolso pusholt erteket a kovetkezo futasig (~24h). Az upstream v3.7.1 blocklist_import.py delete_from_gateway(job="crowdsec-blocklist-import")-t hiv a push_to_gateway elott (fix job label, line 970/980), igy futasonkent csak az aktualis series all rendelkezesre — nincs stale series accumulation (issue #6).

- for:48h ~= 2 egymast koveto failed daily run: a Pushgateway megtartja a 0-t a futasok kozott, igy egyetlen transient fetch-hiba (egy nap) NEM oldja ki a 48h-t — csak a 2. napon is 0 marado feed. Ez a roadmap "silent for N runs" (N=2) intencioja, warning severity-hez.
- keep_firing_for:24h: a recovery ne tuntesse el az alertet azonnal a kovetkezo run-boundary elott (operator legalabb egy ciklusig lathassa).
- absent() for:1h: ride out pushgateway restart / scrape gap. A StatefulSet+PVC miatt a metrikak tulnek pod-restartot — ne false-positive-oljon egy restart.

## Namespace decision

Pushgateway -> observability namespace (nem crowdsec). Indoklas: standard Prometheus scrape-infra, a kube-prometheus-stack (scraper) es a tobbi exporter mellett; nem crowdsec-specifikus. A blocklist-import csak push-ol ide. A scrape-ingress a ingress-from-prometheus CCNP-n keresztul (label); a push-ingress (crowdsec->observability:9091) per-app CNP-vel engedelyezve.

## Open / residual gaps (carried forward)

- (b) bouncer-key 403: get_existing_ips (v3.7.1 line 1681) csak logolja a 403-at, nem ir metrikat; health_check 200/403-at egeszsegnesnek veszi. METRICS_ENABLED nem fedi. Kulon feladat (upstream patch vagy log-parsolas).
- (d) frozen-mirror-200-stale: a v3.7.1 metrikak NEM tartalmaznak per-source Last-Modified-ot — csak source_status (fetch siker) es source_ips. Egy 200-as valaszzu de stale tartalmu fagyott mirror (pl. Cybercrime Tracker 28 napja) source_status=1 -> NEM fedett. Csak az "elerhetetlen feed" esete fedett (source_status=0). A roadmap (d)-je ezzel a megoldassal reszben fedett; a frozen-mirror-stale esete nyitva marad (per-source Last-Modified telemetria kellene, upstream).
- (e) pod-resource 512Mi mervelen; (f) unpaginated get_existing_ips — kulon slow-burn feladatok.
- Phase 4 observation window (roadmap) es Phase 5 Tier B/C promotion — erintetlen.

## Resumption state
Implementation COMPLETE (2026-08-05). All 5 AC met. Code commit on the feature branch (10 files: 5 new pushgateway, 5 modified). Docs commit + push + DRAFT PR vs main pending.

### Validation (all green)
- kustomize build for pushgateway, blocklist-import, crowdsec app, observability parent: all exit 0.
- promtool check rules + test rules via the repo recipe: crowdsec module SUCCESS, 8 rules; test rules SUCCESS; all 4 modules green. Key fix: the test group interval must equal the file evaluation interval (1m), otherwise the for-timer never satisfies for 48h and the alert never fires.
- pre-commit on all 10 files: all hooks passed.
- helm template of the pushgateway chart with the release values: the ServiceMonitor renders with the expected selector and port, so scrape wiring is confirmed.
- CNP wiring verified: push ingress from blocklist-import via a per-app CNP, plus Prometheus scrape via the blanket ingress-from-prometheus CCNP and the allow-prometheus pod label.

### Open (carried forward, unchanged)
Roadmap members (b), (d) frozen-mirror-stale, (e), (f), Phase 4/5 remain open — see Open/residual gaps above.

### Next
Docs commit for the basic-memory tree, push the branch, open a DRAFT PR vs main covering (a+d) with the open items and the namespace decision rationale.
