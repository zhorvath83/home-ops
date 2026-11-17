---
title: grafana-victorialogs-datasource
type: roadmap
permalink: docs/progress/grafana-victorialogs-datasource
topic: Revert D13 — VictoriaLogs datasource in Grafana, first consumer a per-request
  denial list on the geo-gate dashboard
status: implemented
priority: low
scope: Add the victoriametrics-logs-datasource plugin (operator-managed, version-pinned,
  Renovate-tracked) and a VictoriaLogs GrafanaDatasource to the operator-managed Grafana,
  open the two network paths it needs, and append a per-request table of geo-denied
  requests to the "Envoy external — geo gate" dashboard. Supersedes decision D13 of
  grafana-operator-migration. Out of scope - log-based alerting (vmalert) and the
  Tier 2 geomap (onprem-geoip-country-filter section 6).
rationale: The geo gate is now the only country filter (Cloudflare rule removed 2026-11-14)
  and the only signal for a misclassified Hungarian client is a manual vmui query.
  Prometheus cannot hold per-request data (client IP, host, path, user agent), so
  a Grafana list needs a log datasource. D13 explicitly left a revert path for the
  case where in-Grafana log correlation becomes wanted; this is that case.
options:
- 'A (recommended): operator spec.plugins on the GrafanaDatasource (GF_INSTALL_PLUGINS,
  download from grafana.com at pod start), version pinned + Renovate'
- 'B: init container downloading the GitHub release zip with checksum verification
  into the plugins dir — github.com egress instead of grafana.com, more machinery,
  same startup dependency'
- 'C: custom Grafana image with the plugin baked in — no runtime egress, but an own
  image build pipeline; rejected (cost far above the value)'
- 'D: keep D13, add a vmui deep-link panel with a prefilled LogsQL query and the dashboard
  time range — zero new dependency, list opens outside Grafana'
related_areas:
- observability
- networking
- iam
---

# Grafana VictoriaLogs datasource (D13 revert) + geo-denial list

## Metadata (observation-form, schema validation)

- [topic] Revert D13 — VictoriaLogs datasource in Grafana, first consumer a per-request denial list on the geo-gate dashboard
- [status] implemented — option A (async-preinstall variant) live 2026-11-17, direct to main; two acceptance checks open (see Implementation); moved from docs/roadmap
- [priority] low
- [researched_at] 2026-11-16
- [effort] S–M (one PR, ~6 files, plus a live spike)

## What we gain

- A per-request table (time, client IP, country, host, path, method, user agent, response detail) at the bottom of the geo-gate dashboard, bound to the dashboard time range — the misclassified-HU check becomes a glance instead of a vmui query.
- Metric↔log correlation in one place for every later dashboard (e.g. CrowdSec 403s, Envoy 5xx detail).
- A Grafana Explore view on logs for the same audience that already has vmui.

## What we accept

- Grafana startup again depends on grafana.com (plugin download into an emptyDir on every pod start; the instance is stateless, D2). Failure mode is degraded, not down: Prometheus dashboards keep working, only log panels are empty until the next successful start.
- One more versioned artefact to keep current (plugin 0.x, frequent releases).
- The Grafana CNP widens again: grafana.com + plugin CDN egress, and victoria-logs:9428 egress (plus the matching ingress on the victoria-logs side).
- Grafana queries VictoriaLogs with its own pod identity, bypassing the vmui OIDC gate — acceptable only because both are infra_admins-only (see Security).

## Current state (evidence, 2026-11-16)

