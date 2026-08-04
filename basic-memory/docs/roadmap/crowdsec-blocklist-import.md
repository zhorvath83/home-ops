---
title: crowdsec-blocklist-import
type: roadmap
permalink: home-ops/docs/roadmap/crowdsec-blocklist-import
topic: Adoption of crowdsec-blocklist-import for enhanced threat intelligence
status: proposed
priority: medium
scope: Block known-malicious source IPs at the Envoy gateway before a request reaches
  any application, by importing a precision-tiered set of third-party threat-intelligence
  feeds into the existing CrowdSec LAPI with `wolffcatskyy/crowdsec-blocklist-import`,
  on top of the CAPI community blocklist. The tool runs as a batch job, fetching external
  blocklists, deduplicating them against existing LAPI decisions, and importing new
  IPs with a configurable TTL to prevent database bloat. The design must remain valid
  if the cluster moves from Cloudflare Tunnel to direct exposure.
rationale: 'The gain is defensive and pre-authentication: known C2 and malware-hosting
  infrastructure, mass credential-stuffing and SSH/RDP brute-force sources, hijacked
  netblocks and already- compromised hosts are dropped at `envoy-external` before
  they reach an application or the SSO/OIDC gate. CAPI alone covers a baseline (~20k
  IPs); the external feeds widen that coverage with independently curated intelligence.
  Today, the cluster sits behind Cloudflare Tunnel, whose edge filtering absorbs a
  lot, making external feeds a supplement with modest marginal value. In the future,
  the infrastructure may be directly exposed with no edge filter, managed WAF, or
  Cloudflare bot/threat scoring. In that regime, external blocklists become materially
  more valuable and the blocklist plane becomes a primary control. The design must
  be valid in both regimes without rework. The `crowdsec-blocklist-import` tool automates
  the ingestion of such feeds directly into the LAPI via a batch process, with built-in
  deduplication to avoid overloading the single-node SQLite backend.'
options:
- CronJob (Recommended) — The tool is designed to run once and exit (`INTERVAL=0`
  default). A CronJob aligns perfectly with this execution model and the repo's GitOps
  workflow. It allows external scheduling, prevents resource consumption during idle
  periods, and integrates cleanly with Flux CD.
- Long-running Deployment (Rejected) — While the tool supports a daemon mode (`INTERVAL=3600`),
  keeping a Python process running constantly just to wake up hourly is wasteful on
  a single-node cluster. A CronJob achieves the same result with lower resource overhead.
- CrowdSec-native mechanisms (Partly redundant) — CAPI is already enabled and provides
  ~20k IPs. This tool supplements CAPI with specialized lists that are not natively
  included in the free CAPI tier.
- Do nothing (Live option) — The cluster relies solely on CAPI, local detections,
  and Cloudflare edge filtering. For a home cluster, this baseline may already be
  sufficient, making adoption optional.
related_areas:
- networking
- observability
- external-secrets
---

# crowdsec-blocklist-import

## Metadata (observation-form, schema validation)

- [topic] Adoption of crowdsec-blocklist-import for enhanced threat intelligence
- [status] proposed
- [priority] medium
- [verification] The list-selection and integration-shape assessment was produced by an Ollama agent and independently spot-verified by the Maestro against repo files. The remaining numbers marked "approx" come from the upstream docs and the blog.lrvt.de/enhancing-crowdsec article, not from a local measurement.

## Context

The purpose of this roadmap item is defensive coverage: drop automated attack traffic from known-bad source IPs at `envoy-external`, before the request reaches an application or the SSO/OIDC gate. The cluster today enforces the CAPI community blocklist (~20k IPs) and local scenario-based bans via the Envoy CrowdSec bouncer; CAPI is a baseline, and the external feeds widen it with independently curated intelligence on C2 infrastructure, brute-force sources, hijacked netblocks and compromised hosts. The `crowdsec-blocklist-import` tool automates the ingestion of such feeds directly into the LAPI via a batch process, with built-in deduplication to avoid overloading the single-node SQLite backend.

**Scope boundary.** In scope: the blocklist import plane only — a CronJob that fetches curated
feeds and writes decisions into the existing LAPI, plus its secret delivery, egress policy and
observability. Out of scope, because they are already owned by the deployed CrowdSec/bouncer
implementation ([[envoy-crowdsec-bouncer]]): how the gateway resolves the client IP, the extAuth
wiring, CAPI configuration, and the local scenario/AppSec planes. This item consumes whatever
client IP the bouncer already evaluates; it neither changes nor depends on how that value is
derived.

