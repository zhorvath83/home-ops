---
title: crowdsec-psa-removal-and-official-chart-migration
type: roadmap
permalink: home-ops/docs/progress/crowdsec-psa-removal-and-official-chart-migration
topic: Relax the crowdsec namespace PSA to an explicit privileged; migrate to the
  official crowdsecurity/crowdsec chart; replace the victorialogs tail with the file
  datasource on host container logs.
status: implemented
priority: high
scope: 'Replace the restricted PSA labels on the crowdsec namespace with an explicit
  enforce: privileged, migrate the CrowdSec workload from bjw-s app-template to the
  official crowdsecurity/crowdsec chart (LAPI + agent DaemonSet + AppSec), and replace
  the silently-stalling victorialogs tail acquisition with the chart-native file datasource
  on /var/log/containers.'
rationale: The crowdsec image was not designed for the restricted-PSA rootless posture
  the bjw-s chart was forced into, and the victorialogs tail datasource stops permanently
  and silently on every VictoriaLogs pod replacement (upstream readResponse treats
  stream EOF as success and never reopens). Relaxing PSA lets the official chart run
  the image as designed and unlocks the hostPath the file datasource needs.
related_areas:
- k8s-workloads
- networking
- observability
options:
- 'Explicit enforce: privileged + official chart + chart-native file datasource (chosen
  2026-07-30)'
- 'Bare removal of all PSA labels (rejected: relies on the implicit cluster default)'
- 'Keep the victorialogs tail plus a push pipeline via a Vector/Fluent-bit translator
  (rejected: one new component, zstd and no-per-sink-filter blockers)'
- 'Keep the tail plus an auto-heal watchdog (rejected: RBAC + moving part, treats
  the symptom)'
tags:
- crowdsec
- psa
- helm
- acquisition
- resilience
verified_at: '2026-07-30'
---

# CrowdSec: PSA relaxation, official chart migration, and acquisition resilience

Drop the `restricted` Pod Security Admission enforcement on the `crowdsec` namespace (down to an
explicit `privileged`), migrate the CrowdSec workload off the bjw-s `app-template` chart (which was bent
into a rootless posture the upstream image was not designed for) onto the official
`crowdsecurity/crowdsec` chart, and — in the same move — retire the silently-stalling victorialogs tail
acquisition for the chart-native `file` datasource on host container logs. The PSA relaxation is what
unlocks the acquisition fix; they are one change, not two.

This item absorbs the former `crowdsec-acquisition-resilience` roadmap (merged and deleted 2026-07-30)
and records a deliberate exception to the (now-dropped) pod-security-admission-enforcement roadmap for the `crowdsec` namespace.

## Metadata (observation-form, schema validation)

- [topic] Relax the crowdsec namespace PSA to privileged; migrate to the official crowdsecurity/crowdsec chart; replace the victorialogs tail with the file datasource on host container logs.
- [area] k8s-workloads, networking, observability
- [status] implemented — Part 8 verified live 2026-07-30. Execution and verification recorded in memory://home-ops/docs/progress/crowdsec-psa-removal-and-official-chart-migration. Two sub-criteria remain: an envoy-pod-recreation survival check (awaits a natural event) and a local-decision trigger + OIDC live login (await a Maestro action). Follow-ups closed 2026-07-31 (docs session): bouncer SA-token mount (6eb636118), hardening pass — seccomp RuntimeDefault + all caps dropped (522d66e9a + 2a8aef0e6; readOnlyRootFilesystem DECLINED, not deferred), Grafana dashboard 21689 removed (0ac6787d8; premise corrected — never a job-split problem), ADR AD-024 (since deleted) filed, and the crowdsec row added to the (now-dropped) pod-security-admission-enforcement roadmap. Closed 2026-07-31 (b): criterion 4 PASS (single ltsich/http-w00tw00t trigger from a mobile IP produced a local origin=crowdsec ban, enforced by the bouncer; decision deleted afterwards) and criterion 5 PASS (passkey login completed by the human). Machine-list churn closed (prune run) after fixing its true LAPI-side root cause: the postStart hook was clobbering the LAPI's own local_api_credentials.yaml because cscli machines add defaults to that path — fixed with -f /dev/null in e54c621aa, matching upstream docker_start.sh:217, and the PVC file repaired. The upstream victorialogs issue was DROPPED by human decision (not filed; analysis kept below for provenance). Closed 2026-07-31 (c): criterion 3's envoy-pod-recreation arm PASS (deliberate envoy-internal restart; the agent picked up the new log path and resumed parsing from 0 with no errors), so ALL Part 8 criteria now PASS. The two deferred items are DECLINED with evidence, not left open: the heartbeat Probe (the 6h gate is open 95.7% of the last 30d, and in the real incident it was open throughout — the Probe would have added nothing) and the auto-heal watchdog (its stall class is retired, the replacement datasource survived the exact triggering event, and the alert demonstrably fires). The CrowdSecAcquisitionStalled rule was back-tested against the 2026-07-29 incident: it would have fired ~4h10m after onset, 4h before the manual restart. The analysis below is the original proposed spec, kept as history.
- [priority] high
- [confidence] high
- [verified_at] 2026-07-30