- [evidence] D13 text (docs/progress/grafana-operator-migration): no VictoriaLogs datasource/plugin; it was the only runtime-downloaded plugin; dropping it removed grafana.com / storage.googleapis.com / victoria-logs:9428 egress. Its follow-up names the revert: one GrafanaDatasource CR with `plugins:` + the CNP rules.
- [evidence] Pre-D13 setup (git 0edf7772e^, grafana/app/helmrelease.yaml): `GF_PLUGINS_PREINSTALL_SYNC: victoriametrics-logs-datasource@0.26.3`, datasource URL `http://victoria-logs-server.observability.svc.cluster.local:9428`; old CNP allowed grafana.com, *.grafana.com, storage.googleapis.com, *.storage.googleapis.com on 443 and victoria-logs:9428.
- [evidence] kubernetes/apps/observability/grafana/instance/grafana.yaml: Grafana 13.0.1 (live image), `plugins.plugin_admin_enabled: false`, `preinstall_disabled: true` and `public_key_retrieval_disabled: true` (both annotated D13), readOnlyRootFilesystem, only /tmp emptyDir declared in the CR (the operator adds its own data volume — verify mount of /var/lib/grafana/plugins).
- [evidence] grafana/instance/ciliumnetworkpolicy.yaml: egress gravatar, Prometheus 9090, Alertmanager 9093 only; header comment cites D13.
- [evidence] kube-prometheus-stack/app/grafanadatasource.yaml: Prometheus (default) + Alertmanager, comment cites D13.
- [evidence] victoria-logs/app/ciliumnetworkpolicy.yaml: default-deny ingress, explicit allows for kubelet probes, the collector, crowdsec; NO egress section. Grafana is not an allowed source today.
- [evidence] victoria-logs/app/grafanadashboard.yaml: two chart dashboards, Prometheus-only, comment cites D13.
- [evidence] victoria-logs ks.yaml: dependsOn onepassword-connect + pocket-id; uses components/gateway-oidc (SecurityPolicy victoria-logs-oidc live). Server v1.54.0, chart 0.13.13.
- [evidence] grafana-operator 5.25.0 (operator/ocirepository.yaml).
- [evidence] Dashboard kubernetes/apps/networking/envoy-gateway/config/dashboards/envoy-external-geo-gate.json: rows Gate health (y0) / Decisions (y6) / Denials (y23, one timeseries at y24 h8); one templating variable `datasource` (type prometheus). GrafanaDashboard has no `datasources:` mapping (variable-based).
- [evidence] envoy-external access log JSON fields (networking/envoy-gateway/config/envoy.yaml:74-97): start_time, method, ":authority", x-envoy-origin-path, protocol, response_code, response_flags, response_code_details, downstream_remote_address, downstream_direct_remote_address, x-forwarded-for, user-agent, request_id, upstream_host, upstream_cluster, duration_ms, bytes_received, bytes_sent, route_name, geo_country.
- [evidence] LogsQL verified live 2026-11-16 via the API: `_time:24h kubernetes.pod_name:envoy-external* response_code_details:rbac_access_denied* | stats by (geo_country) count()` returned NL 32, US 9, FR 4, IT 4, ID 2, KZ 2, LT 1.

## Research findings