**Exposure regime and marginal value.** The cluster sits behind Cloudflare Tunnel today, whose edge
filtering absorbs a lot, so extra feeds buy less than on a directly-exposed host. Cloudflare is a
current deployment detail, not a design premise: under direct exposure there is no edge filter, no
managed WAF and no bot/threat scoring in front of the cluster, and the blocklist plane becomes a
primary control rather than a supplement. The design must hold in both regimes without rework.
Consequently "the feed only buys a little because Cloudflare already filters" is not a valid reason
to disable a feed — only false-positive risk, genuine irrelevance to this cluster's services, or
redundancy with CAPI/another enabled feed is.

## Security value

**What it buys** — pre-authentication blocking at the cluster edge (`envoy-external`), with no
per-app work, against attack classes that are identifiable by source IP:

- known C2 and malware-hosting infrastructure — Abuse.ch (Feodo + URLhaus), Cybercrime Tracker,
  Monty Security C2, VX Vault, Botvrij, Binary Defense
- mass credential-stuffing and SSH/RDP brute-force sources — Bruteforce Blocker, DShield
- hijacked / permanently criminal-controlled netblocks — Spamhaus DROP
- hosts already compromised and used for automated attack traffic — Emerging Threats

These are the Tier A feeds (see list selection): every entry asserts *confirmed* malicious
infrastructure. Reputation aggregates (Blocklist.de, IPsum, CI Army, GreenSnow, AbuseIPDB, Firehol)
would add volume in the same attack classes but not verification, so they stay evidence-gated in
Tier B — the defensive claim above is deliberately limited to what Tier A actually supports.

The block happens *in front of* the SSO/OIDC gate, so it also shields surfaces the gate does not
cover (unauthenticated endpoints, health/callback paths, any route exposed without the OIDC
SecurityPolicy). It is defence-in-depth ahead of that gate, never a replacement for it.

**What it does NOT protect against** — stated plainly so the plane is not over-trusted:

- targeted attacks from clean or rapidly rotating IPs; residential-proxy and cloud-rented IPs
- application-layer vulnerabilities (that is AppSec/WAF territory, and patching)
- credential compromise, session/token theft, or abuse by an authenticated user
- insider or LAN-origin abuse — LAN is whitelisted by design (`crowdsecurity/whitelists`)
- anything arriving over a path that does not traverse `envoy-external` (internal gateway,
  NodePort/hostPort, direct pod access, non-HTTP protocols)

**Posture in both exposure regimes** — today: Cloudflare edge filtering + CAPI + local scenarios +
this plane. After a possible move to direct exposure: this plane + CAPI + local scenarios **only**,
with no edge filter, no managed WAF and no bot/threat scoring in front of the cluster. That is the
argument for adopting now rather than later: the control is in place, sized and measured *before*
the exposure change removes the edge, instead of being stood up under pressure afterwards.

**False positives are a security-adjacent availability failure** (self-lockout of legitimate users
is an outage, and an outage is a security event). That is why Tor exit nodes and scanner feeds stay
disabled, and why the 24h decision TTL, the `ALLOWLIST`, and the existing `crowdsecurity/whitelists`
parser are treated as required compensating controls, not optional extras.

## Assessment — integration shape

A Kubernetes `CronJob` is the correct integration shape for this tool in this cluster.

- **CronJob (Recommended)**: The tool is designed to run once and exit (`INTERVAL=0` default). A CronJob aligns perfectly with this execution model and the repo's GitOps workflow. It allows external scheduling, prevents resource consumption during idle periods, and integrates cleanly with Flux CD.
- **Long-running Deployment (Rejected)**: While the tool supports a daemon mode (`INTERVAL=3600`), keeping a Python process running constantly just to wake up hourly is wasteful on a single-node cluster. A CronJob achieves the same result with lower resource overhead.
- **CrowdSec-native mechanisms (Partly redundant)**: CAPI is already enabled and provides ~20k IPs. This tool supplements CAPI with specialized lists that are not natively included in the free CAPI tier.
- **Do nothing (Live option)**: No third-party threat-intel plane at all — the cluster relies on CAPI, local scenario detections and, for as long as it lasts, Cloudflare edge filtering. Security cost: after a move to direct exposure the cluster would face the internet with CAPI + local scenarios alone, and the coverage gap would have to be closed reactively. For a home cluster the baseline may still be judged sufficient; that is the human's call (decision 1).