## Part 1 — the problem being eliminated

### The incident (2026-07-29/30)

- [observation] `cs_parser_hits_ok_total{acquis_type="envoy"}` froze at 1912 from 2026-07-29 23:24 CEST
  until a manual restart at 07:41 — **8.2 hours** with no envoy log parsing.
- [observation] Trigger: `victoria-logs-server-0` was **recreated** at 23:21 (image v1.52.0; `restartCount`
  stayed 0, so a pod replacement, not a container restart).
- [observation] The crowdsec pod stayed `1/1 Running`, 0 restarts, and emitted **not one log line** about
  the loss. 20h of logs grepped for `victorialog|acquis|tail|EOF|error|warn` returned nothing.
- [observation] Enforcement was unaffected (bouncer served 10 062 extAuth calls, AppSec inspected 8 091
  requests), but every one of the 60 533 active bans came from `origin="CAPI"`/`origin="lists"` —
  `origin="crowdsec"` (local decisions) was absent. Degraded defence, not dead.

### Root cause — upstream bug, unfixed in v1.7.8 and in master

- [evidence] `pkg/acquisition/modules/victorialogs/internal/vlclient/vl_client.go:204-207` (`readResponse`):
  the tail stream's `io.EOF` is treated as normal completion (`finishedReading = true`), so it returns
  `(n, latestTS, nil)` — no error, and `responseChan` is never closed (`close(c)` exists only in
  `doQueryRange`, line 156).
- [evidence] `pkg/acquisition/modules/victorialogs/run.go:109-117` (`StreamingAcquisition`): the consumer
  selects on `resp, ok := <-respChan`. With the channel neither closed nor written again the goroutine
  **blocks forever**; the `"VictoriaLogs channel closed"` warning branch is structurally unreachable.
- [evidence] `max_failure_duration`/`shouldRetry()` guard only connection *establishment*, never stream loss.
- [evidence] `vl_client.go` and `run.go` are byte-identical between v1.7.8 and master (verified by diff);
  a search over 94 victorialogs-related issues found no existing report. `config.go` exposes only `tail`
  and `cat` modes, so there is **no config-level workaround**.
- [observation] This recurs on **every** VictoriaLogs pod replacement: Renovate bumps, node reboots,
  Talos upgrades, evictions.

### Why the alert lied — and the fix that already landed

The old rule gated on `increase(envoy_..._rq_total[1h]) > 0`. Measured over 7d at 5m resolution that gate
is closed 21–39% of the time (envoy traffic here is low and bursty), so the single continuous 8.2h stall
was reported as **two** fire/resolve cycles — the alert was structurally incapable of staying firing.

| window | gate closed | longest blind run | behaviour during the real stall |
|---|---|---|---|
| 2h | 21.0% | 6.9h | 2 episodes (flaps) |
| 4h | 7.1% | 4.9h | 1 episode, 4.2h |
| 6h | 3.5% | 2.9h | 1 episode, 2.2h |
| 12h | 0.0% | 0.0h | **never — misses an 8h stall entirely** |

- [decision] Landed 2026-07-30: symmetric **6h** windows plus **`keep_firing_for: 3h`** (covers the measured
  2.9h longest blind run), `for: 10m` unchanged. This is **detection only — it does not stop the stall.**

### Why the other exits are dead ends (research verdicts, keep for the record)

- [evidence] **Push pipeline into crowdsec's `http` source does not work.** vlagent hardcodes
  `Content-Encoding: zstd` (`app/vlagent/remotewrite/client.go:315`, `pendinglogrows.go:147`) with no
  disable flag; crowdsec's `http` source decodes gzip only (`pkg/acquisition/modules/http/run.go:76`)
  and answers 400 to everything else. vlagent also has no per-sink filter (only the global
  `-kubernetesCollector.excludeFilter`), so a second sink would fire every cluster pod log at crowdsec.
  A translator component (Vector/Fluent-bit) would be required.
- [evidence] **Envoy as the direct producer is a dead end.** Envoy Gateway 1.8.3 access-log sinks are
  `File` | `ALS` (gRPC) | `OpenTelemetry`; CrowdSec v1.7.8 ships no ALS/gRPC/OTLP datasource.
