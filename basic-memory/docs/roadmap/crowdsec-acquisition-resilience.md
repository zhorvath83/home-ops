---
title: crowdsec-acquisition-resilience
type: roadmap
permalink: home-ops/docs/roadmap/crowdsec-acquisition-resilience
topic: Make CrowdSec's envoy log acquisition survive a VictoriaLogs restart — migrate
  off the silently-stalling victorialogs tail datasource
status: proposed
priority: high
scope: Replace or backstop the CrowdSec victorialogs tail acquisition, which stops
  permanently and silently whenever the victoria-logs-server pod is replaced. Decide
  between an upstream fix, a push-based pipeline with one new translator component,
  or the file datasource on host container logs — the last of which requires dropping
  the crowdsec namespace from restricted PSA to privileged.
rationale: On 2026-07-29 the acquisition died silently for 8.2h after a routine victoria-logs-server
  image bump. The pod stayed 1/1 Ready with zero log output, and the only safety net
  (a PrometheusRule) false-resolved mid-incident. Local envoy-based scenario detection
  was gone the whole time while the pod reported healthy. This will recur on every
  VictoriaLogs pod replacement — Renovate bumps, node reboots, Talos upgrades, evictions.
related_areas:
- networking
- observability
options:
- Upstream fix in crowdsec (smallest, removes the bug for everyone) — do this first
  regardless
- Push pipeline via a translator component (keeps restricted PSA, costs one component)
- The file datasource on host container logs (simplest, but costs privileged PSA)
- Keep the tail plus an auto-heal watchdog (no architecture change, adds RBAC and
  a moving part)
---

# CrowdSec acquisition resilience — get off the silently-stalling victorialogs tail

## Metadata (observation-form, schema validation)

- [topic] Make CrowdSec's envoy log acquisition survive a VictoriaLogs restart
- [area] networking
- [status] proposed
- [priority] high
- [confidence] high
- [verified_at] 2026-07-30

## The incident (2026-07-30)

- [observation] `cs_parser_hits_ok_total{acquis_type="envoy"}` froze at 1912 from
  2026-07-29 23:24 CEST until a manual restart at 2026-07-30 07:41 — **8.2 hours** of no
  envoy log parsing.
- [observation] Trigger: `victoria-logs-server-0` was **recreated** at 23:21 CEST
  (image v1.52.0, a new pod — `restartCount` stayed 0, so this was a pod replacement, not a
  container restart).
- [observation] The crowdsec pod stayed `1/1 Running`, 0 restarts, and emitted **not one log
  line** about the loss. Grepping 20h of logs for `victorialog|acquis|tail|EOF|error|warn`
  returned nothing.
- [observation] Enforcement was unaffected: the bouncer served 10 062 extAuth calls, AppSec
  inspected 8 091 requests, and the LAPI answered `/v1/decisions/stream` every 10s. 60 533
  bans stayed active — but **all** from `origin="CAPI"` and `origin="lists"`, with
  `origin="crowdsec"` (local decisions) absent. Degraded defence, not dead.

## Root cause — upstream bug, unfixed in v1.7.8 and in master

- [evidence] `pkg/acquisition/modules/victorialogs/internal/vlclient/vl_client.go:204-207`
  (`readResponse`): the tail stream's `io.EOF` is treated as normal completion —
  `finishedReading = true` — so the function returns `(n, latestTS, nil)`. **No error, and
  `responseChan` is never closed** (`close(c)` exists only in `doQueryRange`, line 156).
- [evidence] `pkg/acquisition/modules/victorialogs/run.go:109-117`
  (`StreamingAcquisition`): the consumer selects on `resp, ok := <-respChan`. Since the
  channel is neither closed nor written to again, the goroutine **blocks forever**. The
  `s.logger.Warnf("VictoriaLogs channel closed")` branch is structurally unreachable.
- [evidence] `max_failure_duration` / `shouldRetry()` do not help — they guard only
  connection *establishment* (`Tail()`, `Get()`), never stream loss.
- [evidence] `vl_client.go` and `run.go` are **byte-identical between tag v1.7.8 and
  master** (verified by diff) — upstream has not fixed this. A GitHub issue search over 94
  victorialogs-related issues found no existing report.
- [evidence] `config.go` exposes only `tail` (streaming) and `cat` (one-shot) modes, so
  there is **no config-level workaround**.

## Why the alert lied — and what was changed

The old rule gated on `increase(envoy_..._rq_total[1h]) > 0`. Measured over 7 days at 5m
resolution, that gate is **closed 21–39% of the time** on this cluster (envoy traffic is low
and bursty: envoy-external had 58 requests total since pod start).