## Assessment — list selection

Feeds are classified by **precision** — what a listing actually asserts about an IP — not by size.
Volume is not a defensive benefit: an IP that never sends a request to this cluster is a row in
SQLite, not a blocked attack. Every low-precision entry, by contrast, carries a real chance of
locking out a legitimate user of *these* services (CGNAT, mobile carriers, shared hosting, VPN
exits).

| List | Env flag | Approx size | Precision (what a listing asserts) | Tier | FP risk |
|------|----------|-------------|------------------------------------|------|---------|
| Spamhaus DROP | `ENABLE_SPAMHAUS` | 1.5k | netblock is hijacked / wholly criminal-controlled | **A** | Low |
| Abuse.ch (Feodo + URLhaus) | `ENABLE_ABUSE_CH` | ~10k | verified malware C2 / malware-hosting host | **A** | Low |
| Emerging Threats | `ENABLE_EMERGING_THREATS` | 0.5k | host observed compromised and used for attacks | **A** | Low |
| Binary Defense | `ENABLE_BINARY_DEFENSE` | 1.3k | malware / botnet infrastructure, vetted | **A** | Low |
| DShield (ISC top attackers) | `ENABLE_DSHIELD` | 20 | top attack sources by volume across ISC sensors | **A** | Very low |
| Bruteforce Blocker | `ENABLE_BRUTEFORCE_BLOCKER` | 0.5k | host observed performing SSH/RDP brute force | **A** | Low |
| Cybercrime Tracker | `ENABLE_CYBERCRIME_TRACKER` | small | tracked C2 panel / fraud infrastructure | **A** | Low |
| Monty Security C2 | `ENABLE_MONTY_SECURITY_C2` | small | identified C2 server | **A** | Low |
| VX Vault | `ENABLE_VXVAULT` | small | malware distribution host | **A** | Low |
| Botvrij | `ENABLE_BOTVRIJ` | 4 | verified botnet C2 | **A** | Very low |
| Firehol Level 1 | `ENABLE_FIREHOL_LEVEL1` | 4.5k | composite of high-confidence feeds (largely the same sources as Tier A) | **B** | Low |
| IPsum | `ENABLE_IPSUM` | 19k | appeared on ≥3 other blocklists — reputation, not verification | **B** | Moderate |
| Blocklist.de (+ SSH/Apache/mail sub-lists) | `ENABLE_BLOCKLIST_DE` | 27k (+31k) | someone reported abuse from this IP | **B** | Moderate–High |
| CI Army | `ENABLE_CI_ARMY` | 15k | "poor reputation" score, vague criterion | **B** | Moderate |
| GreenSnow | `ENABLE_GREENSNOW` | 4.3k | attack attempts seen by GreenSnow sensors, limited vetting | **B** | Moderate |
| AbuseIPDB (public mirror) | `ENABLE_ABUSE_IPDB` | unknown | user-submitted reports, mirror quality unverified | **B** | Moderate |
| Sentinel (Turris) | `ENABLE_SENTINEL` | unknown | Turris sensor observations, precision undocumented here | **B** | Unknown |
| Firehol Level 2 | `ENABLE_FIREHOL_LEVEL2` | 19k | aggregate of aggregates | **C** | Moderate |
| Firehol Level 3 | `ENABLE_FIREHOL_LEVEL3` | >30k | most aggressive aggregation level | **C** | High |
| Firehol (meta flag) | `ENABLE_FIREHOL` | — | enables the Firehol group; leave off, use the per-level flags | **C** | — |
| Tor exit nodes | `ENABLE_TOR` | 1.3k + 2.4k | this IP is a Tor exit — not a malice signal | **C** | High (privacy-using legitimate visitors) |
| Scanners (Shodan/Censys) | `ENABLE_SCANNERS` | 47 | known internet-measurement infrastructure | **C** | Moderate (blocks legitimate research; rotating IPs make it futile) |
| StopForumSpam | `ENABLE_STOPFORUMSPAM` | 53 | forum-spam submitter | **C** | Low (irrelevant: no public forum) |