- [evidence] vlagent discards the raw line (`processor.go:226-250` forwards only `parser.Fields`, and
  `RenameField(..., {"message","msg","log"}, "_msg")` finds no match in an envoy access log) — this is
  where the "missing _msg" placeholder that forced the `copy`+`pack_json` hack originates.

**Conclusion:** the `file` datasource on host container logs is the only translator-free exit, and it needs
hostPath — which is what ties this to the PSA relaxation.

## Part 2 — decisions (locked with the human, 2026-07-30)

- [decision] **PSA: explicit `privileged`.** Replace the six `pod-security.kubernetes.io/*` labels in
  `kubernetes/apps/crowdsec/namespace.yaml` with a single `pod-security.kubernetes.io/enforce: privileged`.
  No `enforce-version` (the privileged profile has no checks to version), and no `warn`/`audit` — the
  namespace is knowingly root + hostPath, so those would only emit noise on every deploy.
- [decision] Chosen **over bare label removal**, which was the first draft's plan. Both work, but bare
  removal leans on an implicit cluster default; the explicit label states the exception in Git and
  survives any future change to that default.
- [evidence] Bare removal *would* have worked: this cluster's effective default for an unlabeled
  namespace is `privileged`. Verified by server-side dry-run — a pod with `hostPID: true`,
  `privileged: true` and a `hostPath` volume was accepted in the unlabeled `default` namespace with no
  warnings. Corroborated by the live `observability` namespace (no PSA labels), which runs
  `victoria-logs-collector` (hostPath `/var/log`, `/var/lib`) and node-exporter (hostPath `/`).
  The Talos machine config sets no `admissionControl` PodSecurity defaults (`machineconfig.yaml.j2:114-130`
  has only `disablePodSecurityPolicy: true`). Recorded because it also means the crowdsec namespace is
  currently the **only** namespace in the repo carrying PSA labels at all.
- [decision] **Acquisition: chart-native `file` datasource** on `/var/log/containers`. The victorialogs
  tail and its `copy`+`pack_json` reconstruction hack are deleted; the upstream bug becomes irrelevant.
- [decision] **Hardening: first pass with NO additional hardening.** Strip the rootless-era
  securityContext; let chart defaults apply (`allowPrivilegeEscalation: false`, `privileged: false`) and
  the pods run as root with default caps and a writable rootfs. Re-hardening is a separate follow-up.

## Part 3 — verified facts about the target chart

Chart pulled and read at `oci://ghcr.io/crowdsecurity/helm-charts/crowdsec` **0.24.0**
(digest `sha256:a2c4fbf4f4692d9fca09d51d102c7e417fbe93b609356c4777f9cc31cb202458`, appVersion **v1.7.8** —
same version we run today).

- [evidence] The chart splits the single pod into three workloads:

| Workload | Toggle | Kind | Pod labels | Service | Ports |
|---|---|---|---|---|---|
| LAPI | `lapi.enabled` | Deployment `crowdsec-lapi` | `k8s-app=crowdsec, type=lapi, version=v1` | `crowdsec-service` | 8080 lapi, 6060 metrics |
| Agent | `agent.enabled`, `isDeployment: false` | DaemonSet `crowdsec-agent` | `k8s-app=crowdsec, type=agent, version=v1` | `crowdsec-agent-service` | 6060 metrics |
| AppSec | `appsec.enabled` | Deployment `crowdsec-appsec` | `k8s-app=crowdsec, type=appsec, version=v1` | `crowdsec-appsec-service` | 7422 appsec, 6060 metrics |

- [evidence] The chart sets **no** `app.kubernetes.io/*` labels — the existing CNP selector
  (`app.kubernetes.io/name: crowdsec`) matches nothing after the migration and must be rewritten.
- [evidence] `podLabels` (global) **wins over** `<component>.podLabels` — the templates use
  `if .Values.podLabels ... else if .Values.<c>.podLabels`. Set the prometheus label once, globally.
- [evidence] `env` is an **array** of `{name, value}` on all three components (not a map, unlike bjw-s).
  Only `lapi` supports `envFrom`.
- [evidence] LAPI runs the **chart's own** `/docker_start.sh` (ConfigMap `crowdsec-docker-start-script-configmap`
  from `files/docker-start-custom.sh`), which is the image entrypoint with all agent-side config removed.
  It handles `USE_WAL`, `ENROLL_KEY`/`ENROLL_INSTANCE_NAME`, `ENABLE_CONSOLE_MANAGEMENT` and the
  `BOUNCER_KEY_*` registration loop — but **not** `COLLECTIONS`/`PARSERS` and **not**
  `AGENT_USERNAME`/`AGENT_PASSWORD`. Agent and AppSec run the **image's** `./docker_start.sh`, which does
  handle `COLLECTIONS`/`PARSERS`/`POSTOVERFLOWS`/`APPSEC_CONFIGS`.
