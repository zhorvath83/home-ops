---
title: blackbox-http-endpoint-probing
type: progress_note
permalink: home-ops/docs/progress/blackbox-http-endpoint-probing
topic: Active HTTP endpoint probing of the Pocket IdP via the blackbox-exporter http_2xx
  module
status: done
priority: medium
scope: One http_2xx probe of https://idm.${PUBLIC_DOMAIN} (Pocket IdP), the allow-gateways
  pod label for the envoy-internal hairpin, a BlackboxTLSCertExpiringSoon rule scoped
  to the cluster's shortlived LE cert profile (threshold 1 day), and promtool unit
  tests. Delivered direct to main. Absorbs the former roadmap item docs/roadmap/blackbox-http-endpoint-probing
  (deleted on merge).
related_areas:
- observability
- networking
- iam
tags:
- observability
- networking
- iam
---

# Blackbox HTTP endpoint probing (idm) — delivered

Active HTTP endpoint probing of the Pocket IdP via the already-deployed blackbox-exporter
`http_2xx` module. This note now also absorbs the former roadmap item
`docs/roadmap/blackbox-http-endpoint-probing` (the gap rationale and the design questions that
preceded delivery); the roadmap note was deleted on merge, 2026-08-01.

## Background — the gap (evidence)

- [evidence] The `http_2xx` module IS fully configured in `kubernetes/apps/observability/blackbox-exporter/app/helmrelease.yaml:19-27` — `prober: http`, `timeout: 5s`, `valid_http_versions: [HTTP/1.1, HTTP/2.0]`, `follow_redirects: true`, `preferred_ip_protocol: ip4`.
- [evidence] **Zero Probe CRs used it before this work.** `kubernetes/apps/observability/blackbox-exporter/app/probes.yaml` contained exactly two: `devices` (`module: icmp` → `nas.lan`) and `nfs` (`module: tcp_connect` → `nas.lan:2049`). A repo-wide grep for `http_2xx` returned a single hit — the module definition itself.
- [evidence] Both pre-existing probes exist to serve the NFS-dependency zeroscaler HPA via `probe_success` (see [[nfs-dependency-zeroscaler]] and [[prometheus-adapter]]), not endpoint monitoring.
- [observation] The parent item [[observability-probes-and-disk-health]] was recorded as having its blackbox half DONE because the app was deployed. That conflated *app deployed* with *capability delivered*; corrected on 2026-08-01. This item was split out to deliver the HTTP half the original rationale was written for.

## Metadata (observation-form, schema validation)

- [topic] Active HTTP endpoint probing of the Pocket IdP via the blackbox-exporter http_2xx module
- [status] done
- [priority] medium
- [created] 2026-08-01 — delivered direct to main (Flux GitOps watches refs/heads/main)
- [absorbed] 2026-08-01 — merged the former roadmap item docs/roadmap/blackbox-http-endpoint-probing into this progress note; roadmap deleted on merge

## Design questions → resolutions

The roadmap posed five open questions before implementation; this delivery settled them as follows.

- [question] **Vantage point** (internal gateway direct vs public through the tunnel vs both as separate jobs) → [resolution] ONE job probing the public hostname `https://idm.${PUBLIC_DOMAIN}`, which coredns rewrites to envoy-internal so the probe hairpins through envoy on :10443. Tests the internal cluster path end-to-end without a second job. See *What shipped*.
- [question] **Access/OIDC-gated apps** would not return 200 to an unauthenticated prober → [resolution] The idm `/` path has no gateway-level pre-auth, so a 200 comes from the backend itself and the `http_2xx` module is used AS IS (no `valid_status_codes` tuning). Enumerating and probing other gated routes remains open — see *Out of scope / follow-ups*.
- [question] **Target list and its maintenance** (curated vs HTTPRoute-derived) → [resolution] A conscious curated choice of a single high-value target (the Pocket IdP, the shared OIDC failure point behind every OIDC-gated app). A broader HTTPRoute-derived list is still open — see *Out of scope / follow-ups*.
- [question] **Alert semantics** — whether to reuse `BlackboxProbeFailed` or add HTTP-specific thresholds → [resolution] `BlackboxProbeFailed` (`probe_success == 0`, `for 2m`, critical, NOT job-scoped) covers the new probe automatically and was left untouched. A separate `BlackboxTLSCertExpiringSoon` rule was added for TLS expiry. See *What shipped* and *Correction 1*.
- [question] **Cert expiry** — alert here or leave to cert-manager → [resolution] Alert here via `probe_ssl_earliest_cert_expiry`. No cert-manager PrometheusRules exist repo-wide (grep found zero), so this blackbox signal is the only TLS-expiry observation that exists, observing the cert as a real client sees it. Threshold `< 1 day` for the shortlived LE cert profile. See *Correction 1*.

## What shipped