**Tier meanings.** **A** = confirmed malicious infrastructure, adopt now (~12–15k IPs).
**B** = reputation aggregate; adopt only on evidence from the observation window (below).
**C** = never for this cluster, for the reason stated in the row.

**Primary recommendation — Tier A only.** Complete env-var block:

```yaml
ENABLE_SPAMHAUS: "true"
ENABLE_ABUSE_CH: "true"
ENABLE_EMERGING_THREATS: "true"
ENABLE_BINARY_DEFENSE: "true"
ENABLE_DSHIELD: "true"
ENABLE_BRUTEFORCE_BLOCKER: "true"
ENABLE_CYBERCRIME_TRACKER: "true"
ENABLE_MONTY_SECURITY_C2: "true"
ENABLE_VXVAULT: "true"
ENABLE_BOTVRIJ: "true"
ENABLE_FIREHOL: "false"
ENABLE_FIREHOL_LEVEL1: "false"
ENABLE_FIREHOL_LEVEL2: "false"
ENABLE_FIREHOL_LEVEL3: "false"
ENABLE_IPSUM: "false"
ENABLE_BLOCKLIST_DE: "false"
ENABLE_CI_ARMY: "false"
ENABLE_GREENSNOW: "false"
ENABLE_ABUSE_IPDB: "false"
ENABLE_SENTINEL: "false"
ENABLE_TOR: "false"
ENABLE_SCANNERS: "false"
ENABLE_STOPFORUMSPAM: "false"
DECISION_DURATION: "24h"
DECISION_ORIGIN: "blocklist-import"
MAX_DECISIONS: "50000"
BATCH_SIZE: "500"
CONSOLIDATE_ALERTS: "true"
ALLOWLIST: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
TELEMETRY_ENABLED: "false"
METRICS_ENABLED: "false"
LOG_LEVEL: "INFO"
```

`MAX_DECISIONS: 50000` is a safety cap on what one import run may push (Tier A ~15k plus ample
headroom), so a feed that suddenly balloons fails the run instead of flooding the LAPI. It is not a
cap on total LAPI decisions. `METRICS_ENABLED: "false"` because the cluster runs no Prometheus
Pushgateway — LAPI-side metrics are the observability path. `ALLOWLIST` complements, and does not
replace, the existing `crowdsecurity/whitelists` parser.

**Promotion path to Tier B.** Tier B is enabled per feed, one at a time, only when the observation
window (Phase 4) shows Tier A + CAPI leaving a real gap — i.e. attack traffic reaching the services
from IPs that a specific Tier B feed lists. Enable one feed, keep the same window length, and check
both directions: did anything new get blocked, and did any legitimate user get locked out. Note that
Firehol Level 1 largely re-derives the Tier A sources, so it is the *least* likely Tier B feed to
add coverage despite being the safest.

Per the repo's priority order (Security > Clarity > Performance), resource headroom must never be
the reason a defensive feed is dropped — only false-positive risk or genuine irrelevance may
disable one. Equally, "we may raise memory" is permission, not an obligation to import volume.

## Sizing

The memory number is a **consequence** of the list decision, not an independent choice.

- Measured: bouncer at 32Mi resident while caching ~20k CAPI decisions
  (`bouncer_decision_cache_size{origin="CAPI"} = 19956`), request 64Mi, limit 128Mi
  (`kubernetes/apps/crowdsec/bouncer/app/helmrelease.yaml:62-67`).
- Attributing the whole 32Mi to the cache gives a deliberately conservative ~1.6 KiB per decision
  (the real per-decision cost is lower, since a Go process has a baseline footprint). One data
  point — this is an **extrapolation**, not a measurement of scaling.
- Tier A (~15k decisions) on top of CAPI (~20k) ≈ 35k decisions → ~56Mi by the conservative
  estimate. That fits inside the **existing** 128Mi limit with ~2.3x headroom.

**Recommendation now: change nothing.** Keep `requests.memory: 64Mi` / `limits.memory: 128Mi`. A
raise is not free: the bouncer is fail-closed (`failOpen: false`), so restarting it to apply a new
limit denies traffic on `envoy-external` for the duration of the rollout. Speculative headroom buys
nothing and costs a remediation gap.

**Only if Tier B is later promoted** (worst case ~90k additional decisions → ~145Mi by the same
conservative estimate) raise to `requests.memory: 192Mi` / `limits.memory: 384Mi`, in the same
change that enables the feed, so the restart is paid once. If instead the node ever gets tight (it
is not today: 64GiB, 14% requested, 20% used), revisit the request rather than the limit.