- [evidence] `secrets.username` / `secrets.password` are **dead values** — referenced by no template. There
  is no chart path that registers the web-ui machine.
- [evidence] With `lapi.persistentVolume.config.enabled: true`, `StoreCAPICredentialsInSecret` and
  `StoreLAPICscliCredentialsInSecret` both resolve false → **no register Jobs, no Role/RoleBinding/SA, and
  no `alpine/kubectl:latest` (mutable-tag) image is pulled.** Keep the config PVC enabled for this reason.
- [evidence] LAPI command with the config PVC:
  `cp -nR /staging/etc/crowdsec/* /etc/crowdsec_data/ && ln -s /etc/crowdsec_data /etc/crowdsec && bash /docker_start.sh`.
  The data PVC mounts at `/var/lib/crowdsec/data` with `subPath: crowdsec`.
- [evidence] Agent and AppSec register through an init container:
  `cscli lapi register --machine "$USERNAME" -u "$LAPI_URL" --token "$REGISTRATION_TOKEN"` where
  `USERNAME` = **pod name** — so every pod recreation adds a machine to the LAPI machine list.
- [evidence] The LAPI's own `CUSTOM_HOSTNAME` is also the pod name, but with the persistent config PVC the
  entrypoint finds the stored `local_api_credentials.yaml` and re-registers **that** login instead of
  creating a new machine — so LAPI itself does not churn.
- [evidence] `container_runtime: containerd` is required (default is `docker`, which adds a
  `/var/lib/docker/containers` hostPath the Talos node does not have) and it is also what the acquisition
  `labels.type` is set from — see Part 4.
- [evidence] `agent.hostVarLog: true` (default) mounts hostPath `/var/log` read-only. The agent runs as root,
  so no `supplementalGroups: [0]` is needed (host container logs are 0640 root:root — the trick
  `victoria-logs-collector` needs only because it is rootless).
- [evidence] The chart exposes **neither** `automountServiceAccountToken` **nor** `enableServiceLinks` —
  a token-hygiene regression against the repo baseline. See Part 5.

## Part 4 — the acquisition, corrected

This is where the first draft of this plan was wrong. The parse path is the whole point, so it is
spelled out with its evidence.

- [evidence] `yanis-kouidri/envoy-logs` filters on **`evt.Parsed.program == 'envoy'`** (hub source), and its
  JSON branch requires `TrimSpace(evt.Parsed.message) startsWith "{"`.
- [evidence] `crowdsecurity/cri-logs` (s00-raw) filters on **`evt.Line.Labels.type == 'containerd'`**, groks
  the containerd `<ts> stdout F <line>` prefix off `Line.Raw` into `evt.Parsed.message`, and sets
  `program` from `evt.Line.Labels.program`.
- [evidence] The chart's `acquis-configmap` renders each `agent.acquisition` entry as
  `filenames: [/var/log/containers/<podName>_<namespace>_*.log]`, `force_inotify: true`,
  `labels: {type: <container_runtime>, program: <program>}`.
