---
title: crowdsec-import-silent-degradation
type: progress-note
permalink: home-ops/docs/progress/crowdsec-import-silent-degradation
---

# crowdsec-import-silent-degradation — execution progress

## Metadata (observation-form, schema validation)

- [topic] Detect silent degradation of the blocklist-import plane — minimal (a)+(d) scope via in-cluster Pushgateway freshness metrics
- [status] DONE — implemented, deployed, live-verified. PR #4129 squash-merged to main (commit 2ea1daaa1). All 5 acceptance criteria met; the runtime chain (importer push -> pushgateway -> Prometheus scrape -> PrometheusRule label match) is live-verified green (see Roadmap closure). The 4 residual degradation modes (b/d/e/f) were consciously DROPPED by human decision 2026-08-05 — user-accepted risk with explicit re-open triggers, not forgotten.
- [roadmap] merged into this note — docs/roadmap/crowdsec-import-silent-degradation deleted on closure; design rationale (6-mode framing, a+d scope, namespace decision, for/keep_firing_for reasoning) lives in the sections below
- [closed] 2026-08-05
- [branch] feat/crowdsec-import-freshness-signal — merged to main via PR #4129 (squash 2ea1daaa1)
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

## Open / residual gaps (reviewed and DROPPED 2026-08-05 — see Roadmap closure for the decision and re-open triggers; the gap evidence below is retained as the dropped-risk record)

- (b) bouncer-key 403: get_existing_ips (v3.7.1 line 1681) csak logolja a 403-at, nem ir metrikat; health_check 200/403-at egeszsegnesnek veszi. METRICS_ENABLED nem fedi. Kulon feladat (upstream patch vagy log-parsolas).
- (d) frozen-mirror-200-stale: a v3.7.1 metrikak NEM tartalmaznak per-source Last-Modified-ot — csak source_status (fetch siker) es source_ips. Egy 200-as valaszzu de stale tartalmu fagyott mirror (pl. Cybercrime Tracker 28 napja) source_status=1 -> NEM fedett. Csak az "elerhetetlen feed" esete fedett (source_status=0). A roadmap (d)-je ezzel a megoldassal reszben fedett; a frozen-mirror-stale esete nyitva marad (per-source Last-Modified telemetria kellene, upstream).
- (e) pod-resource 512Mi mervelen; (f) unpaginated get_existing_ips — kulon slow-burn feladatok.
- Phase 4 observation window (roadmap) es Phase 5 Tier B/C promotion — erintetlen.

## Roadmap closure (2026-08-05)

PR #4129 squash-merged to main (2ea1daaa1); Flux reconciled; the runtime chain is live-verified GREEN — HR Ready=True UpgradeSucceeded; ServiceMonitor pushgateway live in observability with honorLabels=true; Prometheus scrape target up; both CrowdSecBlocklistImport* rules loaded; CrowdSecBlocklistImportMetricsAbsent firing (self-validating, see below). The 4 residual degradation modes (b/d/e/f) were consciously DROPPED by human decision 2026-08-05 — user-accepted risk, not forgotten; each has a re-open trigger below.

### HIBA 2 — live Helm install failure and fix
The pushgateway HelmRelease went Stalled / Ready=False in the live cluster: the prometheus-pushgateway chart's serviceMonitor.namespace default ("monitoring") does not exist in this cluster, so Helm server-side-apply failed creating the ServiceMonitor (UpgradeFailed, MissingRollbackTarget). Fix: helmrelease sets serviceMonitor.namespace=observability (release namespace) and honorLabels=true (explicit, critical — without honorLabels Prometheus overwrites the pushed job label with the scrape target name and the CrowdSecBlocklistImport* rule selectors never match). Verified by helm template: the ServiceMonitor renders with namespace=observability, honorLabels=true, port=http, namespaceSelector.matchNames=[observability], selector app.kubernetes.io/name=prometheus-pushgateway. Live kubectl confirmed the failure (Stalled/UpgradeFailed, the namespace-not-found message) and that no ServiceMonitor existed yet for pushgateway in either namespace; the other 12 ServiceMonitors all live in observability, confirming the pattern the fix follows. RESOLVED post-merge (verified live 2026-08-05): HR Ready=True UpgradeSucceeded; ServiceMonitor pushgateway now exists in observability (honorLabels=true); Prometheus scrape target up.

### promtool run method — explicit lesson
Run the tests via `just k8s test-prom-rules`, NOT a direct `promtool test rules prometheusrule_test.yaml`. The test file references ./_extracted_rules.yaml, which the recipe regenerates from the PrometheusRule spec on every run and removes afterwards; a stale leftover _extracted_rules.yaml from a prior run makes a direct promtool call return got:[] (false failures). The recipe is the only correct runner. crowdsec module: SUCCESS, 8 rules found; all 4 modules green. (Direct promtool produced a false failure during review — the defectus was in the run method, not the tests.)

### Shared-worktree incident and branch cleanup
A parallel terminal in the shared working directory staged its own pod-garbage-collector work; an unfenced `git commit` (without -o pathspec) pulled those files into my fix commit on the remote — a constraint violation (the human had marked pod-gc files off-limits). Local reset --soft + recommit with explicit pathspec produced a clean fix commit (pushgateway helmrelease only). force-with-lease push replaced the bad commit on origin/feat and in DRAFT PR #4129. Lesson: in a shared working directory, `git commit -o <pathspec>` per file is mandatory — never bare `git commit` (it commits the whole index, including another terminal's staged work).