- [observation] The single continuous 8.2h stall was reported as **two** fire/resolve cycles.
  The `RESOLVED` at 03:53 matches the end of the first true window (03:44 + Alertmanager
  resolve delay) exactly; it re-fired at 06:20. The alert was structurally incapable of
  staying firing.

Window sweep against the real incident (0 false positives at **every** width — with symmetric
windows a false positive is structurally impossible, since a healthy crowdsec parses every
envoy request that the gate counts):

| window | gate closed | longest blind run | firing during the real stall |
|---|---|---|---|
| 2h | 21.0% | 6.9h | 2 episodes (flaps) |
| 3h | 12.0% | 5.9h | 2 episodes (flaps) |
| 4h | 7.1% | 4.9h | 1 episode, 4.2h |
| 6h | 3.5% | 2.9h | 1 episode, 2.2h |
| 8h | 1.1% | 0.9h | 1 episode, 0.2h (barely) |
| 12h | 0.0% | 0.0h | **never — misses an 8h stall entirely** |

- [decision] Landed 2026-07-30: symmetric **6h** windows plus **`keep_firing_for: 3h`**
  (covers the measured 2.9h longest blind run, so a quiet stretch can no longer look like a
  self-heal). `for: 10m` unchanged. The description now names the real cause and the real
  remediation (restart the deployment) instead of the original wrong guess (re-check the
  LogsQL query).
- [observation] `keep_firing_for` is available: Prometheus v3.13.1 and the PrometheusRule
  CRD both support it (verified against the live CRD schema).
- [observation] This is detection only. **The alert does not stop the stall from recurring.**

## Durable-fix options — research verdicts

### 1. Upstream fix (do this first, regardless of the rest)

The bug is a few lines: in tail mode, EOF must either close `responseChan` or trigger a
reconnect. File the issue (none exists) and, ideally, the patch. If upstream fixes it, every
option below becomes unnecessary. Zero local cost; uncertain timeline.

### 2. Push pipeline — needs one new component (verified)

The attractive "second vlagent sink straight into crowdsec's `http` source" **does not
work**. Two independent blockers, each fatal:

- [evidence] **zstd vs gzip.** vlagent hardcodes `Content-Encoding: zstd` and always
  zstd-compresses each block (`app/vlagent/remotewrite/client.go:315`,
  `pendinglogrows.go:147`); no disable flag exists anywhere in the `remotewrite` package.
  CrowdSec's `http` source decodes **gzip only** (`pkg/acquisition/modules/http/run.go:76`)
  and answers HTTP 400 to everything else.
- [evidence] **No per-sink filtering.** vlagent has no `-remoteWrite.filter` and no
  `-remoteWrite.urlRelabelConfig`; the only filter is the single global
  `-kubernetesCollector.excludeFilter` (`kubernetescollector/collector.go:214`), which is
  exclude-only and shared by all destinations. A second sink would fire **every cluster pod
  log** at the crowdsec agent.
- [evidence] vlagent also discards the original raw line: `processor.go:226-250` forwards
  only `parser.Fields`, and `RenameField(..., {"message","msg","log"}, "_msg")` finds no
  match in an envoy access log, so the row leaves the collector already flattened with no
  `_msg`. **This is where the "missing _msg" placeholder originates — the collector, not
  the VL server.**

So this path requires a translator (Vector / Fluent-bit) that accepts zstd `jsonline`,
filters to `namespace=networking, container=envoy`, and re-emits gzip-or-plain NDJSON.
**Its one advantage: it needs no hostPath, so the crowdsec namespace keeps `restricted`.**

### 3. Envoy as the producer — dead end

- [evidence] Envoy Gateway 1.8.3 access-log sinks are `File` | `ALS` (gRPC) |
  `OpenTelemetry` (OTLP). CrowdSec v1.7.8 ships no ALS, gRPC, or OTLP datasource — its full
  list is `appsec, cloudwatch, docker, file, journalctl, http, kafka, kinesis,
  kubernetesaudit, loki, s3, syslog, victorialogs, wineventlog`. No translator-free path.

### 4. The file datasource — simplest, but costs privileged PSA

CrowdSec's `file` source has proper tail-with-reopen semantics, reads the **raw** envoy JSON
line (so the `copy` + `pack_json` hack in `acquis.yaml` disappears too), and needs no new
component. It requires a hostPath mount of the node's container logs.

## What to do when the PSA is relaxed

This is the path the human intends ("a psa-t le fogjuk venni később"). Read the correction
below **before** planning it.