Watch the LAPI side independently: `cs_active_decisions{job="crowdsec-service", namespace="crowdsec"}`
for total decision growth, plus LAPI CPU/memory (43Mi / 256Mi request / 768Mi limit today) and the
latency of the bouncer's decision stream. SQLite + WAL handles tens of thousands of rows without
trouble; a Postgres LAPI is a follow-up only if measurements demand it, and is out of scope here.

## Design

- **File paths**:
  - `kubernetes/apps/crowdsec/blocklist-import/ks.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/kustomization.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/helmrelease.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/externalsecret.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/ciliumnetworkpolicy.yaml`
  - `kubernetes/apps/crowdsec/blocklist-import/app/prometheusrule.yaml`
- **CronJob spec**: Deployed via `bjw-s/app-template` (repo idiom). Schedule: `0 4 * * *` (daily). `concurrencyPolicy: Forbid`, `restartPolicy: OnFailure`, `backoffLimit: 3`. CronJob pod resources: requests `cpu: 50m`, `memory: 64Mi`; limits `memory: 256Mi` (the importer's own working set — unrelated to the bouncer's cache sizing).
- **Secret flow**: The tool requires a bouncer key (read) and machine credentials (write). These will be generated manually via `cscli` and stored in the existing 1Password `crowdsec` item. An `ExternalSecret` will sync them to a Kubernetes Secret named `crowdsec-blocklist-import-secret`. The HelmRelease will mount these via `envFrom`.
- **Egress network policy**: A CiliumNetworkPolicy must allow egress from the CronJob pod to:
  - `http://crowdsec-service.crowdsec.svc.cluster.local:8080` (LAPI)
  - External blocklist FQDNs for the BROAD selection:
    - `feodotracker.abuse.ch`
    - `urlhaus.abuse.ch`
    - `rules.emergingthreats.net`
    - `www.binarydefense.com`
    - `feeds.dshield.org`
    - `www.dshield.org`
    - `danger.rulez.sk`
    - `www.spamhaus.org`
    - `www.botvrij.eu`
    - `github.com`
    - `api.github.com`
    - `raw.githubusercontent.com`
    - `gist.githubusercontent.com`
    - `crowdsecurity.github.io`
    - `lists.abuseipdb.com`
    - `api.abuseipdb.com`
    - `sentinel.tdmdn.com`
  - `bouncer-telemetry.ms2738.workers.dev` must NOT be allowed (`TELEMETRY_ENABLED=false` in addition, defence in depth).
- **Observability**: A PrometheusRule will alert on `CronJobJobFailed`. The existing `CrowdSecBanActive` alert in `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml` must exclude the new `blocklist-import` origin, otherwise it fires continuously.
- **Pod security**: Image provenance pinned to `ghcr.io/wolffcatskyy/crowdsec-blocklist-import:3.7.1@sha256:78ec83464827a129128e2e1cba0bc23562988bec177745334a9f2896c817860c` (OCI image index, multi-arch). The Dockerfile creates a non-root system user (`blocklist`) without a fixed UID. The pod security context will set `runAsNonRoot: true` and `readOnlyRootFilesystem: true`. `capabilities: {drop: ["ALL"]}`.
- **Renovate**: The image will be tracked via `renovate: datasource=docker depName=ghcr.io/wolffcatskyy/crowdsec-blocklist-import` annotation.
- **Allowlist**: The `ALLOWLIST` env var complements (does not replace) the existing `crowdsecurity/whitelists` parser which already whitelists LAN traffic.

## Execution plan (research-backed)

### Phase 1 — credentials and registration
- Generate a bouncer API key and machine credentials, store them in the existing 1Password
  `crowdsec` item as `BLOCKLIST_IMPORT_BOUNCER_KEY` and `BLOCKLIST_IMPORT_MACHINE_PASSWORD`.
- Wire `BOUNCER_KEY_blocklist_import` into the LAPI HelmRelease env (auto-registration) and the
  machine registration into the existing postStart hook; add the fields to the crowdsec
  `ExternalSecret`.
