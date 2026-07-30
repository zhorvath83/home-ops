---
title: crowdsec-psa-removal-and-official-chart-migration
type: progress_note
permalink: home-ops/docs/progress/crowdsec-psa-removal-and-official-chart-migration
---

# crowdsec-psa-removal-and-official-chart-migration — execution progress

## Metadata (observation-form)

- [topic] Execution state for the crowdsec PSA-relaxation (explicit privileged) + official-chart migration + file-datasource acquisition
- [status] implemented — Part 8 verified; two sub-criteria await a natural event (envoy-pod-recreation survival, victoria-logs-replacement non-event) and two await a Maestro action (local-decision origin trigger, OIDC live login)
- [roadmap] [[crowdsec-psa-removal-and-official-chart-migration]]
- [priority] high
- [area] k8s-workloads, networking, observability
- [created] 2026-07-30
- [last-updated] 2026-07-30 (post-step-4 closeout: step 3B landed + Part 8 verified live by the Maestro; docs commit in this step)

> This note was rewritten at the post-3A checkpoint and again at the step-4 closeout. The earlier body was the pre-implementation ratified spec; that spec is now history. The sections below describe what actually landed, the Part 8 verification results, and what remains. A cold reader can resume from here without the session transcript.

## Commits that landed (all on main, direct commits — repo norm)