- [decision] **Use the chart-native `agent.acquisition`, not `additionalAcquisition` with `labels.type: envoy`.**
  With `labels.type: envoy` (the first draft's proposal) `cri-logs` never fires, the CRI prefix stays on the
  line, `message` does not start with `{`, and **nothing parses at all**. The correct chain is
  `cri-logs` (type=containerd) → `envoy-logs` (program=envoy) → `http-logs` → enrichment.
- [decision] **Split the pod glob.** `envoy-*` would also match `envoy-gateway-*` — the controller pod,
  live in the `networking` namespace — feeding controller logs into the parser. Use two entries,
  `envoy-external-*` and `envoy-internal-*`.
- [decision] **`poll_without_inotify: true` is mandatory.** `/var/log/containers/*.log` are symlinks, and
  crowdsec warns on exactly this (`pkg/acquisition/modules/file/run.go:255-262` v1.7.8): *"File %s is a
  symlink, but inotify polling is enabled. Crowdsec will not be able to detect rotation."* With inotify
  the watch binds the rotated-away inode; kubelet log rotation would then produce **the same class of
  silent stall we are migrating away from**. Polling re-stats the path, re-resolves the symlink and
  reopens.
- [evidence] **Why pod recreation is survived:** `Configure()` (`file/config.go:95-108`) adds an fsnotify
  watch on `filepath.Dir(pattern)` when `force_inotify` is set — here the literal, stable directory
  `/var/log/containers` — and `monitorNewFiles()` (`file/run.go:128-170`) tails any newly created file
  matching the glob. A new envoy pod creates a new symlink there and is picked up automatically.
  **Corollary:** the glob's parent directory must be literal. `/var/log/pods/networking_envoy-*/envoy/*.log`
  would break discovery (`watcher.Add` on a non-existent globbed dir fails).
- [decision] **Rename four envoy JSON fields** in both access-log blocks of
  `kubernetes/apps/networking/envoy-gateway/config/envoy.yaml`:
  `path`→`x-envoy-origin-path`, `authority`→`:authority`, `x_forwarded_for`→`x-forwarded-for`,
  `user_agent`→`user-agent`. Verified against a live log line: `start_time`, `method`,
  `response_code` and `downstream_remote_address` already match what the parser reads; those four do not.
  The only consumer of the current names in the repo is the acquis hack itself, so this is cosmetic for
  victoria-logs.
- [decision] **Drop `crowdsecurity/syslog-logs`.** It was needed only for the victorialogs source (its
  `non-syslog` s00-raw node filled `evt.Parsed.message`). It is not a dependency of
  `yanis-kouidri/envoy` → `base-http-scenarios` (verified). Worse, its `non-syslog` node
  (`filter: type not in ['syslog','unifi']`) **also matches `containerd`**, and its statics would overwrite
  `program` and `message`; the outcome would depend on s00-raw node evaluation order. Remove it rather
  than depend on ordering.
- [decision] **Declare `crowdsecurity/cri-logs` explicitly in `PARSERS`.** It is present today
  (`cscli parsers list` on the live pod) as an **image default**, not as a dependency of anything we
  install — and the entire parse path now rests on it. Declaring it is idempotent and self-documenting.
- [evidence] The AppSec pod needs no `APPSEC_CONFIGS` env: `crowdsecurity/appsec-virtual-patching` already
  lists `crowdsecurity/appsec-default` under its `appsec-configs` (hub source).
- [note] The agent has no data PVC, so `geoip-enrich` re-downloads the GeoLite2 mmdb from
  `hub-data.crowdsec.net` on **every** agent pod start. That is a startup cost and a hard egress
  requirement (Part 5, CNP).

**Resulting values (agent side):**

```yaml
agent:
  acquisition:
    - namespace: networking
      podName: envoy-external-*
      program: envoy
      poll_without_inotify: true
    - namespace: networking
      podName: envoy-internal-*
      program: envoy
      poll_without_inotify: true
```

## Part 5 — file-by-file change plan

### `kubernetes/apps/crowdsec/namespace.yaml`
- Replace the six `pod-security.kubernetes.io/*` labels with the single
  `pod-security.kubernetes.io/enforce: privileged`. Keep the `kustomize.toolkit.fluxcd.io/prune: disabled`
  annotation. Replace the now-false "restricted-clean by construction" comment with a one-liner naming
  the reason (the agent DaemonSet needs hostPath `/var/log`).

### `.../crowdsec/app/ocirepository.yaml` (NEW)
- OCIRepository for `oci://ghcr.io/crowdsecurity/helm-charts/crowdsec`, tag `0.24.0`, same shape as
  `bouncer/app/ocirepository.yaml` (layerSelector + `# renovate: registryUrl=https://ghcr.io/crowdsecurity/helm-charts chart=crowdsec`).

### `.../crowdsec/app/helmrelease.yaml` (REWRITE)
- `image.repository: crowdsecurity/crowdsec`, `image.tag: v1.7.8@sha256:…` (tag+digest is a valid
  reference for the chart's `{{ repo }}:{{ tag }}` interpolation); keep the renovate annotation.
- `container_runtime: containerd`.
- `podLabels.ingress.home.arpa/allow-prometheus: "true"` — **global**, covers all three pods.
- `config.config.yaml.local`: the chart's `auto_registration` block **merged with** our
  `api.server.trusted_ips` (127.0.0.1, ::1, 10.0.0.0/8, `${LAN_SUBNET}` — Flux substitutes this one).
- `config.profiles.yaml`: the two `duration_expr` remediation profiles verbatim (LAPI-only mount).
- `lapi`: `persistentVolume.config` (1Gi) + `persistentVolume.data` (2Gi) on
  `democratic-csi-local-hostpath`; `deployAnnotations.reloader.stakater.com/auto: "true"`;
  `metrics.serviceMonitor.enabled: true`; `env` (`USE_WAL`, `ENABLE_CONSOLE_MANAGEMENT`,
  `ENROLL_INSTANCE_NAME: home-ops`); `envFrom` the `crowdsec-secret`; `lifecycle.postStart` for the
  web-ui machine (Open tasks); LAPI-sized resources.
- `agent`: `isDeployment: false`; `hostVarLog: true`; the two `acquisition` entries above;
  `env` (`COLLECTIONS: yanis-kouidri/envoy`, `PARSERS: crowdsecurity/cri-logs crowdsecurity/dateparse-enrich crowdsecurity/geoip-enrich crowdsecurity/whitelists`,
  `POSTOVERFLOWS: crowdsecurity/ipv6_to_range`); `metrics.serviceMonitor.enabled: true`.
- `appsec`: `acquisitions` (`source: appsec`, `listen_addr: 0.0.0.0:7422`, `path: /`,
  `appsec_config: crowdsecurity/appsec-default`, `labels.type: appsec`);
  `env.COLLECTIONS: crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules`;
  `metrics.serviceMonitor.enabled: true`.
- `postRenderers` (the repo's sanctioned exception to the HelmRelease minimal-spec policy, precedent:
  `onepassword-connect`): kustomize patches setting `automountServiceAccountToken: false` and
  `enableServiceLinks: false` on `crowdsec-lapi`/`crowdsec-appsec` (Deployment) and `crowdsec-agent`
  (DaemonSet) — none of the three touches the K8s API.
- Drop: bjw-s `controllers`/`defaultPodOptions`/`persistence`/`service`/`serviceMonitor`, the rootless
  securityContext, the `rsync`+symlink-cleanup command hack, the `varlog`/`tmp` emptyDirs, the custom probes.

- [decision] **The chart's registration-token placeholder must be escaped for Flux.** Write it as
  `$${REGISTRATION_TOKEN}` — a doubled dollar sign — inside the HelmRelease values. The
  cluster-root Kustomization patches **every** child Kustomization with
  `postBuild.substituteFrom: cluster-settings` (`kubernetes/flux/cluster/ks.yaml:63-69`) — verified live
  (the `LAN_SUBNET` placeholder in today's `crowdsec-config-local` ConfigMap renders as `192.168.1.0/24`).
  Unescaped, Flux would substitute the registration token to **empty** before crowdsec ever sees it,
  silently killing agent and AppSec registration. The doubled form renders back to a literal placeholder
  that crowdsec's own env expansion then resolves.

### `.../crowdsec/app/kustomization.yaml`
- Add `./ocirepository.yaml`; remove the three `configMapGenerator` entries.

### `.../crowdsec/app/{acquis.yaml,config.yaml.local,profiles.yaml}` (DELETE)
- Content moves inline into the HelmRelease values (chart-native). Keeping the files and using Flux
  `valuesFrom` is possible but adds indirection for no gain — recommend inline.

### `.../crowdsec/app/ciliumnetworkpolicy.yaml` (REWRITE — four documents)
- `crowdsec`: selector `k8s-app: crowdsec` (all three pods), **egress only** — the existing
  `crowdsec.net` / `papi.api.crowdsec.net` / `blocklists.api.crowdsec.net` / `*.crowdsec.net` FQDN
  block on 443. **All three** pods need it now: LAPI for CAPI/PAPI/console, agent and AppSec for hub
  downloads on every start (including the GeoLite2 mmdb).
- `crowdsec-lapi`: selector `k8s-app: crowdsec, type: lapi`, ingress — bouncer→8080, web-ui→8080+6060,
  **and `k8s-app: crowdsec`→8080** for the agent's and AppSec's registration and streaming. Omitting
  that last rule breaks the whole engine; it did not exist before because everything lived in one pod.
- `crowdsec-agent`: selector `k8s-app: crowdsec, type: agent`, ingress — web-ui→6060 (see the web-ui
  metrics decision below). Without this document the agent has no CNP of its own, but the clusterwide
  `ingress-from-prometheus` CCNP still selects it (via the global pod label) and therefore flips its
  ingress to default-deny — the web-ui scrape would be dropped.
- `crowdsec-appsec`: selector `k8s-app: crowdsec, type: appsec`, ingress — bouncer→7422, web-ui→6060.
- Prometheus ingress to all three arrives via the clusterwide `ingress-from-prometheus` CCNP through the
  global pod label; cluster-internal egress stays on the `allow-cluster-egress` CCNP baseline (crowdsec
  carries no `egress.home.arpa/custom-egress` opt-out label).

### `.../crowdsec/app/externalsecret.yaml` (UNCHANGED)
- `BOUNCER_KEY_envoy` (chart's LAPI script keeps the `BOUNCER_KEY_*` loop), `AGENT_PASSWORD` (now
  consumed by the postStart hook instead of the entrypoint) and `ENROLL_KEY` all stay in use.

### `.../crowdsec/app/prometheusrule.yaml` (UPDATE — both rules)
- `CrowdSecLAPIDown`: `up{job="crowdsec-service", namespace="crowdsec"}`.
- `CrowdSecAcquisitionStalled`: the counter now comes from the **agent** and its labels change.
  Verified live today: `cs_parser_hits_ok_total{acquis_type="envoy", source="http://victoria-logs-server…:9428", type="victorialogs"}`
  — `acquis_type` is the acquisition's `labels.type`, so it becomes **`containerd`**, `type` becomes
  `file`, and `source` becomes the log file path. New selector:
  `cs_parser_hits_ok_total{job="crowdsec-agent-service", namespace="crowdsec", acquis_type="containerd", source=~"/var/log/containers/envoy-.*"}`.
  (`source` churns on every envoy pod recreation — fine under `sum(increase(...))`.)
- Rewrite the description: the cause is no longer the victorialogs tail. The 6h + `keep_firing_for` shape
  stays valid — traffic-gate blindness is a property of low envoy traffic, not of the datasource.
- [note] The `job` label is the **Service** name (prometheus-operator default when `jobLabel` is unset;
  consistent with today's `job="crowdsec"`/`job="crowdsec-bouncer"`). Confirm against live targets after
  cutover before trusting the alerts.

### `.../bouncer/app/helmrelease.yaml` (UPDATE cross-refs)
- `config.bouncer.lapiURL` → `http://crowdsec-service.crowdsec.svc.cluster.local:8080`.
- `config.waf.appSecURL` → `http://crowdsec-appsec-service.crowdsec.svc.cluster.local:7422`.

### `.../web-ui/app/helmrelease.yaml` (UPDATE cross-refs + metrics fan-out)
- `CONFIG_INSTANCE_LAPI_URL` → `http://crowdsec-service.crowdsec.svc.cluster.local:8080`.
- [decision] **Register all three metrics endpoints, not one.** Splitting the pod splits the `:6060`
  surface: the LAPI process exposes API/decision/machine/bouncer counters, the agent process exposes the
  acquisition/parser/bucket counters, the AppSec process its own. A single URL would therefore show a
  partial picture in the web-ui's Metrics page.
- [evidence] The web-ui accepts **zero or more** metrics endpoints per instance
  (`instances[].metrics[]`, env form `CONFIG_INSTANCES_<INDEX>_METRICS_<METRIC_INDEX>_*`) — verified in
  the README at the deployed tag `2026.7.24`, not just on `main`. So nothing is lost; this is a config
  change, not a tradeoff.
- Replace `CONFIG_INSTANCE_METRICS_URL` with the indexed form (the README states the shorthand and the
  indexed form are equivalent and must not be set together):
  `CONFIG_INSTANCES_0_METRICS_0_URL` = `http://crowdsec-service.crowdsec.svc.cluster.local:6060/metrics`,
  `_1_URL` = `http://crowdsec-agent-service…:6060/metrics`,
  `_2_URL` = `http://crowdsec-appsec-service…:6060/metrics`, each with a matching
  `_NAME` (`LAPI` / `Agent` / `AppSec`) so the UI selector is readable.
- This is what makes the `crowdsec-agent` and `crowdsec-appsec` CNP ingress rules above necessary.

### `kubernetes/apps/networking/envoy-gateway/config/envoy.yaml` (RENAME fields)
- The four renames in **both** the envoy-external and envoy-internal access-log JSON blocks
  (lines ~50-62 and ~127-139). Afterwards verify both proxies reload the format and still emit logs.

## Part 6 — cutover sequence (the migration is not a plain HelmRelease edit)

- [evidence] **ConfigMap ownership collision.** The chart creates ConfigMaps named **`crowdsec-profiles`**
  and **`crowdsec-config-local`** — byte-identical names to the ones our `configMapGenerator` owns today.
  Helm refuses to adopt resources it does not own ("invalid ownership metadata"), so an in-place
  HelmRelease swap can deadlock on them.
- [evidence] **PVCs.** The chart creates `crowdsec-config-pvc` / `crowdsec-db-pvc`; the current release owns
  `crowdsec-config` / `crowdsec-data`. No name collision, but `democratic-csi-local-hostpath` has
  `reclaimPolicy: Delete`, so uninstalling the old release **destroys the old LAPI database**.
  That is intended (fresh state, no rootless-era leftovers), and the cost is bounded: CAPI/list
  decisions re-stream, the bouncer re-registers from `BOUNCER_KEY_envoy`, console re-enroll is a no-op —
  only locally-generated decisions are lost. **There is no rollback to the old DB.**

Order:
1. Commit the envoy field renames first, and confirm envoy still logs (independent, reversible).
2. Commit the crowdsec app rewrite in one commit: namespace label, kustomization (generators removed),
   the three deleted config files, new ocirepository, new helmrelease, new CNP, updated PrometheusRule.
3. Let Flux prune the old ConfigMaps/HelmRelease before the new release installs — verify
   `crowdsec-profiles` and `crowdsec-config-local` are gone (or deleted by hand) **before** the new
   HelmRelease reconciles; otherwise the install fails on ownership.
4. Update the bouncer and web-ui references (they fail closed while LAPI is down anyway).
5. Walk the verification criteria.

## Part 7 — open tasks

- [task] **Web-ui LAPI machine registration.** The chart's LAPI script ignores `AGENT_USERNAME`/
  `AGENT_PASSWORD` (verified). Plan: `lapi.lifecycle.postStart.exec` running
  `cscli machines add crowdsec-web-ui -p "$AGENT_PASSWORD" --force` in a retry loop (postStart races the
  entrypoint; `cscli` needs `/etc/crowdsec` seeded). Fallback: a one-shot Job. Validate the web-ui logs in.
- [task] **Confirm the `config.yaml.local` merge** renders our `trusted_ips` *alongside* the chart's
  `auto_registration` block, and that the escaped registration-token placeholder survives Flux
  substitution while `LAN_SUBNET` is substituted.
- [task] **Machine-list churn.** Agent/AppSec register per pod name; check the machine list after a few
  restarts and decide whether a periodic `cscli machines prune` is warranted.
- [task] **Grafana dashboard 21689** is an upstream grafana.com dashboard; check its job/instance
  variables still resolve with three jobs instead of one.

## Part 8 — verification criteria

- [criterion] `crowdsec-lapi`, `crowdsec-agent` (DaemonSet) and `crowdsec-appsec` Running, 0 restarts; the
  namespace carries exactly one PSA label (`enforce: privileged`) and no PodSecurity admission events.
- [criterion] `cscli metrics` on the agent shows the two `/var/log/containers/envoy-*` files as acquisition
  sources with non-zero reads, and the parser chain `cri-logs`→`envoy-logs`→`http-logs` shows hits (not
  just reads) — a real envoy log line parsed end to end.
- [criterion] **The root criterion:** `cs_parser_hits_ok_total{acquis_type="containerd", source=~"/var/log/containers/envoy-.*"}`
  climbs continuously **across an envoy pod recreation** — the acquisition survives by construction, not
  by alert. Also verify across a `victoria-logs-server` replacement (must now be a non-event).
- [criterion] `cs_active_decisions` shows an `origin="crowdsec"` series after a deliberate local trigger.
- [criterion] Bouncer extAuth + AppSec still serve; web-ui logs in (OIDC + LAPI machine registered).
- [criterion] The web-ui Metrics page lists all three endpoints (LAPI / Agent / AppSec) and each returns
  data — proving both the indexed config and the new agent/appsec CNP ingress rules.
- [criterion] Prometheus scrapes all three ServiceMonitors; `CrowdSecLAPIDown` and
  `CrowdSecAcquisitionStalled` fire/resolve correctly with the new job labels.
- [criterion] envoy-external/-internal still emit JSON access logs with the renamed fields and
  victoria-logs still ingests them.
- [criterion] No API token mounted in the three crowdsec pods (postRenderer applied).

## Part 9 — follow-up

- [follow-up] **File the upstream victorialogs issue** (and ideally the patch: on tail-stream EOF either
  close `responseChan` or reconnect). Zero local cost, and no issue exists. We no longer depend on it,
  but every other user does.
- [follow-up] **Hardening pass** — re-harden the now-root pods (seccomp `RuntimeDefault`,
  `readOnlyRootFilesystem`, scoped capabilities), validating each against the chart's root entrypoint.
  The explicit second step the human asked for.
- [follow-up] **ADR** — record the PSA decision for the `crowdsec` namespace: it reverses a human-locked
  `restricted` PSA, and the namespace now runs root + hostPath by design under an explicit
  `enforce: privileged`.
- [follow-up] **Deferred, still valid:** no heartbeat `Probe` (would remove the alert's traffic gate, but
  needs an in-cluster route to envoy-internal and a crowdsec allowlist for the pod CIDR — self-ban risk,
  see [[envoy-crowdsec-bouncer]] Session 4); no auto-heal watchdog (a CronJob needs `delete pods` RBAC
  and the stall class it healed is what this migration removes).

## Relations

- relates_to [[envoy-crowdsec-bouncer]]
- relates_to [[cr-health-alerting]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- relates_to [[observability]]
- relates_to [[iam]]