- **Acceptance**: `kubectl -n crowdsec get externalsecret` reports `SecretSynced`;
  `kubectl -n crowdsec exec deploy/crowdsec-lapi -- cscli bouncers list` and `cscli machines list`
  both show the registration, with a deliberate naming split: `cscli bouncers list` shows
  `blocklist_import` (UNDERSCORE — the LAPI `docker_start.sh` derives bouncer names via
  `cut -d_ -f3-` and bash `compgen -A variable` cannot see hyphenated env-var names), while
  `cscli machines list` shows `blocklist-import` (HYPHEN — registered by the postStart hook).
  Seeing `blocklist-import` in `cscli bouncers list` would be a failure.

### Phase 2 — CronJob with Tier A, dry run first
- Add `kubernetes/apps/crowdsec/blocklist-import/{ks.yaml,app/*}` (app-template, cronjob
  controller), image pinned by digest, Tier A env block, `DRY_RUN: "true"` on the first roll-out.
- **Acceptance**: `kubectl -n crowdsec create job --from=cronjob/blocklist-import bli-dryrun` →
  `kubectl -n crowdsec logs job/bli-dryrun` shows every Tier A feed fetched, a deduplicated count,
  and no write attempt; `cscli decisions list --origin blocklist-import` still empty.
- **Auth gate (does NOT depend on dry-run)**: the `DRY_RUN: "false"` run below is the
  credential gate — a 401 at `/v1/watchers/login` (machine JWT) or `/v1/decisions` (bouncer key)
  fails the Job loudly, catching an empty or templated-out machine password or bouncer key. Under
  `DRY_RUN=true` upstream skips the auth check, `can_write()`, the health check and the
  existing-decisions fetch, so a green dry-run is NOT sufficient evidence and its dedup count is
  vacuous against an empty existing-decisions set.
- Then flip `DRY_RUN: "false"`, re-run manually, and confirm
  `cscli decisions list --origin blocklist-import | wc -l` is in the expected ~10–20k range and
  `MAX_DECISIONS` was not hit.

### Phase 3 — network policy and observability
- `CiliumNetworkPolicy`: egress to the LAPI service on 8080 plus **only** the Tier A feed FQDNs;
  `bouncer-telemetry.ms2738.workers.dev` explicitly not allowed. Add the LAPI-side ingress entry
  for the new pod. Extend `CrowdSecBanActive` in
  `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml:50` to exclude the
  `blocklist-import` origin, and add a job-failure alert for the CronJob.
- **Acceptance**: `just k8s hubble-live-capture 120` during a manual run, then
  `just k8s hubble-analyze k8s:app.kubernetes.io/name=blocklist-import DROPPED egress` shows no
  unexpected drops and no flow to the telemetry FQDN; `flux get ks -A` reconciled;
  the new alert rules appear in Prometheus and `CrowdSecBanActive` is not firing.

### Phase 4 — observation window (3 weeks) and review gate
- Measure at the end of the window:
  - decision volume by origin: `sum by (origin) (cs_active_decisions{job="crowdsec-service", namespace="crowdsec"})`
    — verified to exist (`prometheusrule.yaml:50` already uses this metric).
  - bouncer cache size: `bouncer_decision_cache_size` by origin — verified in use
    (`docs/progress/envoy-crowdsec-bouncer`).
  - **hits** (requests actually blocked, by origin): NOT verified to exist as a metric. Acceptance
    criterion: first verify whether the bouncer exposes a per-origin block counter (inspect
    `/metrics` on the bouncer pod and the bouncer Grafana dashboard); if it does not, fall back to
    counting bouncer-denied requests in VictoriaLogs (bouncer + Envoy access logs, 403s attributed
    to extAuth) and correlating the source IPs against `cscli decisions list --origin blocklist-import -o json`.
- Decision rule: prune any Tier A feed with zero correlated hits **and** no unique coverage; do not
  promote a Tier B feed unless the logs show attack traffic that Tier A + CAPI missed and that feed
  lists. Record the numbers in the progress note — a null result is a valid, publishable outcome.

### Phase 5 — conditional Tier B promotion (only if Phase 4 justifies it)
- Enable one Tier B feed, together with the memory raise from the Sizing section and the matching
  `MAX_DECISIONS` bump and CNP FQDN additions, in a single change so the bouncer restarts once.
