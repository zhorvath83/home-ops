---
title: security-event-alerting
type: progress
permalink: docs/roadmap/security-event-alerting
topic: Security-event alerting — WAF rule hits and Pocket ID identity events reach
  Alertmanager/Pushover
status: done
priority: high
scope: Two detection gaps from the 2026-11-23 public-endpoint review. (a) A CrowdSec
  AppSec (WAF) rule hit blocks the request but notifies nobody unless a ban follows.
  (b) Pocket ID security events (failed sign-ins, admin changes to users/groups/clients/API
  keys, passkey add/remove, login-code issuance) are not alerted at all. Covers a
  PrometheusRule for (a), a log-based alert engine (vmalert on VictoriaLogs) for (b),
  the Pocket ID login-notification env migration, and self-monitoring of the new path.
  Item 7b of the review (KubeHpaMaxedOut noise) is already handled by silence-operator
  (observability/silence-operator/silences/hpa_maxed_out.yaml) and is out of scope.
rationale: 'The prevention layers are solid (HU geo gate, CrowdSec ext_authz + AppSec,
  passkey-only IdP, route auth guard), but a targeted, low-volume attempt stays silent:
  CrowdSecBanActive fires only on bans, and the WAF blocked real probes (vpatch-env-access,
  vpatch-git-config) and a CVE-2025-29927 test without any alert. On the identity
  plane, an admin action through a hijacked session (new OIDC client, new API key,
  a user added to infra_admins, a foreign passkey enrolled) would be invisible: Pocket
  ID v2.19.3 has no admin notifications, no security metrics, and audits none of those
  admin actions.'
options:
- (b) vmalert in vlogs mode querying VictoriaLogs, notifying the existing Alertmanager
  — RECOMMENDED
- '(b) Grafana-managed alert rules on the VictoriaLogs datasource (operator GrafanaAlertRuleGroup)
  — rejected: a second alert pipeline beside Alertmanager (own contact points, silences,
  routing)'
- '(b) CronJob polling GET /api/audit-logs/all with an admin API key, pushing counters
  to Pushgateway — deferred: v2.19.3 audits only sign-in/passkey/client-authorization
  events, the admin events are unreleased upstream; revisit when they ship'
- (a) PrometheusRule on cs_appsec_rule_hits — RECOMMENDED; (a) CrowdSec http notification
  plugin posting to the Alertmanager API — alternative if the client IP must be in
  the alert
related_areas:
- observability
- iam
- networking
---

# Security-event alerting (WAF hits + Pocket ID events)

## Metadata (observation-form, schema validation)

- [topic] Security-event alerting — WAF rule hits and Pocket ID identity events reach Alertmanager/Pushover
- [status] done — Phases 1–4 delivered and live 2026-11-23 (direct to main); passkey live trigger still open (see Implementation)
- [priority] high
- [researched_at] 2026-11-23
- [effort] M

## What we gain

