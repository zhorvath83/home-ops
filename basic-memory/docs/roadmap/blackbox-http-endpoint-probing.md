---
title: blackbox-http-endpoint-probing
type: roadmap
permalink: home-ops/docs/roadmap/blackbox-http-endpoint-probing
topic: Active HTTP endpoint probing with the already-deployed blackbox-exporter
status: done
priority: medium
scope: 'Add Probe CRs that actually use the http_2xx module already configured in
  the blackbox-exporter HelmRelease, plus a matching PrometheusRule. Split out of
  docs/roadmap/observability-probes-and-disk-health on 2026-08-01: that item delivered
  the blackbox-exporter app and its ICMP/TCP probes (which serve the NFS zeroscaler
  HPA) and the smartctl-exporter, but never delivered HTTP probing — the capability
  its rationale was written for.'
rationale: 'The http_2xx module is fully configured and completely unused: zero Probe
  CRs reference it. So the original pain is still uncovered — if cloudflared, an HTTPRoute,
  or an upstream chart silently 5xx-es, nothing detects it and only a user report
  surfaces the failure. A configured-but-unused prober module is also a standing invitation
  to assume the coverage exists when it does not.'
options:
- Probe the internal gateway directly (bypasses Cloudflare/Access, tests the cluster
  path only)
- Probe public hostnames through the Cloudflare Tunnel (end-to-end, but Access-gated
  apps need valid_status_codes tuning)
- Both, as separate jobs, so a tunnel outage is distinguishable from an app outage
related_areas:
- observability
- networking
- iam
---

# Active HTTP endpoint probing with the already-deployed blackbox-exporter

## Metadata (observation-form, schema validation)

- [topic] Active HTTP endpoint probing with the already-deployed blackbox-exporter
- [status] done
- [priority] medium
- [created] 2026-08-01 — split out of [[observability-probes-and-disk-health]] after an audit
  found the HTTP half of that item was never delivered

## The gap (evidence)

- [evidence] The `http_2xx` module IS fully configured in
  `kubernetes/apps/observability/blackbox-exporter/app/helmrelease.yaml:19-27` —
  `prober: http`, `timeout: 5s`, `valid_http_versions: [HTTP/1.1, HTTP/2.0]`,
  `follow_redirects: true`, `preferred_ip_protocol: ip4`.
- [evidence] **Zero Probe CRs use it.** `kubernetes/apps/observability/blackbox-exporter/app/probes.yaml`
  contains exactly two: `devices` (`module: icmp` → `nas.lan`) and `nfs`
  (`module: tcp_connect` → `nas.lan:2049`). A repo-wide grep for `http_2xx` returns a single
  hit — the module definition itself.
- [evidence] Both existing probes exist to serve the NFS-dependency zeroscaler HPA via
  `probe_success` (see [[nfs-dependency-zeroscaler]] and [[prometheus-adapter]]), not endpoint
  monitoring.
- [observation] The parent item [[observability-probes-and-disk-health]] was recorded as having
  its blackbox half DONE because the app was deployed. That conflated *app deployed* with
  *capability delivered*; corrected on 2026-08-01.

## Design questions to settle before implementation

- [question] **Vantage point.** Probing a public hostname from inside the cluster leaves through
  the Cloudflare Tunnel and comes back in — it tests the whole chain but is sensitive to
  Cloudflare itself. Probing the internal gateway directly tests only the cluster path. Running
  both as separate jobs makes a tunnel outage distinguishable from an app outage, at the cost of
  two Probe sets.
- [question] **Access/OIDC-gated apps.** Routes behind Cloudflare Access or the `gateway-oidc`
  Envoy-native gate (see [[iam]]) will not return 200 to an unauthenticated prober — they
  redirect or 403. Those targets need `valid_status_codes` tuned to the expected gate response,
  or a dedicated module; otherwise the probe reports a false outage. Enumerating which routes are
  gated is part of this work.
- [question] **Target list and its maintenance.** Static target lists in a Probe CR drift as apps
  come and go. Decide between an explicit curated list (few, high-value routes) and something
  derived from the HTTPRoute inventory. A curated short list is the likely right answer for a
  homelab, but it must be a conscious choice.
- [question] **Alert semantics.** `BlackboxProbeFailed` already exists for `probe_success == 0`
  and is NOT job-scoped, so new HTTP probes would inherit it immediately. Decide whether that is
  desired (one generic alert) or whether HTTP targets need their own thresholds, `for` durations,
  and severity — a flapping public route should probably not page like a dead NFS mount.
- [question] **Cert expiry.** The http prober also exposes `probe_ssl_earliest_cert_expiry`;
  decide whether to alert on it here or leave TLS expiry to cert-manager's own signals.

## Related

- relates_to [[observability]]
- relates_to [[networking]]
- relates_to [[iam]]
- continues [[observability-probes-and-disk-health]]
- relates_to [[nfs-dependency-zeroscaler]]
- relates_to [[prometheus-adapter]]