- [observation] **hostPath is forbidden in `baseline` too, not only in `restricted`.** The
  PSS Baseline profile lists "HostPath Volumes" among its restricted fields
  (`spec.volumes[*].hostPath` must be undefined/nil). So enabling the `file` datasource
  moves the crowdsec namespace from `restricted` all the way to **`privileged`** — it
  cannot stop at `baseline`.
- [observation] Current live state: `kubernetes/apps/crowdsec/namespace.yaml:11-16` sets
  `enforce/warn/audit: restricted` at `v1.36`, and the pod's `varlog` volume is an
  **emptyDir** (not a hostPath) — it exists only to give the read-only-rootfs container a
  writable `/var/log`. There is no hostPath in the crowdsec namespace today.

Steps, in order:

1. **File the upstream issue first** and check whether it is fixed before spending the PSA
   budget. If upstream lands a fix, stop here — bump the image and keep `restricted`.
2. **Decide explicitly between option 2 and option 4** on the security trade, not on
   convenience: one new component while keeping `restricted`, versus zero new components at
   `privileged`. Record the choice as an ADR — it reverses a human-locked decision (see the
   `restricted` PSA plus victorialogs lock in [[envoy-crowdsec-bouncer]]).
3. If option 4 is chosen:
   - Drop the crowdsec namespace to `privileged` (`enforce`), ideally keeping
     `warn/audit: restricted` so the delta stays visible.
   - Mount the node's container logs **read-only** (`/var/log/pods` or
     `/var/log/containers`); keep the existing emptyDir at `/var/log` from colliding with it.
   - Note the uid problem: host container logs are `0640 root:root`. The collector solves
     this with `supplementalGroups: [0]` (see the victoria-logs-collector helmrelease
     comment); crowdsec will need the same, which keeps `runAsNonRoot` true.
   - Replace the `victorialogs` source in `acquis.yaml` with a `file` source over the
     envoy pods' log glob, `labels.type: envoy`. **Delete the `copy` + `pack_json` pipe** —
     the raw line no longer needs reconstruction.
   - Keep `crowdsecurity/syslog-logs` in the collections: its `s00-raw` `non-syslog` node
     is what fills `evt.Parsed.message`, without which the envoy parser cannot match.
   - Re-verify with `cscli metrics` that `acquis_type=envoy` hits climb, and confirm the
     CNP no longer needs the crowdsec-to-victoria-logs egress rule.
4. **Simplify the alert afterwards.** A `file` source reading the same node's logs removes
   the network hop, but the traffic-gate blindness is a property of low envoy traffic, not of
   the datasource — so the 6h plus `keep_firing_for` shape stays valid. Revisit only if a
   heartbeat is added (see below).

## Deferred, with reasons

- [decision] **No heartbeat Probe now.** A `Probe` (http_2xx, 60s) through envoy-internal
  would guarantee a traffic floor, letting the alert drop the gate clause entirely and detect
  a stall in ~40m instead of ~6h. Deferred because the whole detection pipeline changes with
  the PSA migration. Two unknowns to resolve if it is revived: (a) how the blackbox pod
  reaches envoy-internal, since in-cluster resolution of the public hostname is not
  straightforward (k8s-gateway serves the LAN) — probably a Service address plus a `Host`
  header; (b) **self-ban risk** — 1440 identical requests/day traverse the fail-closed extAuth
  and AppSec, and self-banning has already happened in this setup (see
  [[envoy-crowdsec-bouncer]] Session 4). A crowdsec allowlist for the pod CIDR would be a
  prerequisite.
- [decision] **No auto-heal watchdog now.** A CronJob comparing counter staleness and deleting
  the pod would self-heal within the current architecture, but needs `delete pods` RBAC and
  is a moving part. Build it only if the fixed alert proves annoying in practice — expected
  rate is once per VictoriaLogs pod replacement, i.e. weekly-to-monthly.

## Verification criteria

- [criterion] The alert fires and **stays** firing across a full simulated stall. Reproduce by
  deleting `victoria-logs-server-0` and leaving crowdsec alone for more than 6h.
- [criterion] `cs_parser_hits_ok_total{acquis_type="envoy"}` climbs continuously across a
  victoria-logs-server pod replacement — this is the actual fix, and the only one that matters.
- [criterion] `cs_active_decisions` shows an `origin="crowdsec"` series after a deliberate
  local trigger, proving the detection path produces decisions end to end.

## Related

- relates_to [[envoy-crowdsec-bouncer]]
- relates_to [[pod-security-admission-enforcement]]
- relates_to [[networking]]
- relates_to [[observability]]
- relates_to [[cr-health-alerting]]