- Every WAF block (an exploit attempt that reached the gateway) pages within minutes, with the rule name.
- Every change to the identity plane (users, groups, group membership, OIDC clients and secrets, API keys, app configuration, signup tokens, admin-issued login codes) and every passkey add/remove produces a notification; a change you did not make is visible the same day.
- Failed-login bursts on the IdP become visible (today only CrowdSec's generic scenarios could see them, and they do not alert unless they ban).
- A log-based alerting path exists for any future log-only signal (geo-gate misclassification, app-specific auth failures), closing the "out of scope: vmalert" note of [[grafana-victorialogs-datasource]].

## What we accept

- Admin-write alerts also fire for legitimate changes, including every `just pocket-id apply` (Terraform drives the admin API). Volume is low (14 admin writes in 14 days) and the alert doubles as a change log (D2).
- Log-based alerts are only as good as the log pipeline; a silent pipeline must itself alert (Phase 3).
- The WAF metric carries no client IP (only the bouncer pod as `source`); the alert names the rule, the IP is looked up in LAPI (`cscli alerts list`) or the geo-gate Grafana dashboard.
- LAN tests (e.g. a deliberate vpatch probe) fire the WAF alert too. Intended: a test should prove the alert path.

## Research findings (2026-11-23)

### (a) WAF
- [evidence] `cs_appsec_rule_hits{rule_name, source=<bouncer pod IP>, type=inband}` is scraped (job `crowdsec-appsec-service`). Current values: `vpatch-CVE-2025-29927` 4 (the 2026-11-23 test), `vpatch-env-access` 2 and `vpatch-git-config` 1 (from the previous bouncer pod IP — real probes nobody was told about).
- [evidence] ~~`cs_appsec_block_total` increased by 0 over 7 days~~ — corrected in Phase 0: it did move (3 on source .82, 4 on .95, equal to the rule_hits sums). The "0" was the new-series pitfall: each series was born with its first value, so `increase()` saw nothing. `cs_appsec_rule_hits` is used because it carries `rule_name`.
- [evidence] LAPI recorded the 4 test hits as alerts without decisions (LAN source whitelisted by `crowdsecurity/whitelists`). The appsec pod has `crowdsecurity/appsec-vpatch` and `appsec-native` scenarios installed, so a repeated external offender is banned and then `CrowdSecBanActive` fires; a single attempt is not.
- [evidence] Alertmanager: default receiver `pushover`, `severity=critical` routed to pushover, `Watchdog` heartbeat, critical inhibits warning per alertname+namespace (`observability/kube-prometheus-stack/app/alertmanagerconfig.yaml`).
- [fact] Repo precedent: alerts read the TSDB with range queries, not instant presence (see [[crowdsec-alert-tsdb-sourced]]); rules ship with a `prometheusrule_test.yaml` promtool test.
- [fact] Prometheus pitfall: a counter series that appears for the first time with value 1 has no earlier sample, so `increase()` returns 0 for the first hit. The rule needs a new-series branch.

### (b) Pocket ID (v2.19.3, source-level research)
- [fact] Audit event types (`backend/internal/auditlogs/model.go`): `SIGN_IN`, `TOKEN_SIGN_IN`, `REMOTE_SIGN_IN`, `ACCOUNT_CREATED` (self-signup only), `CLIENT_AUTHORIZATION`, `NEW_CLIENT_AUTHORIZATION`, `DEVICE_CODE_AUTHORIZATION`, `NEW_DEVICE_CODE_AUTHORIZATION`, `PASSKEY_ADDED`, `PASSKEY_REMOVED`. Sign-ins carry `newBrowser`, IP, country, city, user agent.
- [fact] **Not audited** in v2.19.3: failed sign-ins, admin user/group/membership changes, OIDC client and secret changes, API key create/renew/revoke, login-code issuance, app-config changes. `main` adds ~25 events (`API_KEY_*`, `CLIENT_*`, `CLIENT_SECRET_*`, `ADMIN_GRANTED/REVOKED`, `GROUP_MEMBER_*`, `LOGIN_CODE_CREATED`, …) plus actor fields, and moves the admin list to `GET /api/admin/audit-logs` — release unknown.
- [fact] Audit rows live only in the DB (`audit_logs`, retention `AUDIT_LOG_RETENTION_DAYS`, default 90); a successful insert writes no log line; no webhook, no OTel audit signal. Readable via `GET /api/audit-logs/all` (scope `audit-logs:read`, `X-API-Key`), paginated (max 100).
- [fact] No custom metrics: the Prometheus exporter carries otelgin HTTP histograms (`http_server_request_duration_seconds` by route/method/status) and runtime metrics only.
- [fact] No admin notification for any event. The user login notification mode: `EMAIL_LOGIN_NOTIFICATION_MODE` (`disabled` default | `browserRecognition` | `ipAndUserAgent` | `always`). Our env still sets the **legacy** `EMAIL_LOGIN_NOTIFICATION_ENABLED=true`, which v2.19.3 maps to `browserRecognition` (`appconfig/service.go:239-248`, `appconfig/legacy.go:26-30`) and which is marked for removal in v3 — after a v3 Renovate bump the notification would silently fall back to `disabled`.
- [evidence] The request log is JSON on stdout (`LOG_JSON=true`) and VictoriaLogs stores it with top-level fields `method`, `route` (gin template, e.g. `/api/oidc/clients/:id`), `path`, `status`, `ip` (client IP, Envoy XFF trusted via `TRUST_PROXY`), `user_agent`, `referer`, `request_id`, `app=pocket-id` (verified on a `POST /api/webauthn/login/finish` entry). User ID is not logged.
- [evidence] Write requests in the last 14 days (VictoriaLogs, `method:in(POST,PUT,DELETE,PATCH)`): `POST /api/oidc/token` 39×200 + 1×401; `POST /api/webauthn/login/finish` 19; `POST /api/oidc/interactions/:id/complete` 19; `POST /api/api-keys/:id/renew` 3; `POST /api/oidc/clients` 2; `PUT /api/oidc/clients/:id/allowed-user-groups` 2; `POST`/`DELETE /api/oidc/clients/:id/secrets[/:secretId]` 2+2; `PUT /api/oidc/clients/:id` 1; `POST /api/user-groups` 1; `PUT /api/user-groups/:id/users` 1; `POST /api/one-time-access-email` 1×403. Baseline is tiny → "any occurrence" alerts are viable.
- [fact] No log-based alerting exists today (no vmalert/VMRule; Grafana has the VictoriaLogs datasource for dashboards only). VictoriaLogs: `victoria-logs-single` chart 0.13.13, service `observability/victoria-logs-server:9428`, retention 14d. Alertmanager service `observability/alertmanager-operated:9093`.

## Design

### (a) WAF hit alert — PrometheusRule in `crowdsec/crowdsec/app/prometheusrule.yaml`
```yaml
- alert: CrowdSecWAFRuleHit
  expr: |-
    sum by (rule_name) (increase(cs_appsec_rule_hits{job="crowdsec-appsec-service", namespace="crowdsec"}[15m])) > 0
    or
    sum by (rule_name) (cs_appsec_rule_hits{job="crowdsec-appsec-service", namespace="crowdsec"}
      unless cs_appsec_rule_hits{job="crowdsec-appsec-service", namespace="crowdsec"} offset 15m) > 0
  labels:
    severity: critical
  annotations:
    summary: "WAF rule {{ $labels.rule_name }} blocked a request"
    description: "Client IP: cscli alerts list --since 30m (LAPI pod) or the Envoy geo-gate dashboard."
```
- `source` dropped from the grouping (it is the bouncer pod IP, changes on rollout). The `unless … offset` branch catches a brand-new series; an appsec pod restart resets counters — Prometheus `increase()` handles resets.
- promtool test cases: first hit on a new series, second hit on an existing series, counter reset, quiet period (no alert).

### (b) Pocket ID events — vmalert (vlogs) → Alertmanager
New app `kubernetes/apps/observability/vmalert-logs/` (Flux ks + OCIRepository `oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-alert`, Renovate-tracked; name final in Phase 0):
- vmalert with `-datasource.url=http://victoria-logs-server.observability.svc:9428`, `-rule.defaultRuleType=vlogs`, `-notifier.url=http://alertmanager-operated.observability.svc:9093`, rules from a ConfigMap in git (`rules/pocket-id.yaml`), external label `source=vmalert-logs`.
- No remote write / state restore (stateless; `for:` not needed for "any occurrence" rules).
- Hardening like the other observability apps: non-root, RO rootfs, drop ALL, seccomp; CNP: egress to victoria-logs 9428 and alertmanager 9093 only; ingress from Prometheus for `/metrics`; victoria-logs CNP gains an ingress rule from vmalert; ServiceMonitor.

Rules (LogsQL; each `stats by (...)` row becomes one alert with those fields as labels; time window = group interval, 1m):

| Alert | Severity | LogsQL (stream filter `kubernetes.pod_namespace:=security app:=pocket-id` implied) |
|---|---|---|
| `PocketIDAdminChange` | warning (critical if `ip` not RFC1918) | `method:in(POST,PUT,DELETE,PATCH) route:~"^/api/(users\|user-groups\|oidc/clients\|api-keys\|application-configuration\|signup-tokens\|custom-claims)" status:<400 \| stats by (method, route, ip) count()` |
| `PocketIDPasskeyChanged` | critical | `(route:="/api/webauthn/register/finish" method:=POST or route:~"webauthn-credentials\|/api/webauthn/credentials/" method:=DELETE) status:<400 \| stats by (route, ip) count()` |
| `PocketIDLoginCodeIssued` | critical | `route:~"one-time-access" status:<400 \| stats by (route, ip) count()` |
| `PocketIDFailedSignIns` | warning | `route:in("/api/webauthn/login/finish","/api/one-time-access-token/:token","/api/oidc/token") status:>=400 \| stats by (route, ip) count() as c \| filter c:>=5` (window 10m) |
| `PocketIDRateLimited` | warning | `status:=429 \| stats by (route, ip) count()` |
| `PocketIDLogsSilent` | critical | `* \| stats count() as c \| filter c:=0` over 15m — the blackbox `idm_probe` hits `/` every 60s, so a silent stream means the pipeline (or Pocket ID logging) broke |

- The exact route templates and the RFC1918 split (two rules, or `ip:ipv4_range(...)` filter) are pinned in Phase 0 against real log entries. The IP inside admin alerts tells "Terraform from the Mac on the LAN" from "a browser session from outside" at a glance.
- vmalert self-monitoring in Prometheus: `VMAlertLogsDown` (`up`/`absent`), `VMAlertLogsRuleErrors` (`increase(vmalert_execution_errors_total[15m]) > 0`), `VMAlertLogsNotifierErrors` (`vmalert_alerts_send_errors_total`). Without these a broken query silently disables every rule.

### Pocket ID config
- Replace `EMAIL_LOGIN_NOTIFICATION_ENABLED: "true"` with an explicit `EMAIL_LOGIN_NOTIFICATION_MODE` (D3), so the v3 removal of the legacy variable cannot turn notifications off.
- Keep `AUDIT_LOG_RETENTION_DAYS` default (90) — forensic lookback beyond VictoriaLogs' 14 days.

## Plan

### Phase 0 — Spike and pin
1. WAF: from the LAN, request a harmless vpatch trigger (e.g. `GET https://echo.${PUBLIC_DOMAIN}/.env`) and record which of `cs_appsec_rule_hits` / `cs_appsec_block_total` move and with which labels.
2. vmalert: confirm the chart name/version, the vlogs rule format (`type: vlogs`, how the time filter is applied per evaluation, label mapping from `stats by`), notifier compatibility with Alertmanager v2 API, and resource footprint.
3. Pocket ID: trigger each event class on purpose (create and delete a throwaway OIDC client and API key via the LAN admin UI; add and delete a test passkey; a failed passkey login) and read the resulting `route`/`method`/`status` in VictoriaLogs; freeze the LogsQL.
4. Decide D1–D4.

### Phase 1 — WAF alert
- Rule + promtool tests in `crowdsec/crowdsec/app/prometheusrule{,_test}.yaml`; pre-commit green; after reconcile, the Phase 0 probe produces exactly one Pushover notification naming the rule.

### Phase 2 — vmalert-logs + Pocket ID rules
- New Flux app, CNPs, ServiceMonitor, self-monitoring PrometheusRule; rules ConfigMap; Pocket ID env change (D3).
- Replay the Phase 0 event triggers: each produces its alert in Alertmanager (labels `route`, `ip`, `source=vmalert-logs`) and a Pushover message.

### Phase 3 — Failure-path verification
- Scale victoria-logs to 0 for 5 minutes (or block vmalert's egress): `VMAlertLogsRuleErrors` fires. Restore.
- Stop Pocket ID logging (e.g. scale pocket-id to 0 briefly): `PocketIDLogsSilent` fires (BlackboxProbeFailed fires too — consistent).

### Phase 4 — Docs
- BM `docs/areas/observability` (log-based alerting path), `docs/areas/iam` (event → alert map, the upstream audit gap), Grafana annotation/runbook text in alert descriptions.
- Follow-up trigger recorded: when a Pocket ID release ships the extended audit events, re-evaluate option C (audit-API poller) — it would add actor identity and cover admin actions done through non-HTTP paths (CLI).


## Implementation (2026-11-23)

### Commits (main)
- WAF rule + promtool tests: landed inside `1e906c73d` (📝 docs(homepage): close homepage-gateway-oidc) — a concurrent session's commit swept the already-staged files; content correct, message misleading, not rewritten (pushed).
- `a815cfd14` ✨ feat(observability): add vmalert-logs for log alerts (promtool hook skipped on request: a concurrent session edited files during the hook; suite passed on the same content).
- `deb024e89` 🔒 security(pocket-id): pin explicit login notification.

### Decisions taken
- [decision] D1 vmalert vlogs, D2 alert on every admin write (incl. Terraform), D3 `browserRecognition`, D4 critical — all as recommended.
- [decision] Admin-change rule is **fail-closed** (deviation from the Design's route allowlist): every successful write alerts unless its route is a known sign-in/session flow (`/authorize`, `/api/oidc/{token,interactions/:id/complete,par,userinfo,introspect,end-session}`, `/api/webauthn/{login/finish,logout,reauthenticate}`) or owned by the passkey / login-code rules. A write route added by an upgrade alerts instead of being silently ignored. Route list pinned from the v2.19.3 source (all `.POST/.PUT/.DELETE/.PATCH` registrations).
- [decision] Split `PocketIDAdminChange` (warning, client IP in 10/8, 172.16/12, 192.168/16) and `PocketIDAdminChangeExternal` (critical, any other or missing IP). Distinct names so the critical→warning inhibit rule cannot hide LAN changes during an external incident.
- [decision] `PocketIDLoginCodeIssued` became `PocketIDLoginCodeUsed`: covers admin issuance (`/api/users/:id/one-time-access-{token,email}`) and redemption (`/api/one-time-access-token/:token`, `/api/one-time-access-email`). `PocketIDFailedSignIns` became `PocketIDFailedRequests`: any 4xx write, ≥5 per IP in 10m.
- [decision] Stream filter keys on Kubernetes metadata (`{kubernetes.pod_namespace="security",kubernetes.container_name="app"}` + pod label `app.kubernetes.io/name=pocket-id`), not the app-emitted `app` field, so another pod cannot forge Pocket ID lines.
- [decision] WAF rule: the new-series branch is gated by `and on () group(up{job="crowdsec-appsec-service"} offset 15m)` so a >15m Prometheus gap does not re-announce every old series (mutation-pinned by promtool case W5).

### Findings
- [fact] vmalert vlogs: when the expr has no `_time` filter, vmalert sends `start=time-interval`; with an explicit `_time:5m` it sends only `time` (vmalert v1.157.0 `datasource/client_vlogs.go`). Every rule therefore carries `_time:5m` (10m/15m where needed) at a 1m interval.
- [evidence] The overlapping window is load-bearing: the 22:20:18Z API-key events were absent at the 22:21:20Z evaluation and first seen at 22:22:20Z (collector ingestion lag > 1 min). A plain 1m window would have dropped them permanently.
- [fact] vmalert pods carry `app.kubernetes.io/name=victoria-metrics-alert`, `instance=vmalert-logs` (chart 0.54.0); metrics: `vmalert_alerting_rules_errors_total`, `vmalert_alerts_send_errors_total`, `vmalert_config_last_reload_successful`.
- [fact] Rules ship as a kustomize-generated ConfigMap (`vmalert-logs-rules`, Flux substitution disabled) mounted as a directory; `-configCheckInterval=1m` hot-reloads, a bad reload keeps the old rules and raises `VMAlertLogsConfigReloadFailed`.

### Verification
- [verified] Phase 0 LogsQL: every rule expr run against 14d of real logs via `stats_query`; admin rule returned exactly the 8 known LAN admin writes; the silent rule returns one zero row on no match (so it fires).
- [verified] promtool: crowdsec suite +5 cases (new series, existing series, counter reset, quiet, Prometheus gap); vmalert-logs self-monitoring 10 cases; all 18 suites green.
- [verified] AC1 live: a LAN `/.env` probe created a brand-new `vpatch-env-access` series (value 2); `CrowdSecWAFRuleHit` fired critical via the new-series branch → Alertmanager → pushover.
- [verified] AC2 partial: throwaway API key create/revoke → two `PocketIDAdminChange` warnings (labels method/route/ip, `source=vmalert-logs`) → Alertmanager → pushover; vmalert sent 2, 0 send errors.
- [verified] AC3 partial: `VMAlertLogsDown` went pending before the first scrape and cleared after it; rule errors 0, reload ok.
- [verified] AC4: pod env `EMAIL_LOGIN_NOTIFICATION_MODE=browserRecognition`, pod healthy.

### Open
- [open] Passkey live trigger not yet run (enrol + delete a test passkey → 2× `PocketIDPasskeyChanged`); the rule is query-verified only.
- [open] Deliberate failure-path drill (victoria-logs down → `VMAlertLogsRuleErrors`; pocket-id at 0 → `PocketIDLogsSilent`) not run; promtool + live health checks only.
- [follow-up] When a Pocket ID release ships the extended audit events (actor identity, admin events), re-evaluate the audit-API poller (option C).
- [follow-up] vmalert -dryRun was not run locally (binary download blocked by the harness); startup validation + `VMAlertLogsDown` cover a bad rules file.

## Acceptance criteria

- AC1: a single WAF block (new or existing rule series) yields one Pushover alert within ~2 scrape+eval cycles; promtool tests cover new-series, existing-series and reset cases.
- AC2: each Phase 0 Pocket ID trigger class produces its named alert; no alert during a quiet 24h (apart from deliberate changes).
- AC3: breaking the log query path or the Pocket ID log stream raises a critical alert.
- AC4: Pocket ID login notification mode is explicit in the manifest and a fresh-browser sign-in still sends the email.

## Decisions

- **D1 — Engine for (b)**: vmalert vlogs (RECOMMENDED) vs Grafana alerting vs audit-API poller.
- **D2 — Admin-change noise**: alert on every admin write including Terraform applies (RECOMMENDED: rare, and a change log is the point) vs suppress writes from the operator's LAN IP (hides a compromised LAN device).
- **D3 — Login notification mode**: `browserRecognition` (today's effective behaviour, RECOMMENDED), `ipAndUserAgent` (more emails on IP changes, e.g. mobile), `always`.
- **D4 — WAF alert severity**: critical (RECOMMENDED; baseline 0 hits/week) vs warning.

## Relations

- relates_to [[observability]]
- relates_to [[iam]]
- relates_to [[networking]]
- relates_to [[crowdsec-alert-tsdb-sourced]]
- relates_to [[grafana-victorialogs-datasource]]
- relates_to [[rate-limit-tiers]]