- [step] 8977dd70e — Step 1: envoy access-log field renames. Renamed four JSON fields in both EnvoyProxy access-log blocks (path to x-envoy-origin-path, authority to :authority, x_forwarded_for to x-forwarded-for, user_agent to user-agent). Verified live: both EnvoyProxy CRs carry the new keys; live envoy config_dump access_log json_format carries the new names; envoy-external and envoy-internal pods Running 2/2, 0 restarts, no CrashLoop. Independent and reversible; landed first per the cutover sequence.
- [step] 64f3881aa — Step 2: official chart migration + cutover. New ocirepository.yaml (official oci://ghcr.io/crowdsecurity/helm-charts/crowdsec tag 0.24.0) + full helmrelease.yaml rewrite (LAPI Deployment + agent DaemonSet + AppSec Deployment) + 6 supporting files: namespace (single enforce: privileged label), kustomization (added ocirepository, removed 3 configMapGenerator entries), deletion of acquis.yaml / config.yaml.local / profiles.yaml (content moved inline), ciliumnetworkpolicy (rewritten as 4 documents), prometheusrule (new job labels + new acquisition selector). Cutover happened automatically via GitHub webhook to Flux. Old app-template 5.0.1 release removed; old LAPI PVCs destroyed by reclaimPolicy Delete (DB lost — intended, human-accepted; CAPI/list decisions re-streamed, only local decisions lost). No ConfigMap ownership collision: the old crowdsec-profiles and crowdsec-config-local ConfigMaps were pruned before the new HelmRelease installed. 3 pods Running 1/1; agent+appsec auto-registered via the init-container REGISTRATION_TOKEN; CAPI blocklist ~15000 entries re-streamed; web-ui machine registered by the postStart hook.
- [step] f603ef281 — Step 3A part 1: point bouncer and web-ui at the split services. Three one-line edits: bouncer lapiURL to crowdsec-service.crowdsec.svc.cluster.local:8080, bouncer appSecURL to crowdsec-appsec-service.crowdsec.svc.cluster.local:7422, web-ui CONFIG_INSTANCE_LAPI_URL to crowdsec-service.crowdsec.svc.cluster.local:8080. CONFIG_INSTANCE_METRICS_URL left untouched (deferred to step 3B). The HelmRelease upgrade rewrote the bouncer ConfigMap with the new URLs, but the bouncer pod was NOT restarted by it (see the Reloader finding).
- [step] bd42ec51c — Step 3A part 2: durable Reloader fix. A postRenderer kustomize patch injecting reloader.stakater.com/auto: "true" onto the bouncer Deployment metadata.annotations (the chart exposes no such key). Durable for all future bouncer ConfigMap changes. Did NOT roll the running pod by itself (Reloader is event-driven — see below).
- [step] 159f3b664 — Step 3B: fan web-ui metrics to the three split pods. Replaced the single dead CONFIG_INSTANCE_METRICS_URL (pointing at the gone `crowdsec` service) with three named metrics endpoints on instance 0 — LAPI / Agent / AppSec — each with a stable id (lapi/agent/appsec), name, and :6060 URL against crowdsec-service / crowdsec-agent-service / crowdsec-appsec-service. Single-instance deployment, so scalar instance fields stay on the CONFIG_INSTANCE_* shorthand (incl. LAPI auth, whose password still arrives via the unchanged CONFIG_INSTANCE_LAPI_AUTH_PASSWORD secret key); only the metrics array moves to the indexed CONFIG_INSTANCES_0_METRICS_<j>_* form. The README at image tag 2026.7.24 states the shorthand and indexed forms are equivalent and must not be set together, and the shorthand has no metrics index past 0, so "do not set equivalent forms together" forbids keeping both spellings of metrics[0] — hence the block-level move of the whole metrics array to indexed, with no shorthand surviving. Verified live: all nine CONFIG_INSTANCES_0_METRICS_* env vars on the Deployment, no surviving shorthand, new pod Running 1/1.

## Live-verified state (post step 3A, after the one-time rollout restart)

- [verified] Three crowdsec workloads Running 1/1, 0 restarts: crowdsec-lapi (Deployment), crowdsec-agent (DaemonSet), crowdsec-appsec (Deployment); plus crowdsec-bouncer and crowdsec-web-ui.
- [verified] PSA: the crowdsec namespace carries exactly one PSA label, pod-security.kubernetes.io/enforce: privileged (the agent DaemonSet mounts hostPath /var/log). The kustomize.toolkit.fluxcd.io/prune: disabled annotation is preserved. This matches the roadmap chosen option (explicit privileged over bare label removal).
- [verified] CPU-limit removal survived the full Flux/Helm/API round-trip: limits.cpu: null on lapi/agent/appsec rendered through to the live Deployment and DaemonSet — no CPU limit on any of the three. (Helm deletes a null key; the chart default 500m did not survive.)
- [verified] Token-mount hygiene: automountServiceAccountToken: false and enableServiceLinks: false on crowdsec-lapi/appsec/agent via the postRenderer patches, and on web-ui via values. (Bouncer chart does not expose automountServiceAccountToken — see follow-ups.)
- [verified] Agent file acquisition: agent tails envoy-external-* and envoy-internal-* pods in networking (program: envoy, poll_without_inotify: true). Note the glob actually matches 6 files not 2 — see follow-ups.
- [verified] All machines authenticating to the LAPI: cscli machines list shows crowdsec-lapi, crowdsec-agent, crowdsec-appsec, crowdsec-web-ui all healthy with recent last-seen; LAPI access logs show web-ui heartbeat 200 and usage-metrics 201 every 30s, and the bouncer GET /v1/decisions/stream 200 every 10s.
- [verified] Bouncer decision sync: bouncer logs "Using API key auth" and "initial decision sync complete"; LAPI returns 200 on the decisions/stream pull every 10s. The "no such host" errors are GONE.
- [verified] postStart hook registered the web-ui machine — this was the roadmap riskiest open task (Part 7). Proven live: the crowdsec-web-ui machine exists (cscli) and the web-ui heartbeats with HTTP 200 (only possible if the machine exists). Correction 1 (postStart must exit 0) validated.

## Step 3B live-verified state

- [verified] web-ui Deployment carries all nine indexed metrics env vars (CONFIG_INSTANCES_0_METRICS_0/1/2 _ID/_NAME/_URL) and NO surviving shorthand CONFIG_INSTANCE_METRICS_URL. Scalar instance fields (NAME, LAPI_URL, LAPI_AUTH_USERNAME) stay shorthand; the LAPI auth password secret key CONFIG_INSTANCE_LAPI_AUTH_PASSWORD is unchanged.
- [verified] The new web-ui pod is Running 1/1; its three :6060 metric endpoints (lapi/agent/appsec) each return data — the metrics page is no longer empty.
- [verified] The LAPI auth path is untouched: the ExternalSecret still renders CONFIG_INSTANCE_LAPI_AUTH_PASSWORD from .WEBUI_LAPI_PASSWORD, and the web-ui machine still heartbeats HTTP 200.

## Design defects caught in Maestro review before they shipped (lessons, not just fixes)

- [lesson] Crashlooping postStart hook. The first-draft postStart would exit non-zero when cscli machines add failed (it fails until /etc/crowdsec is seeded by the entrypoint, which races postStart). A non-zero postStart makes the kubelet restart-loop the LAPI. Correction 1: retry cscli 30 times (2s apart) and exit 0 either way; every dollar sign is Flux-escaped (doubled) so the registration token and AGENT_PASSWORD survive Flux substitution. Lesson: a postStart hook for non-fatal seeding must never exit non-zero — kubelet treats non-zero postStart as a pod failure and restart-loops it.
- [lesson] Silently inherited 500m CPU limit. Helm deep-merges maps, so the chart default limits.cpu: 500m survived on all three components unless explicitly deleted. Correction 2: set limits.cpu: null on each (Helm deletes a null key). Lesson: chart-inherited resource values can silently override an intended no-CPU-limit policy; an explicit null is required to delete a map key, and the round-trip (Helm to Flux to API to live workload) must be checked, not assumed.

## The Reloader finding (full — this costs an hour to rediscover)

- [finding] The envoy-proxy-bouncer chart 0.6.3 exposes NO Deployment-metadata annotation key. Its templates/deployment.yaml metadata block has only name and labels (no annotations field at all); the only annotation hooks are podAnnotations (pod template), httproute.annotations, grafana.dashboard.annotations. Reloader reads reloader.stakater.com/auto off the workload metadata.annotations — NOT the pod template — so podAnnotations is useless for this.
- [fix] Injected reloader.stakater.com/auto: "true" onto the bouncer Deployment metadata.annotations via a Flux postRenderer kustomize patch (commit bd42ec51c) — the documented use of postRenderers ("when an upstream chart leaves no other way to patch a manifest field"). Matches crowdsec-lapi and crowdsec-web-ui which carry it natively (lapi via chart deployAnnotations, web-ui via app-template controller annotations). Verified live: the annotation is on the Deployment metadata.
- [finding] Reloader is EVENT-driven. It rolls an annotated Deployment on a ConfigMap/Secret CHANGE event (its logs: "Changes detected in <cm> ... updated <deploy>"). It stores NO hash on the pod template (crowdsec-lapi pod template carries only the chart own checksum annotations, no reloader.stakater.com/configmaps-hash) — so it does NOT retroactively roll.
- [consequence] The bouncer ConfigMap changed at the 19:42 reconcile (commit f603ef281), BEFORE the reloader annotation existed (added at 19:48, bd42ec51c). Reloader skipped that change event; adding the annotation afterward did not replay it. The pod-template hash did not change either (the metadata-annotation patch does not touch the pod template), so k8s itself did not roll — confirmed by no new ReplicaSet (both RS date from 2 days prior).
- [resolution] One-time, human-approved kubectl -n crowdsec rollout restart deployment/crowdsec-bouncer got the running pod onto the already-correct ConfigMap. This was the LAST manual nudge this gap needs: the durable annotation now handles every future change. Lesson: for Reloader to auto-roll a config change, the annotation must precede the change event; if it does not, a single bridge restart is needed and the durable annotation prevents recurrence.

## Deviations from the roadmap and why

- [deviation] docker.io image prefix. The roadmap Part 5 specified image.repository: crowdsecurity/crowdsec; the approved HelmRelease uses docker.io/crowdsecurity/crowdsec (the # renovate: depName was updated to match). Reason: explicit registry prefix for unambiguous digest/Renovate resolution. Approved in Maestro review.
- [deviation] Bouncer/web-ui cross-refs deferred to step 3A. The roadmap cutover sequence (Part 6) bundled the bouncer/web-ui reference updates with the app rewrite. We split them into a separate step 3A (commits f603ef281 + bd42ec51c) AFTER the cutover, because the bouncer fails closed while the LAPI is down anyway and the split kept the cutover commit focused. Deliberate Maestro-driven sequencing.
- [deviation] Web-ui metrics fan-out deferred to step 3B. The roadmap Part 5 included the indexed CONFIG_INSTANCES_0_METRICS_* fan-out in the web-ui update. Step 3A only fixed the LAPI URL; the metrics fan-out (and the agent/appsec :6060 CNP ingress it depends on) is step 3B — now landed in commit 159f3b664.
- [note] Not a deviation: the PSA privileged choice matches the roadmap (which explicitly chose it over bare removal); the LAPI PVC/DB loss matches the roadmap Part 6 (intended, no rollback); no ConfigMap ownership collision because the old CMs were pruned before install.

## Part 8 — verification against the roadmap acceptance criteria

Verified live by the Maestro (port-forward to prometheus-operated) and by the worker (read-only kubectl / cscli), 2026-07-30. Criteria are not rounded up — PENDING is PENDING.

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | lapi/agent/appsec 0 restarts; one PSA label; no PSA admission event | PASS | 3 pods Running 1/1 0 restarts; namespace carries exactly pod-security.kubernetes.io/enforce: privileged; `kubectl get events -n crowdsec` → no PodSecurity admission events |
| 2 | cscli metrics: envoy file reads + cri-logs→envoy-logs→http-logs parser hits | PASS | envoy-external 14 reads/4 hits, envoy-internal 91 reads/27 hits; cri-logs/envoy-logs/http-logs parser hit counters all present |
| 3 | ROOT: cs_parser_hits_ok_total{acquis_type="containerd", source=~"/var/log/containers/envoy-.*"} climbs continuously across an envoy pod recreation AND across a victoria-logs-server replacement | PARTIAL/PENDING | Counter EXISTS with the NEW label set — exactly 2 series, both job=crowdsec-agent-service acquis_type=containerd: source=envoy-external-… value=4, source=envoy-internal-… value=27. Real envoy access logs parsed end-to-end through cri-logs→envoy-logs. The across-an-envoy-pod-recreation climb is NOT yet proven (no recreation event occurred this session — deliberately not forced, it is cluster-mutating). The victoria-logs-server replacement arm is now structurally a non-event (the victorialogs datasource is gone from the acquisition). PENDING a natural envoy recreation (Renovate envoy-gateway bump, node reboot, Talos upgrade) — see Next. |
| 4 | cs_active_decisions has origin="crowdsec" after a local trigger | PENDING | Only CAPI decisions present (~1912 + ~13088); no local origin=crowdsec decision. Producing one needs a deliberate Maestro-approved local trigger (adds a local ban) — see Next. |
| 5 | bouncer extAuth + appsec serve; web-ui OIDC + LAPI machine | PASS/PENDING | appsec cs_appsec_reqs_total{source="10.244.0.214"}=1 (served); bouncer heartbeat 200 + decisions/stream 200; web-ui machine registered (cscli machines list) and heartbeats 200. OIDC live browser login through idm.horvathzoltan.me → crowdsec web-ui is PENDING a Maestro portal action — see Next. |
| 6 | web-ui three :6060 endpoints return data | PASS | Step 3B live: all nine CONFIG_INSTANCES_0_METRICS_* env vars on the Deployment, no surviving shorthand, new pod Running 1/1; lapi/agent/appsec :6060 each return data |
| 7 | prometheus: three ServiceMonitors + two PrometheusRules with the new job labels, against live targets | PASS | Maestro port-forward to prometheus-operated: up{namespace="crowdsec"} → job=crowdsec-service (pod crowdsec-lapi-748bd798cf-d4p4j) up=1, job=crowdsec-agent-service (pod crowdsec-agent-n69l4) up=1, job=crowdsec-appsec-service (pod crowdsec-appsec-778b798fd-pdtj7) up=1, job=crowdsec-bouncer up=1. The three job labels prometheusrule.yaml asserts are EXACTLY the ones Prometheus assigns — the roadmap "confirm against live targets" caveat is discharged. Alert rules CrowdSecLAPIDown, CrowdSecAcquisitionStalled, CrowdSecBouncerDown all loaded (health=ok, inactive). |
| 8 | envoy renamed JSON fields + victoria-logs ingestion of envoy access logs | PASS | A live envoy access-log row carries all four renamed keys (x-envoy-origin-path, :authority, x-forwarded-for, user-agent); the old names are absent; a corresponding record is ingested into victoria-logs with all four renamed keys |
| 9 | no API service-account token mounted in the three pods | PASS | automountServiceAccountToken: false via postRenderer patches (lapi/appsec/agent) and values (web-ui); no SA-token volume on any pod |

## Notable findings from the Part 8 verification (record against the right follow-ups)

- [notable] cs_parser_hits_ok_total has exactly TWO series — both envoy. The k8tz and shutdown-manager sidecar log files that the agent acquisition glob also matches (6 files, not 2) produced ZERO parser hits. The over-matching is empirically harmless — the envoy parser needs a JSON line, which the sidecar text logs do not provide. This is evidence FOR the human's decision to record the glob over-match as a follow-up rather than fix it now.
- [notable] A HubblePolicyDeny alert fired at 22:04 during the step-3A rollout restart. It was the OLD bouncer pod IP dying during the human-approved rollout restart of deployment/crowdsec-bouncer — transient, not a policy defect. A 20s Hubble capture afterward shows envoy-internal → crowdsec-bouncer:8080 FORWARDED and zero DROPPED flows.
- [notable] cscli machines list (live, 2026-07-30T20:35Z): exactly 4 machines, all healthy, all recent heartbeats — crowdsec-web-ui (6s), crowdsec-lapi-748bd798cf-d4p4j (12s), crowdsec-agent-n69l4 (57s), crowdsec-appsec-778b798fd-pdtj7 (59s). The agent/appsec/lapi machine names are pod-name-based, so the machine list WILL grow on every pod recreation (the churn follow-up is structurally real); currently no stale entries, but a periodic `cscli machines prune` may be warranted once stale entries accumulate.

## Follow-ups

Inherited from the roadmap Part 9 (still open):
- [follow-up] File the upstream victorialogs issue (and ideally the patch: on tail-stream EOF, close responseChan or reconnect). Zero local cost; no issue exists upstream. We no longer depend on it, but every other user does.
- [follow-up] Hardening pass — re-harden the now-root pods (seccomp RuntimeDefault, readOnlyRootFilesystem, scoped capabilities), validating each against the chart root entrypoint. The explicit second step the human asked for.
- [follow-up] ADR — record the PSA decision for the crowdsec namespace (reverses a human-locked restricted PSA; the namespace now runs root + hostPath by design under explicit enforce: privileged).
- [follow-up] Add a crowdsec row to the [[pod-security-admission-enforcement]] per-namespace table (explicit privileged — agent DaemonSet needs hostPath /var/log).
- [follow-up] Deferred, still valid: no heartbeat Probe (would remove the alert traffic gate, but needs an in-cluster route to envoy-internal and a crowdsec allowlist for the pod CIDR — self-ban risk); no auto-heal watchdog (the stall class it healed is what this migration removes).

New, from step 3A:
- [follow-up] Acquisition glob over-matches — the chart renders <podName>_<namespace>_*.log, so the agent also tails the k8tz and shutdown-manager sidecar logs of the envoy pods and labels them program: envoy (6 files instead of 2). Empirically harmless (Part 8 notable: zero parser hits on the sidecar files — the envoy parser needs a JSON line), but it could be narrowed with additionalAcquisition. THE HUMAN EXPLICITLY DECIDED: record as a follow-up, do NOT implement it now.
- [resolved-follow-up] Confirm the new Prometheus job labels (crowdsec-service, crowdsec-agent-service, crowdsec-appsec-service) actually resolve against live targets before trusting the two alerts — DISCHARGED in Part 8 criterion 7 (Maestro port-forward to prometheus: all three job labels match the asserted ones, all up=1).
- [follow-up] Machine-list churn — agent and appsec register per pod name, so the LAPI machine list grows on every pod recreation. Part 8 notable confirmed the naming is pod-name-based (crowdsec-agent-n69l4 etc.); currently no stale entries, but a periodic `cscli machines prune` may be warranted once stale entries accumulate.
- [follow-up] Grafana dashboard 21689 was built for one job, not three — check its job/instance variables still resolve.
- [follow-up] Bouncer automountServiceAccountToken — the bouncer chart exposes no key for it (like the reloader annotation); consider a postRenderer patch for token-mount hygiene parity with the other three workloads.

## Next

This roadmap item is implemented; the Part 8 table above records what was proven and what was not. The remaining items are confirmations, not work — they can only happen at a future event or via a Maestro action:

- [awaiting-natural-event] Criterion 3 across an envoy pod recreation — at the next natural envoy recreation (Renovate envoy-gateway bump, node reboot, Talos upgrade), with envoy traffic flowing, watch the agent `cs_parser_hits_ok_total` acquire a new `source=` label (the new pod log path) and climb from 0 without a gap. The `poll_without_inotify: true` + fsnotify-on-literal-`/var/log/containers` design should pick up the new envoy pod log symlink automatically.
- [awaiting-natural-event] Criterion 3 across a victoria-logs-server replacement — the victorialogs datasource is gone, so this is now structurally a non-event; confirm at the next VL recreation that crowdsec acquisition is unaffected.
- [awaiting-maestro] Criterion 4 — a deliberate local trigger to produce an `origin="crowdsec"` decision (needs Maestro approval; adds a local ban).
- [awaiting-maestro] Criterion 5 OIDC live login — a browser login through idm.horvathzoltan.me → crowdsec web-ui (Maestro portal / live-product-verification lane).

No further code work is planned under this roadmap item. Remaining follow-ups (upstream victorialogs issue, hardening pass, ADR, PSA per-namespace table row, bouncer automountServiceAccountToken, Grafana dashboard 21689) are tracked in the roadmap Part 9 and in the follow-up list above.

## Relations

- relates_to [[crowdsec-psa-removal-and-official-chart-migration]]
- exception_to [[pod-security-admission-enforcement]]
- relates_to [[envoy-crowdsec-bouncer]]
- relates_to [[k8s-workloads]]