### Live verification (live-verified green 2026-08-05)
Proven (static chain): both-direction CNP wiring (blocklist-import egress to pushgateway + pushgateway ingress from blocklist-import on the push port; Prometheus scrape via the blanket ingress-from-prometheus CCNP and the allow-prometheus pod label — live pod labels confirmed matching on both endpoints); in-cluster DNS reachable (headless Service, ClusterIP None, port-forward returns a healthy response); helm template renders the corrected ServiceMonitor with honorLabels. NOW PROVEN live (verified 2026-08-05 via read-only kubectl + Prometheus API port-forward): HR pushgateway Ready=True UpgradeSucceeded; ServiceMonitor pushgateway created in observability with honorLabels=true; Prometheus scrape target serviceMonitor/observability/pushgateway/0 is UP (no lastError); both rules CrowdSecBlocklistImportSourceFailing and CrowdSecBlocklistImportMetricsAbsent are loaded in Prometheus. The static chain was also confirmed live (both-direction CNP wiring, in-cluster DNS, pod labels matching on both endpoints).

### Self-validating signal (no manual check needed)
CrowdSecBlocklistImportMetricsAbsent is currently FIRING (verified via the Prometheus alerts API) because no blocklist_import_source_status series has been pushed yet — the pushgateway holds zero blocklist_import_* series until the first post-merge blocklist-import run. The CronJob runs daily at 04:00 Europe/Budapest. The absent() condition then becomes false. Self-resolves after the for:1h window. The pushed series carries the job label crowdsec-blocklist-import; honorLabels retains it. If STILL firing past the next 04:00 run plus 1h, the push chain is broken and the alert is doing its job (signalling). No manual verification step is required; the alert itself is the check.

### Validation (all green)
- kustomize build for pushgateway, blocklist-import, crowdsec app, observability parent: all exit 0.
- promtool check rules + test rules via the repo recipe: crowdsec module SUCCESS, 8 rules; test rules SUCCESS; all 4 modules green. Key fix: the test group interval must equal the file evaluation interval (1m), otherwise the for-timer never satisfies for 48h and the alert never fires.
- pre-commit on all 10 files: all hooks passed.
- helm template of the pushgateway chart with the release values: the ServiceMonitor renders with the expected selector and port, so scrape wiring is confirmed.
- CNP wiring verified: push ingress from blocklist-import via a per-app CNP, plus Prometheus scrape via the blanket ingress-from-prometheus CCNP and the allow-prometheus pod label.

## Consciously dropped risks (human decision 2026-08-05)
All 4 residual modes were reviewed and DROPPED. This is an accepted-risk record, not a backlog. Each: impact — why dropped — re-open trigger.

- (b) bouncer-key 403 — HIGHEST RISK, the ONE mode that NEMELY cuts protection: a revoked BOUNCER key makes health_check() treat 403 as healthy and get_existing_ips() return [], so dedup is silently skipped and max_new widens to the full MAX_DECISIONS cap (tail feeds then drop on cap exhaustion). WHY DROPPED: low probability (key delivered via ESO from the vault, rotation rare; the last manual run log showed no 403) and the fix needs an upstream patch (image rebuild). CRITICAL: the freshness plane built here does NOT see this — source_status measures FEED FETCH success while the bouncer key is on the LAPI dedup path, so neither CrowdSecBlocklistImport* rule fires on a revoked key. This is a conscious, user-accepted risk — not a forgotten one. RE-OPEN TRIGGER: CrowdSecDecisionBudgetNearCap fires, OR any 403 appears in the blocklist-import pod logs — then re-open (cheapest signal: a VictoriaLogs log-alert on the 403 string; the exact log-line format must be confirmed from upstream blocklist_import.py or a real 403 occurrence first).
- (d) frozen-mirror-200-stale: a feed returns 200 with stale content (Last-Modified old vs its cadence) but source_status at 1, so CrowdSecBlocklistImportSourceFailing does NOT fire — only the "unreachable feed" half of (d) is covered (source_status at 0); the v3.7.1 metrics lack per-source Last-Modified. Dropped because the fix needs an upstream patch (expose Last-Modified or a new_ips metric) or a new scheduled HTTP-HEAD checker component — not manifest-only. Documented stale feed in our setup: Botvrij (Last-Modified 2026-02-03, ~182 days, docs/roadmap/crowdsec-blocklist-import:146), but its expected cadence is unknown so "frozen" vs "legitimately slow" is unproven. RE-OPEN TRIGGER: a feed's IP count stays unchanged for a long period (visible in the pushed source_ips metric once the chain runs).
- (e) resource limit 512Mi and (f) unpaginated get_existing_ips: slow-burn capacity, not a silent protection drop; get_existing_ips fetches the full LAPI decision set unpaginated (~6.8 MB JSON at 33.8k decisions today) and is the root of the 512Mi estimate. Dropped: no OOM evidence (1 visible job Succeeded, no OOMKilled events; 6.8 MB is far below 512Mi); (f) fix is upstream. RE-OPEN TRIGGER: OOMKilled on the blocklist-import pod — then re-open (e) (measure high-water: METRICS_ENABLED is now on, so check whether the importer pushes process or RSS metrics to the pushgateway on the next run) and (f) (upstream paginate or stream patch).