- [decision] ONE probe target: https://idm.${PUBLIC_DOMAIN} (Pocket IdP, the shared OIDC failure point behind every OIDC-gated app). The / path has no gateway-level pre-auth, so a 200 comes from the backend itself.
- [delivered] kubernetes/apps/observability/blackbox-exporter/app/probes.yaml — third Probe CR "idm" (jobName idm_probe, interval 60s, module http_2xx, target https://idm.${PUBLIC_DOMAIN} literal placeholder; root cluster-apps Kustomization substitutes ${PUBLIC_DOMAIN} via postBuild).
- [delivered] kubernetes/apps/observability/blackbox-exporter/app/helmrelease.yaml — added pod label egress.home.arpa/allow-gateways: "true". The pod is custom-egress opt-out, so its CNP is the sole egress source; coredns rewrites idm.${PUBLIC_DOMAIN} to envoy-internal, so the probe hairpins through envoy on :10443, granted by the cluster CCNP allow-gateways-egress for that label (precedent: grafana, pingvin-share-x).
- [delivered] kubernetes/apps/observability/blackbox-exporter/app/ciliumnetworkpolicy.yaml — one-line comment noting the http_2xx egress is granted by the allow-gateways label (cluster CCNP), not this CNP.
- [delivered] kubernetes/apps/observability/blackbox-exporter/app/prometheusrule.yaml — new BlackboxTLSCertExpiringSoon rule (final threshold below). The existing BlackboxProbeFailed (probe_success == 0, for 2m, critical, NOT job-scoped) covers the new probe automatically and was left untouched.
- [delivered] kubernetes/apps/observability/blackbox-exporter/tests/prometheusrule_test.yaml — promtool unit tests for BlackboxTLSCertExpiringSoon (fire + no-fire, asserting exp_labels AND exp_annotations). Run via "just k8s test-prom-rules".
- [decision] http_2xx module used AS IS (no rename, no follow_redirects change, no valid_status_codes); idm / returns 200 directly.

## Commits (all direct to main)

- 3819511ed — feat(observability): probe the Pocket ID endpoint via blackbox http_2xx (the 4-file change: helmrelease label, probes idm, prometheusrule, cnp comment).
- 2510068e6 — test(observability): cover BlackboxTLSCertExpiringSoon with promtool (added after the Maestro review caught the missing repo promtool-test convention).
- f207d2949 — fix(observability): scope TLS expiry threshold to the shortlived cert profile (the threshold correction).

## Live evidence (verified post-push, 2026-08-01)

- [evidence] flux get ks -n observability blackbox-exporter → Ready, Applied revision refs/heads/main@sha1:f207d2949.
- [evidence] Prometheus probe_success{job="idm_probe"} = 1; probe_http_status_code{job="idm_probe"} = 200; probe_duration ≈ 29ms.
- [evidence] (probe_ssl_earliest_cert_expiry{job="idm_probe"} - time()) / 86400 → 5.99 days remaining (matches the shortlived cert profile: 6.67-day lifetime, renewed at 2.22 days).
- [evidence] BlackboxTLSCertExpiringSoon rule state = inactive (not firing, not pending) under the final < 1 threshold; after the Prometheus rule reload it cleared on the first evaluation (5.99 > 1).
- [evidence] Hubble: "just k8s hubble-analyze k8s:app.kubernetes.io/name=prometheus-blackbox-exporter DROPPED egress" → "No flows matched the filter" (zero dropped egress — the allow-gateways label grants the envoy-internal hairpin).
- [evidence] curl https://idm.horvathzoltan.me/ from the LAN → 200, ssl_verify_result=0.

## Correction 1 — shortlived-cert threshold error

- [correction] The original threshold was < 14 days, assuming a standard 90-day Let's Encrypt cert renewed at ~30 days. This cluster issues SHORT-LIVED LE certs (profile: shortlived in kubernetes/apps/cert-manager/cert-manager/issuers/clusterissuer.yaml): the live envoy-internal cert is 6.67 days lifetime, renewed at 2.22 days remaining. A healthy cert here is never more than 6.67 days from expiry, so the < 14 rule would fire permanently and page within an hour — it was deployed at 3819511ed and had already entered pending when caught.
- [correction] First re-scoped to < 1.5 (Maestro), then the human overruled to exactly < 1 day. Final expr: (probe_ssl_earliest_cert_expiry{job="idm_probe"} - time()) / 86400 < 1. Rationale: renewal at 2.22 days, so under 1 day means renewal has been failing ~29h, with ~24h lead before actual expiry. A one-line comment encodes this above the rule.
- [evidence] No cert-manager PrometheusRules exist repo-wide (grep found zero), so this blackbox probe_ssl_earliest_cert_expiry signal is the only TLS-expiry observation that exists, and it observes the cert as a real client sees it.

## Correction 2 — concurrent-human-commit incident (the cancelled amend)

- [incident] The Maestro initially instructed git commit --amend to fold the promtool test into 3819511ed. Before it ran, the human landed 323418c8e (their NAS smartctl work stream) on main, so 3819511ed was no longer HEAD. --amend would have rewritten the human's commit and silently folded my test into their work.
- [correction] The Maestro revoked the amend; the test became its own commit 2510068e6 on top of HEAD. No rebase, no reorder, no rewrite.
- [observation] During the fix work the human committed again (596d61814 docs: close nas-host-exporters), moving HEAD a second time. Per the extra-care protocol I re-checked git status + git log -1 before every git write and confirmed my working changes were intact and I was carrying none of the human's files before each commit.
- [lesson] On a repo where commit-to-main IS the deploy and humans commit concurrently, --amend is unsafe once a commit has been pushed or could be crossed by a concurrent commit; a new commit on top is always safe. The pre-flight git log -1 before any git write is the guardrail that caught this.

## Out of scope / follow-ups

- [followup] BlackboxProbeFailed has NO promtool unit test. That gap is owned by the separate roadmap item [[prometheusrule-unit-test-coverage]], not this change.
- [followup] Only idm is probed today. The broader target list (HTTPRoute-derived, Access-gated apps needing valid_status_codes tuning) is still open — the design questions *Access/OIDC-gated apps* and *Target list* above resolve to this open follow-up for the non-idm routes.

## Related

- continues [[observability-probes-and-disk-health]]
- relates_to [[observability]]
- relates_to [[iam]]
- relates_to [[networking]]
- relates_to [[nfs-dependency-zeroscaler]]
- relates_to [[prometheus-adapter]]