- [fact] Plugin `victoriametrics-logs-datasource`: latest 0.34.0 (GitHub release 2026-11-06, catalog updated 2026-11-10), signatureType **commercial** (Grafana-signed), grafanaDependency `>=10.4.0` → Grafana 13 within range (functional check still in Phase 1). Release assets: zip + tar.gz + checksum files.
- [fact] grafana-operator (Context7, api/v1beta1/plugins.go + examples/datasource): `GrafanaDatasource.spec.plugins: [{name, version}]`, version is strict semver (no `v` prefix) or `latest`; the operator installs by setting `GF_INSTALL_PLUGINS` on the managed Grafana deployment → a plugin change rolls the pod (Recreate strategy → seconds of Grafana downtime, acceptable). The operator does not track new releases itself.
- [fact] Plugin query model (Context7, victorialogs dashboards): target `{datasource: {type: victoriametrics-logs-datasource, uid}, expr: <LogsQL>, queryType: instant}`; `stats_query_range` backs time-series panels; the dashboard time range is applied by the plugin.
- [fact] Pocket ID (provision/pocket-id/clients.yaml): `grafana` and `victoria-logs` clients are both restricted to `infra_admins`; grafana.yaml maps infra_admins → Admin, everyone else → None (role_attribute_strict). So the datasource does not widen who can read logs.
- [fact] Renovate: the generic inline manager (.renovate/customManagers.json5) reads `# renovate: datasource=X depName=Y` + the quoted value on the next line, default datasource github-releases, semver versioning. No native Grafana-plugin datasource.
- [unknown] Whether `plugins.preinstall_disabled: true` also suppresses `GF_INSTALL_PLUGINS` in Grafana 13 (in Grafana 12+ GF_INSTALL_PLUGINS is folded into the preinstall mechanism). Phase 1 decides; if it does, the key flips to false and the 5 default apps must be blocked another way (`plugins.preinstall` explicit list / `disable_plugins`), or the startup burst + HubblePolicyDeny returns.
- [unknown] Whether the commercial signature verifies with `public_key_retrieval_disabled: true` (bundled key). Expected yes (bundled key is Grafana's own); Phase 1 checks the log for `signature` errors.
- [unknown] Current download host chain from grafana.com (`storage.googleapis.com` in 2026-07; may have moved to a Grafana CDN). Phase 1 captures it with Hubble instead of guessing.
- [unknown] Renovate `v` prefix: github-releases tags are `v0.34.0`, the CR needs `0.34.0`. Needs `extractVersion: ^v(?<version>.+)$` via a packageRule (the inline annotation regex has no extractVersion group) — confirm with a Renovate dry run or the first PR.

## Target design (option A)

1. **Datasource** — new `kubernetes/apps/observability/victoria-logs/app/grafanadatasource.yaml` (co-located with the owning app, like Prometheus in kube-prometheus-stack): name `VictoriaLogs`, type `victoriametrics-logs-datasource`, access proxy, URL `http://victoria-logs-server.observability.svc.cluster.local:9428`, explicit stable `uid: victorialogs` (dashboards reference it), `plugins: [{name: victoriametrics-logs-datasource, version: "0.34.0"}]` with a `# renovate: datasource=github-releases depName=VictoriaMetrics/victorialogs-datasource` annotation. Add to app/kustomization.yaml.
2. **Flux ordering** — victoria-logs ks gains `dependsOn: grafana-operator` (CRD presence); verify no cycle (grafana-instance does not depend on victoria-logs).
3. **Grafana CR** — adjust plugins block per Phase 1 result; keep `plugin_admin_enabled: false`; rewrite the D13 comments.
4. **CNP grafana** — egress: grafana.com (+ the CDN host captured in Phase 1) on 443; victoria-logs-server pod on 9428. Rewrite header comment.
5. **CNP victoria-logs** — ingress from `app.kubernetes.io/name: grafana` (ns observability) on 9428.
6. **Renovate** — packageRule for depName VictoriaMetrics/victorialogs-datasource with extractVersion; decide automerge (no: 0.x, manual).
7. **Dashboard** — add a VictoriaLogs datasource variable (`vl`, type victoriametrics-logs-datasource) and a new row **"Denied requests (log)"** at y32:
   - Table "Geo-denied requests" (w24 h12): `kubernetes.pod_name:envoy-external* response_code_details:rbac_access_denied* | fields _time, downstream_remote_address, geo_country, ":authority", method, x-envoy-origin-path, user-agent, response_code_details | sort by (_time desc) | limit 500`, queryType instant; field overrides for column names/widths; no transformations beyond organize.
   - Optional second table "Top sources" (w12): `... | stats by (downstream_remote_address, geo_country) count() hits | sort by (hits desc) | limit 20` — decide in review (strips the port? downstream_remote_address carries ip:port, so a by-IP aggregation needs `| extract_regexp` or the unpack of the host part; verify).
   - Optional: a CrowdSec 403 table (`response_code_details:ext_authz_denied*`) — separate decision, it is a different gate.
8. **Docs** — supersede D13 in docs/areas/observability (+ a dated note in grafana-operator-migration follow-ups), record the working LogsQL in docs/areas/networking, update this note → progress.

## Security review points

- [check] Log readers do not widen: Grafana Admin = infra_admins = vmui ACL. Grafana viewers/editors do not exist (role None). Keep it so — a future Viewer role would expose all cluster logs; note it as a guardrail in the observability area.
- [check] The plugin runs a backend binary inside Grafana: signed (commercial), pinned version, no `allow_loading_unsigned_plugins`.
- [check] victoria-logs ingress opens only for the Grafana pod identity on 9428; VictoriaLogs has no auth, so this is a read+write path in principle (the /insert API is on the same port) — accepted, same as crowdsec's existing allow; note it.
- [check] Access-log content now visible in Grafana includes full client IPs and user agents — same data as vmui, no new audience.

## What to do (phased)

0. **Decide**: option A vs D (user). If D: one panel with a link, no further phases.
1. **Spike (live, revertible, no dashboard yet)**: commit datasource + CNPs + Grafana CR change to main (house practice for this repo) or test via a branch reconcile. Verify: Grafana pod Ready, log shows plugin installed (version 0.34.0), no signature error, no HubblePolicyDeny for grafana (capture the download FQDNs with `just k8s hubble-live-capture` + `hubble-analyze app.kubernetes.io/name=grafana DROPPED egress`), datasource health "OK" in Grafana (Connections → Data sources → Test), Explore returns envoy-external lines. Check whether `preinstall_disabled` blocked the install and adjust.
2. **Dashboard**: add variable + row + table(s); validate every panel against live data (the 24h window currently has ~54 rows). Check column rendering of the `:authority` / hyphenated field names.
3. **Renovate**: packageRule + verify the annotation is picked up (Renovate dependency dashboard issue lists the dep).
4. **Failure-mode test**: block grafana.com egress temporarily (or point version to a non-existent one on a scratch reconcile) and confirm Grafana still starts and Prometheus dashboards render; log panels show a datasource error, not a broken dashboard. Revert.
5. **Docs + close**: area notes updated, D13 marked superseded with reason and date, this note → docs/progress.

## Acceptance criteria

- Grafana Ready after a pod restart with the plugin loaded; plugin version equals the pinned one.
- Datasource Test = OK; no HubblePolicyDeny for grafana or victoria-logs in 1h after rollout.
- The geo-gate dashboard bottom table lists the same rows as the vmui query for the same window (count match).
- Renovate tracks the plugin version.
- With grafana.com unreachable, Grafana still serves the Prometheus dashboards.
- D13 superseded in BM with a link to this item.

## Rollback

- Revert the commit: the operator removes GF_INSTALL_PLUGINS, the pod restarts plugin-free, the dashboard row shows "datasource not found" until its revert (same commit). CNP and Grafana CR return to D13 state.

## Risks / open questions

- [risk] Plugin 0.x breaking changes in the query model → pin + manual Renovate review.
- [risk] Grafana 13 major upgrades may lag plugin compatibility → Renovate grafana bumps now also need a log-panel smoke check (add to the observability area checklist).
- [open] Top-sources table and CrowdSec table: in or out?
- [open] Should the CrowdSec 403 list later move here too (one "edge denials" view)?

## Implementation (2026-11-17)

Decisions (user, 2026-11-17): option A; both optional tables IN (top sources + CrowdSec 403); rollout direct to main.

- [deviation] Install path changed from `GrafanaDatasource.spec.plugins` to Grafana's async `plugins.preinstall` in the Grafana CR. Source-verified (grafana v13.0.1 setting_plugins.go + plugininstaller/service.go, run.sh; grafana-operator v5.25.0 deployment_reconciler.go): the operator only sets `GF_INSTALL_PLUGINS`; Grafana migrates it to `preinstall_sync`, which returns an error and halts startup on a failed download; `GF_INSTALL_PLUGINS_FORCE` instead runs `grafana cli` under `set -e`. Both would break the "Grafana up without grafana.com" acceptance criterion.
- [resolved] Unknown 1 — `preinstall_disabled: true` suppresses everything, including a migrated `GF_INSTALL_PLUGINS`. Removed; default apps blocked via `disable_plugins` (advisor included: `grafanaAdvisor=true` is live).
- [resolved] Unknown 2 — commercial signature verifies with `public_key_retrieval_disabled: true` (no signature error in the log).
- [resolved] Unknown 3 — download hosts: grafana.com + storage.googleapis.com suffice; Hubble capture 19:23–19:27 showed zero DROPPED for grafana egress / victoria-logs ingress.
- [resolved] Unknown 4 — version is a bare `0.34.0` in grafana ks `postBuild.substitute.VL_PLUGIN_VERSION` (the inline regex needs the version as its own quoted value); `.renovate/overrides.json5` adds `extractVersion: ^v(?<version>.+)$`.
- [commits] 6bbd18b0c (datasource, Grafana CR, CNPs, dependsOn grafana-operator, D13 comments), 8b9c277b7 (Renovate rule), 085bc62c4 (dashboard row).
- [verified] Plugin 0.34.0 installed ~7 s after pod start; datasource Test = "Data source is working"; dashboard live with 17 panels, `vl` variable, three tables; each panel query returned rows over 7 d (500 / 20 / 8).
- [finding] 14 envoy-external access-log lines in 7 d have a corrupted `response_code_details` prefix (`…ess_denied_matched_policy[DENY]`); the geo table uses `response_code_details:~"denied_matched_policy"` so they are not dropped. Root cause open (docs/areas/networking).
- [finding] After any Grafana restart, datasources are absent until the operator's next resync (≤10 min) — pre-existing; follow-up candidate.
- [incident] During verification the provisioning admin password was echoed into the session output by BusyBox wget (unsupported `--password` flag). Rotated by the user in 1Password the same evening; ESO synced and Grafana restarted; operator authenticates with the new value. Lesson: in the Grafana pod pass credentials only as a computed `Authorization` header, never as CLI flags.
- [open] Acceptance "Renovate tracks the plugin version": not yet observed — check the Renovate Dashboard issue after the next Renovate run.
- [open] Acceptance "Grafana serves Prometheus dashboards with grafana.com unreachable": verified from source (async path logs and continues), NOT exercised live.