- **Acceptance**: after the restart, `kubectl -n crowdsec get pod -l app.kubernetes.io/name=crowdsec-bouncer -o jsonpath='{.items[*].status.containerStatuses[*].lastState.terminated.reason}'`
  shows no `OOMKilled`; `kubectl top pod -n crowdsec` stays below the new limit after a full import;
  a smoke request through `envoy-external` still succeeds; repeat the Phase 4 measurement for the
  newly enabled feed.

## Risks and blast radius

- **False positives**: Blocking a legitimate IP could lock out a user. The `ALLOWLIST` includes private IP ranges to prevent self-bans. The 24h TTL ensures any false positives expire within a day.
- **Database bloat**: Every imported IP is a row in the SQLite LAPI and an entry in the bouncer's in-memory cache. Tier A (~15k) on top of CAPI (~20k) is well within today's limits (see Sizing); `MAX_DECISIONS: 50000` caps what a single import run may push, so a ballooning feed fails the run instead of flooding the LAPI.
- **Egress policy complexity**: The CronJob requires egress to external FQDNs. If any FQDN changes, the job will fail to fetch that list, though it will continue with others. The CiliumNetworkPolicy must be maintained.
- **Telemetry**: The tool sends anonymous telemetry by default. This will be disabled (`TELEMETRY_ENABLED=false`) and the telemetry FQDN will be blocked by the CNP.
- **Dependency, not scope — client-IP resolution**: the value the bouncer matches decisions against is produced by the existing gateway/bouncer implementation. This plane inherits it and is only as accurate as that resolution. If the cluster ever leaves Cloudflare, revisiting client-IP handling belongs to [[envoy-crowdsec-bouncer]], and should be handled there before the exposure change; no work in this roadmap item depends on it.
- **Blast radius on already-deployed files**:
  - `kubernetes/apps/crowdsec/bouncer/app/helmrelease.yaml:62-67`: 64Mi request / 128Mi limit, single replica, fail-closed. Tier A needs no change here (see Sizing); a raise is only part of a later Tier B promotion, and because the bouncer is fail-closed the restart it requires is itself a brief denial window on `envoy-external`.
  - `kubernetes/apps/crowdsec/bouncer/app/helmrelease.yaml:40`: LAPI in-cluster URL is `http://crowdsec-service.crowdsec.svc.cluster.local:8080`.
  - `kubernetes/apps/crowdsec/crowdsec/app/prometheusrule.yaml:50`: The `cs_active_decisions{job="crowdsec-service", namespace="crowdsec"}` metric is already in use, and the existing `CrowdSecBanActive` expression filters `origin!~"CAPI|lists(:.*)?"`. The required change is extending that regex to also exclude `blocklist-import`.

## Decisions needed from human

1. **Adopt at all?** (a) Adopt with Tier A — recommended: pre-authentication blocking of confirmed
   malicious infrastructure, no outage risk, and the control is in place before a possible move to
   direct exposure removes Cloudflare's edge filtering. (b) Do nothing — CAPI + local scenarios +
   (for now) Cloudflare edge; accepts closing the gap reactively later.
2. **Scope of enablement.** (a) Tier A only now, Tier B strictly evidence-gated — **recommended**.
   (b) Tier A + Tier B immediately (~150k decisions): more rows, no demonstrated extra blocking,
   higher false-positive exposure for legitimate CGNAT/mobile/VPN users.
3. **Memory now or later.** (a) Change nothing now — 64Mi/128Mi covers CAPI + Tier A with ~2.3x
   headroom — **recommended**. (b) Raise to 192Mi/384Mi pre-emptively: costs a bouncer restart
   (a denial window on a fail-closed control) for headroom nothing currently needs.
4. **Observation window length.** (a) 2 weeks. (b) **3 weeks — recommended** (enough traffic to
   judge, short enough to act on). (c) 4 weeks.

## Open questions / evidence gaps

- EVIDENCE GAP: The exact UID of the `blocklist` user in the Docker image. The Dockerfile uses `useradd -r` without a fixed UID. The security context will rely on `runAsNonRoot: true` without an explicit `runAsUser` unless the UID is verified.

## Related

- relates_to [[envoy-crowdsec-bouncer]] — the completed bouncer work that this roadmap item supplements
- relates_to [[networking]] — egress network policies and LAPI connectivity
- relates_to [[observability]] — PrometheusRules for job failure alerts and LAPI decision metrics
- relates_to [[external-secrets]] — 1Password Connect integration for bouncer and machine credentials
