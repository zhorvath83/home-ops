---
title: envoy-crowdsec-bouncer
type: progress-note
permalink: home-ops/docs/progress/envoy-crowdsec-bouncer
tags:
- crowdsec
- networking
- security
- progress
---

# envoy-crowdsec-bouncer — execution progress

## Metadata (observation-form)

- [topic] Execution state for the envoy-crowdsec-bouncer roadmap
- [status] done
- [roadmap] [[envoy-crowdsec-bouncer]] (docs/roadmap)
- [priority] medium
- [area] networking
- [created] 2026-07-27

## Execution model (decided with human, 2026-07-27)

- [decision] Delivery: direct commits to `main` (repo norm; Flux watches refs/heads/main).
- [decision] Scope this round: Phase 0-2 code + observability. The Gateway-level extAuth
  SecurityPolicy is held back to a separate commit that only lands after explicit human
  approval, because attaching it fails requests closed gateway-wide.
- [decision] Credentials: pre-generated values in the 1Password `crowdsec` item, delivered by
  ESO. Registration turned out to be automatic (see below), so the approved "one-shot cscli
  exec" step is not needed.
- [decision] Architecture: bjw-s app-template, NOT the official crowdsec Helm chart.

## Gate verifications (the roadmap's two blocked pillars)

### Gate 1 — envoy log acquisition: RESOLVED, self-contained

The roadmap's locked `victorialogs` acquisition does NOT work as written, and the fix is
not the one the roadmap guessed at.

- [evidence] The crowdsec `victorialogs` datasource unmarshals each VictoriaLogs record into
  a struct with only two fields — `_msg` and `_time`
  (`pkg/acquisition/modules/victorialogs/internal/vlclient/types.go:9-12`) — and assigns
  `Line.Raw = entry.Message` (`run.go:53-60`). Every other field is discarded by
  `encoding/json` before any parser runs, so a custom parser over the flat VL fields is
  impossible, and `transform` cannot recover them either.
- [evidence] Live query against `victoria-logs-server.observability:9428`: envoy access-log
  records carry `_msg` = the literal `"missing _msg field; see …"` placeholder (VictoriaLogs
  `DefaultMsgValue`), with the envoy JSON decomposed into flat fields (`method`, `path`,
  `response_code`, `downstream_remote_address`, `x_forwarded_for`, `start_time`,
  `authority`, `user_agent`, …). Identical for envoy-external and envoy-internal.
- [evidence] The `yanis-kouidri/envoy` parser reads `evt.Parsed.message` (populated from
  `Line.Raw` by the `crowdsecurity/non-syslog` s00-raw node) and JSON-unmarshals it, keying on
  `start_time`, `downstream_remote_address`, `x-envoy-origin-path`, `method`,
  `response_code`, `user-agent`, `:authority`. There is no official `crowdsecurity/envoy`
  parser in the hub — only this third-party collection, and its own hubtest targets the
  file/CRI path.
- [decision] Fix entirely inside the crowdsec acquisition config: a LogsQL `copy` + `pack_json`
  pipe rebuilds a parser-shaped JSON line into `_msg`. Nothing in the shared envoy-gateway
  config or the observability pipeline is touched.
- [verified] Live `/select/logsql/query`: 200/200 records produced a correct reconstructed
  JSON line, 0 empty objects. Live `/select/logsql/tail` with real traffic through
  envoy-internal returned the reconstructed line (ingest lag ~5s), confirming `pack_json`
  is live-tail-capable (`pipe_pack_json.go` `canLiveTail() == true`).
- [observation] The `response_code:* AND method:*` filter is load-bearing: envoy also logs
  connection-level records with `response_code: "0"` and no method/path, which would otherwise
  pack to an empty object.

### Gate 2 — restricted PSA: ACHIEVED, but only off-chart

- [evidence] `crowdsecurity/crowdsec:v1.7.8` image config has `User: null` (uid 0), and
  `/etc/crowdsec` does not exist in the image — it is created at startup.
- [evidence] Layer inspection of the real file modes (an earlier review got this wrong):
  `staging/etc/crowdsec/config.yaml` is 0644 (world-readable), while
  `local_api_credentials.yaml` and `online_api_credentials.yaml` are 0600 root.
- [evidence] `docker_start.sh:6` sets `set -e` + `inherit_errexit`; `:322-332` seeds an empty
  `/etc/crowdsec` with `rsync -av --ignore-existing /staging/etc/crowdsec/*`. As uid 1000 that
  rsync fails on the two 0600 files (exit 23) and kills the container.
- [decision] Wrap the entrypoint:
  `rsync -a --ignore-existing /staging/etc/crowdsec/ /etc/crowdsec/ || true; exec /bin/bash /docker_start.sh`.
  After it `config.yaml` exists, so `:322` short-circuits and the image never runs its own
  rsync; the missing credentials are regenerated anyway by `:369`
  (`cscli machines add --auto --force`) and `:420` (`cscli capi register`).
- [observation] The official crowdsec chart cannot do this — it hardcodes the LAPI container
  command (`cp … && ln -s /etc/crowdsec && bash /docker_start.sh`) with no override value.
  This is what forced the app-template architecture.
- [decision] Namespace carries `enforce/warn/audit: restricted` at `v1.36` (cluster is
  k8s v1.36.3). First namespace in the repo with a PSA label.

## Credential registration is automatic (supersedes a roadmap decision)

- [evidence] `docker_start.sh:472-478` iterates `BOUNCER_KEY_*` env vars and calls
  `register_bouncer()` (`:137-146` runs `cscli bouncers add <name> -k <key>`, skipped if already
  registered). `:375-379` registers one extra machine from `AGENT_USERNAME`/`AGENT_PASSWORD`.
- [decision] So `BOUNCER_KEY_envoy` and `AGENT_PASSWORD` come from ESO env and register
  themselves idempotently on every start. The roadmap's claim that the chart generates these
  is false (the chart has zero bouncer templates), but no manual `kubectl exec` is needed either.

## Other roadmap corrections (evidence-backed)

- [observation] Bouncer chart 0.6.3 is the latest; 0.7.0 does not exist in
  `ghcr.io/kdwils/charts/envoy-proxy-bouncer`. crowdsec chart 0.24.0 does exist but is unused now.
- [observation] No MaxMind secret needed. `crowdsecurity/geoip-enrich` pulls
  `GeoLite2-City.mmdb` / `GeoLite2-ASN.mmdb` from `hub-data.crowdsec.net/mmdb_update/`
  unauthenticated. The roadmap's MaxMind ExternalSecret + egress rule are dropped.
- [observation] No self-ban whitelist config needed. `crowdsecurity/whitelists` (s02-enrich,
  pre-installed in the image) already whitelists 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12,
  192.168.0.0/16.
- [decision] `crowdsecurity/appsec-crs` dropped from the collection list:
  `crowdsecurity/appsec-default` only references `vpatch-*` and `generic-*` rules, so the CRS
  collection would be installed but inert — and CRS is a known false-positive source. Follow-up.
- [decision] `exemptIPs` is `10.0.0.0/8` only (pod + service CIDR), NOT the LAN. The roadmap
  exempted `LAN_SUBNET` too, which would have made the envoy-internal attachment pointless
  (LAN clients are the only clients there). Private IPs still cannot be IP-banned thanks to the
  whitelist parser, but AppSec WAF inspection now applies to LAN requests.
- [decision] Client IP comes from `trustedIPHeader: X-Envoy-External-Address` — the value Envoy
  already resolved (CF-Connecting-IP externally, TCP source on the LAN gateway), so no XFF
  walking and no proxy CIDR list to maintain.
- [decision] No VolSync backup. crowdsec state is disposable (bouncer/machine credentials
  re-register from env, decisions repopulate from CAPI and fresh detections), and the kopia
  mover's PSA-restricted compatibility is unverified — adding it could silently break backups
  in a `restricted` namespace. Follow-up if the Web UI's alert history becomes worth keeping.
- [decision] CAPI community blocklist is on (the entrypoint registers automatically), but
  console enrollment is deferred — it needs `ENROLL_KEY` from the 1Password
  `CAPI_ENROLL_TOKEN` field, which is not verified to exist yet. Follow-up.
- [observation] `container_runtime` (the chart value that would have mounted a bogus
  `/var/lib/docker/containers` hostPath on Talos) is moot off-chart.

## Implemented — commit `cd7ab20c2`

`kubernetes/apps/crowdsec/` — new app group, three Flux Kustomizations:

- `namespace.yaml` — `restricted` PSA labels, prune disabled.
- `crowdsec/` — engine. app-template, one container = LAPI + agent + AppSec (AppSec is an
  acquisition datasource, not a separate component). Two PVCs: `/etc/crowdsec` (hub +
  generated credentials + mutated config.yaml, so CAPI registration and hub download stay
  one-shot) and `/var/lib/crowdsec/data` (SQLite + mmdb). ConfigMaps for `acquis.yaml` and
  `config.yaml.local` are nested inside the `/etc/crowdsec` mount.
- `bouncer/` — kdwils chart 0.6.3, `nameOverride` + `fullnameOverride: crowdsec-bouncer`,
  WAF on, `referenceGrant.create` for `networking`, Prometheus + ServiceMonitor.
- `web-ui/` — app-template, `ghcr.io/theduffman85/crowdsec-web-ui:2026.7.22`, native Pocket ID
  OIDC (`infra_admins`, `unmatchedRole: deny`), route on `envoy-internal` only at
  `crowdsec.PUBLIC_DOMAIN`, 1Gi PVC at `/app/data`.
- Observability: ServiceMonitors, `GrafanaFolder/crowdsec`, dashboard 21689 by URL, the
  bouncer's chart dashboard bridged via `configMapRef`, and PrometheusRules
  (`CrowdSecLAPIDown`, `CrowdSecAcquisitionStalled`, `CrowdSecBouncerDown`).
- Renovate: `CrowdSec bouncer` group (chart + image lockstep) and loose versioning for the
  date-tagged Web UI image.

### Bug caught in review

- [observation] The first render mounted `/etc/crowdsec/acquis.yaml` before the
  `/etc/crowdsec` PVC, because app-template emits volumeMounts in alphabetical key order and
  the kubelet mounts them in that order — the PVC would have shadowed both ConfigMap files.
  Fixed by renaming the keys to `config`, `config-acquis`, `config-local`; re-verified in the
  rendered Deployment.

## Verification status

- [done] `kustomize build` on all four new paths plus `kubernetes/apps` — OK.
- [done] `flux-local build all kubernetes/flux/cluster --enable-helm` — exit 0; all crowdsec
  objects render, including `ReferenceGrant` (from SecurityPolicy in `networking` to Service
  `crowdsec-bouncer`) and the bouncer `config.yaml`.
- [done] `pre-commit` on every touched file — all hooks pass.
- [blocked] Nothing is deployed yet: the ExternalSecrets need two new fields in the
  1Password `crowdsec` item (`BOUNCER_API_KEY`, `WEBUI_LAPI_PASSWORD`), and the push
  awaits human approval.

## Next

Add the two 1Password fields, push, then verify in-cluster in this order:

1. `kubectl -n crowdsec get pods` — no PodSecurity admission denial (proves the whole
   namespace is restricted-clean) and no rsync/permission crashloop (proves the non-root
   entrypoint wrapper).
2. `cscli metrics` shows non-zero parsed envoy lines — the load-bearing acquisition gate.
3. `cscli bouncers list` / `cscli machines list` show `envoy` and `crowdsec-web-ui`.
4. Web UI login through Pocket ID; a non-`infra_admins` user is denied.
5. Only then propose the Gateway-level extAuth SecurityPolicy: merged into
   `envoy-internal-rfc1918` for envoy-internal (a second same-level Gateway policy would be
   `Overridden` and silently inert — live-confirmed that `envoy-internal-rfc1918` is the only
   Gateway-level policy today), separate policy for envoy-external.

## Follow-ups

- [followup] CrowdSec console enrollment via `ENROLL_KEY` (needs the `CAPI_ENROLL_TOKEN`
  1Password field verified).
- [followup] Re-evaluate `crowdsecurity/appsec-crs` with a matching appsec-config once the
  false-positive picture is known.
- [followup] VolSync for the Web UI PVC, gated on checking that the kopia mover pod satisfies
  PSS `restricted`.
- [followup] Phase 4 CAPTCHA (Cloudflare Turnstile) — untouched, still deferred.
- [followup] The `pod-security-admission-enforcement` roadmap must NOT re-label `crowdsec`;
  this roadmap owns it as `restricted`.
- [followup] mTLS to LAPI (cert-manager) as an eventual replacement for the shared API key.

## Relations

- implements [[envoy-crowdsec-bouncer]]
- relates_to [[networking]]
- relates_to [[iam]]
- relates_to [[observability]]
- relates_to [[k8s-workloads]]
- depends_on [[external-secrets]]


## Session 2 — first deploy, verification loop (2026-07-27)

Pushed and verified against the live cluster. Six defects surfaced; all but the last two
were mine. Recorded here because most of them are non-obvious consequences of the non-root
decision.

### What is proven working

- [verified] **Gate 1 end-to-end.** After the parser-chain fix, real traffic through
  envoy-internal produced `Lines read 8 | Lines parsed 8 | Lines unparsed - | Lines
  whitelisted 8`. The LogsQL `copy`+`pack_json` reconstruction feeds the
  `yanis-kouidri/envoy` parser correctly. The 8 whitelisted also prove the self-ban guard:
  LAN traffic is dropped by `crowdsecurity/whitelists`.
- [verified] **restricted PSA holds.** All three pods run non-root in a `restricted`
  namespace with no admission denial.
- [verified] **Credential auto-registration.** `Local agent already registered`,
  `Machine 'crowdsec-web-ui' successfully added`; the bouncer streams decisions
  (`envoy` → `/v1/decisions/stream`) and the Web UI polls alerts. No manual cscli step.
- [verified] **Web UI OIDC is correctly wired**: `/api/auth/status` returns
  `oidcEnabled: true`, and `/api/auth/oidc/login` 302s to
  `https://idm.${PUBLIC_DOMAIN}/authorize?client_id=crowdsec-web-ui&...`, which requires a
  successful discovery — so the IdP hairpin passes the network policy.
- [verified] Console enrollment works; the engine appears under Engines after accept.

### Defect 1 — bouncer rejected by PSA (`drop: [all]` vs `ALL`)

- [evidence] `ReplicaFailure/FailedCreate`: *"violates PodSecurity restricted:v1.36:
  unrestricted capabilities (container must set securityContext.capabilities.drop=[\"ALL\"])"`.
  The kdwils chart drops capabilities as lowercase `all`; PSS matches the literal `ALL`.
- [decision] Override `securityContext.capabilities.drop: ["ALL"]`; Helm's deep merge keeps
  the chart's other values (runAsNonRoot, runAsUser 1000, readOnlyRootFilesystem).
- [observation] My "the chart is restricted-clean, only seccomp is missing" claim was wrong —
  taken from a values dump without checking the case.

### Defect 2 — missing egress FQDN blocked the hub

- [evidence] `cscli hub update: ... version.crowdsec.net ... connection timed out` → no
  `/etc/crowdsec/hub/.index.json` → crashloop.
- [decision] Enumerating endpoints was the wrong shape; allow `crowdsec.net` +
  `*.crowdsec.net` (the pocket-id MaxMind rule's idiom).

### Defect 3 — victoria-logs ingress (the only fix outside the crowdsec tree)

- [evidence] hubble: **108 × `INGRESS POLICY_DENIED` on victoria-logs-server-0:9428 from the
  crowdsec pod**, and zero egress drops on the crowdsec side — a one-sided drop at the
  destination.
- [observation] `victoria-logs`'s own CNP is ingress default-deny and listed only the
  collector on 9428. A new log consumer has to be added there; nothing in the crowdsec tree
  could have fixed it.
- [decision] One explicit `fromEndpoints` entry mirroring the collector rule.

### Defect 4 — the seeded symlinks (the deepest one)

- [evidence] `cscli collections list` emitted `Ignoring file
  /etc/crowdsec/parsers/s00-raw/syslog-logs.yaml: lstat .../hub/...: no such file or directory`
  for the entire tree → **zero parsers loaded** → 29 lines read, 0 parsed.
- [observation] `/staging/etc/crowdsec/{parsers,scenarios,collections,...}` are symlinks into
  a hub tree whose files are 0600 root. uid 1000 copies the links but not their targets, so
  the seeded tree dangles and crowdsec discards all of it.
- [evidence] A second variant then appeared: `unable to open GeoLite2-City.mmdb: permission
  denied` — `/var/lib/crowdsec/data` links into /staging whose targets *exist* but are
  unreadable, so a broken-link test missed them.
- [decision] Unified both into ONE predicate instead of two special cases: drop every seeded
  symlink uid 1000 cannot read (`find … -type l -exec sh -c 'test -r "$1" || rm -f "$1"' _ {} \;`),
  and let cscli fetch the real items. `test -r` fails for dangling and unreadable alike;
  verified in the image that it drops both and keeps working links. busybox find has no
  `-xtype`, which the first attempt assumed.

### Defect 5 — the envoy collection does not pull the parser chain's root

- [observation] `yanis-kouidri/envoy` pulls only `envoy-logs` + `base-http-scenarios`. The
  `crowdsecurity/syslog-logs` s00-raw `non-syslog` node is what fills `evt.Parsed.message`;
  without it the envoy parser structurally cannot match. This was in the research notes and
  I failed to carry it into the manifest.
- [decision] Explicit `PARSERS`: `syslog-logs dateparse-enrich geoip-enrich whitelists`.
  `whitelists` also had to become explicit — the "it ships in the image so no self-ban config
  is needed" claim was true in principle but false in this deployment, because of defect 4.

### Defect 6 — Web UI metrics page (and its hidden CNP half)

- [evidence] UI: *"Metrics are disabled because no metrics endpoint is configured."* The
  engine already runs `prometheus.level: full`; only `CONFIG_INSTANCE_METRICS_URL` was missing.
- [observation] The URL alone would still have timed out: metrics are on 6060 while the
  crowdsec CNP allowed the Web UI only 8080. Fixed both together.

### Not a defect — the empty Web UI and the setup screen

- [observation] The Web UI showing no alerts/decisions is **correct**: `cscli alerts list` and
  `cscli decisions list` both report none. The only traffic so far was LAN, which the
  whitelist parser drops by design.
- [observation] The Web UI asking to create a user instead of offering SSO is upstream's
  designed first-run gate, not a misconfiguration:
  `setupRequired = authEnabled && countAuthUsers() === 0` (`server/app-auth.ts:793`) — a
  purely local check, no network involved, so no CNP can cause it. Docs: `auth.enabled: true`
  *"Requires authentication and initial administrator setup"*.
- [followup] Manual, one-time: create the initial admin, log in via Pocket ID, then
  **disable password login** in Settings — otherwise a local password account persists,
  contradicting the "only Pocket ID infra_admins" intent. Register a passkey first as a
  lockout fallback.

### Console enrollment (was a deferred follow-up, now done)

- [evidence] `Machine is not enrolled in the console, can't synchronize with the console`.
  CAPI registration happens on its own (that is what pulls the community blocklist) but does
  NOT list the instance under Engines — enrollment does.
- [decision] `ENROLL_KEY` from the 1Password `crowdsec` item. Safe to run every start:
  already-enrolled logs a warning and returns nil (`cliconsole/console.go:104`). Pulled via an
  explicit `remoteRef`, not the `extract` template, so a missing field fails the
  ExternalSecret loudly instead of handing `cscli console enroll` a `<no value>` — which would
  abort the entrypoint under `set -e`.

### Commits

`cd7ab20c2` (initial) → `f998b5416` (PSA + hub FQDN) → `418a598ed` (victoria-logs ingress)
→ `dfbba6828` (parser chain) → `58d24cf9a` (unreadable symlinks) → `4e9c3a735` (console
enrollment) → `764bbe76f` (Web UI metrics).

### Still open

- [followup] Manual Web UI admin setup + disable password login (see above).
- [followup] Verify the metrics page renders after the last push.
- [followup] The Gateway-level extAuth SecurityPolicy — unchanged, still gated on approval.


## Session 3 — bouncer wiring, both gateways (2026-07-27/28)

Stage 1 and Stage 2 are live and verified. Two findings here matter beyond crowdsec.

### Finding A — bodyToExtAuth caps every upload at 64KB (live regression, caused and fixed)

- [evidence] CRD, verbatim: *"Envoy will return HTTP 413 and will not initiate the
  authorization process when buffer reaches the number set in this field. Note that this
  setting will have precedence over failOpen mode."* There is no partial-message option in
  the EG API.
- [evidence] Measured on the live gateway minutes after Stage 1 landed: a 1KB POST to
  grafana returned 401 (reached the backend), a **133KB POST returned 413**.
- [observation] Every upload path on envoy-internal was in scope — pingvin-share, paperless,
  calibre, grafana dashboard imports — because none of them carries a route-level policy.
  It went unnoticed only because nobody uploaded anything in that window. With mergeType
  (finding B) qbittorrent's torrent upload would have joined them.
- [decision] Drop `bodyToExtAuth` from both policies. Raising the cap only moves the cliff.
  The WAF keeps URL/query/path/header coverage; IP bans and the CAPI blocklist are untouched.
- [decision] This **reverses the roadmap's "Phase 1 full WAF" locked decision**. The cost
  accepted there was "a 64KB buffer and a bouncer round-trip per request" — not "uploads over
  64KB fail". Same decision, different facts.
- [verified] After the fix the 133KB POST returns 401 again, matching the 1KB control.

### Finding B — route-level OIDC policies were silently excluding the Gateway policy

- [evidence] After attaching Stage 1 the policy reported
  `Overridden=True: This policy is being overridden by other securityPolicies for these
  routes: [downloads/bazarr … kube-system/hubble-ui networking/echo-server]` — all ten
  gateway-oidc consumers.
- [evidence] CRD on `mergeType`: *"If unset, no merging occurs, and only the most specific
  configuration takes effect."* The component set no `mergeType`.
- [observation] **Pre-existing security gap, independent of crowdsec**: the
  `envoy-internal-rfc1918` LAN allowlist had therefore never applied to any OIDC-gated route.
  Not exploitable in practice (envoy-internal is only reachable on a LAN VIP, plus the Cilium
  CNPs), but the policy did not do what its name and the networking guide imply.
- [observation] This **disproves the roadmap's central wiring claim** that a Gateway-level
  extAuth and a route-level oidc "combine cleanly — different level, different feature", and
  its supporting claim that rfc1918 + oidc already coexisted that way. They did not.
- [decision] `mergeType: StrategicMerge` in `kubernetes/components/gateway-oidc/securitypolicy.yaml`
  — one line in the shared component, closing the crowdsec gap and the rfc1918 gap together
  for all ten apps.
- [verified] The condition flipped `Overridden=True` → **`Merged=True`** for all ten routes.

### Stage 2 — envoy-external

- [decision] A standalone Gateway-level policy (`envoy-external-crowdsec`); correct there
  because envoy-external carries no other Gateway-level policy to merge into. It also covers
  the Pocket ID login page, which has no route-level gate by nature.
- [verified] `Accepted=True`, `Merged=True` for networking/echo-server.

### Live verification

- [verified] `bouncer_requests_total{action="allow"}` rose 173 → 3835 once both gateways were
  attached; three requests to OIDC-gated hosts moved it by exactly +3, proving the merged
  routes traverse the bouncer.
- [verified] `bouncer_waf_requests_total 3812`, `bouncer_waf_errors_total 0`,
  `bouncer_decision_cache_size{origin="CAPI"} 14998`, `bouncer_lapi_stream_connected 1`.
- [verified] **Zero bans on legitimate traffic** — no `action="ban"` counter, and
  `cscli decisions list` / `alerts list` are empty. No false positives so far.
- [verified] OIDC still works through the merge: subs/bt/hubble/echo all 302 to
  `idm.${PUBLIC_DOMAIN}/authorize` with a PKCE `code_challenge`.
- [verified] Upload regression gone (133KB POST → 401).

### Commits

`50814b79b` (Stage 1) → `6d2c00f98` (413 regression fix) → `ee0990fd3` (mergeType + Stage 2).

### Remaining

- [followup] Web UI: create the initial admin, log in via Pocket ID, register a passkey,
  then disable password login. Manual and unavoidable — upstream gates SSO behind
  initial-administrator setup (`setupRequired`, a purely local check).
- [followup] Soak: watch `bouncer_requests_total{action="ban"}` and the CrowdSec Console for
  false positives now that ~15k CAPI decisions are enforced on the public edge.
- [followup] Update `docs/areas/networking` — the gateway-policy inventory now includes the
  merged envoy-internal policy and `envoy-external-crowdsec`, and the mergeType semantics are
  worth recording there since they contradict the previous mental model.
- [followup] Body-based WAF detection is now absent; the AppSec collections only see
  URL/headers. Revisit only if EG gains a partial-message option.
- [followup] Unchanged from before: console `ENROLL_KEY` is wired, appsec-crs still out,
  VolSync for the Web UI PVC still pending a PSA-restricted check on the kopia mover.

## Session 4 — close-out: down-alert fix, soak, follow-up resolution (2026-07-28)

Roadmap item closed with the human. Core (Phase 0–3) is live and verified; every
remaining follow-up is resolved below — implemented, or explicitly dropped with
rationale. This supersedes the "Follow-ups" section above.

### Committed this session (down-alert hardening)

- [done] `CrowdSecBouncerDown` and `CrowdSecLAPIDown` PrometheusRules fixed:
  `up{...} == 0` only fires on a failed scrape, not when the target vanishes
  (scale-to-0 / crashloop / readiness-split drops the series). Changed to
  `up{...} == 0 or absent(up{...})` on both. End-to-end tested 2026-07-28: both
  deployments scaled to 0 → alerts went pending→firing → Alertmanager
  `state=active` → Pushover (critical route); restored → both cleared
  (`send_resolved`).
- [done] `EnvoyProxyDown` PrometheusRule (new, networking ns,
  `envoy-gateway/config/prometheusrule.yaml`): the envoy proxies are the data
  plane (envoy-external public, envoy-internal LAN, one replica each, one
  PodMonitor job `networking/envoy-proxy`). Expr
  `count(up{job="networking/envoy-proxy",namespace="networking"} == 1) < 2`
  covers one-down, both-down, scrape failure, and all-vanished; `for: 2m` skips
  a rolling-update blip on the single replica. The envoy-gateway controller
  (control plane) is a separate ServiceMonitor and is not covered here.
- [done] Self-ban test cleanup: the two manual/web-ui bans (192.168.1.100
  self-ban + one IPv6) have expired; `cscli decisions list` = "No active
  decisions".
- [observation] Commits on main: `be6982769` (crowdsec alert absent fix),
  `572d4787f` (EnvoyProxyDown rule), `929b664f4` (docs). The area-level
  record is in [[networking]] (2026-07-28 update).

### Soak verification (live, 2026-07-28)

- [verified] All three pods Running, 0 restarts (12–20h uptime).
- [verified] `bouncer_requests_total` `sum by (action)` returns ONLY
  `allow` = 1106 — there is no `action="ban"` series at all, i.e. ZERO bans
  since the bouncer started.
- [verified] `bouncer_waf_requests_total{action="allow"}` = 1103 (WAF
  inspected, all allowed); `bouncer_decision_cache_size{origin="CAPI"}`
  = 19956 (~20k community blocklist decisions enforced on the public edge);
  `origin="cscli"` = 0 (no local decisions); `bouncer_lapi_stream_connected`
  = 1.
- [verified] `cscli alerts list` shows only the two expired manual test bans;
  no automated false-positive bans. Clean soak — ~20k CAPI decisions enforced,
  zero false positives.

### Follow-up resolution (closed 2026-07-28 with human)

- [dropped] **VolSync for the Web UI PVC.** CrowdSec state is disposable
  (credentials re-register from env, decisions repopulate from CAPI + fresh
  detections); the kopia mover's PSA `restricted` compatibility is unverified
  and could silently break backups. Web UI SQLite alert history is acceptable to
  lose (alerts also live in the CrowdSec Console + `cscli alerts list`).
- [dropped] **Body-based WAF detection.** `bodyToExtAuth` is removed (it
  413-capped every upload over 64 KB — a live regression, reversed the
  roadmap's "Phase 1 full WAF" decision). AppSec keeps URL/query/path/header
  coverage. Revisit only if Envoy Gateway gains a partial-message extAuth
  option — not on the EG roadmap.
- [dropped] **`crowdsecurity/appsec-crs` re-evaluation.** CRS is inert without
  a referencing appsec-config, is a known false-positive source, and with
  `bodyToExtAuth` gone its body-oriented rules (SQLi/XSS in POST bodies) are
  doubly inert. Not worth re-evaluating.
- [dropped] **mTLS to LAPI (cert-manager).** Viable technically (cert-manager
  is in-cluster; CrowdSec LAPI supports TLS + client-cert auth), but the LAPI
  is in-cluster-only behind a CNP (bouncer/web-ui/prometheus + kubelet only):
  an in-cluster adversary who can read the bouncer's env can read a mounted
  cert too, so mTLS doesn't materially raise the bar against the realistic
  threat. The only real gain is rotation hygiene, which does not justify the
  cert-manager wiring across three workloads + chart-support verification.
  Shared API key (ESO-delivered, idempotent re-registration) stays.
- [dropped] **Phase 4 CAPTCHA (Cloudflare Turnstile).** Turnstile itself is
  free, unlimited, and does NOT require the site to be on Cloudflare's
  proxy/DNS (works on any origin; a free Cloudflare account provides the
  site/secret key). Dropped because (a) the bouncer is wired as gRPC extAuth
  and the chart's CAPTCHA flow (a `/captcha` HTTPRoute + HTML challenge) is
  unverified in that mode, and (b) the threat model is thin: the bouncer has
  zero bans, body-WAF is gone, and only hard-deny rules remain (URL/header WAF
  + IP-ban + CAPI blocklist) — there is little "suspicious" traffic to
  soft-challenge. Revisit only if soft-challenge becomes wanted AND chart
  extAuth-captcha support is confirmed.
- [done] **Console enrollment** (`ENROLL_KEY`) — wired in Session 2.
- [done] **`docs/areas/networking` update** — already current (three
  2026-07-28 updates record the merged `envoy-internal-rfc1918` policy,
  `envoy-external-crowdsec`, `mergeType` semantics, the `bodyToExtAuth` 413
  finding, the rate-limit per-client bucket fix, and the down-alert fix).

### Close

- [observation] Roadmap [[envoy-crowdsec-bouncer]] closed: Phase 0–3
  implemented and live; Phase 4 + every follow-up above dropped with rationale.
  No open work remains.

## Archived roadmap — design reference

Merged here from `docs/roadmap/envoy-crowdsec-bouncer` on 2026-07-28 when the roadmap item closed and the roadmap note was deleted. Preserved as the historical design reference; the execution log lives in the sessions above.

### Original roadmap frontmatter

```yaml
title: envoy-crowdsec-bouncer
type: note
permalink: envoy-crowdsec-bouncer
status: done
priority: medium
tags:
- networking
- security
- crowdsec
```

### Original roadmap body

# Envoy CrowdSec Bouncer + Web UI Integration

Integrate CrowdSec (detection + decisions) with the Envoy Gateway edge via the
`envoy-proxy-bouncer` as a native `SecurityPolicy.extAuth` service, and deploy the
self-hosted CrowdSec Web UI (TheDuffman85) for alert/decision visibility. Scope expanded
from the bouncer-only original to cover the Web UI per the 2026-07-27 research sweep.

Revised 2026-07-27 after a review against the live repo, the BM area-references, and
EG 1.8.3 docs, then re-verified against the chart sources and the live cluster; follow-ups
resolved with the human 2026-07-27 — see "Review correction log" at the end for the change set.

## Goal

- Automate blocking of malicious actors at the Envoy Gateway edge (IP-ban + AppSec WAF),
  reducing attack surface for every backend application behind `envoy-external`/`envoy-internal`.
- Add a self-hosted, OIDC-protected dashboard (CrowdSec Web UI) for alert/decision
  investigation, historical retention, and notifications — LAN-only, Pocket ID auth.

## Research basis (evidence-backed)

Surveyed two reference homelabs + the Web UI repo + the bouncer chart repo (all via `gh`
on 2026-07-27, this branch). Versions current as of the sweep.

- **artichoked1/homelab** — Envoy Gateway stack (closest to this repo's log source).
  CrowdSec chart 0.24.0, PostgreSQL backend, `agent.acquisition` reads Envoy pod stdout
  logs (`podName: envoy-networking-web-gateway-*`, `program: envoy`,
  `poll_without_inotify: true`) with `COLLECTIONS: yanis-kouidri/envoy`. Bouncer chart
  0.5.5, `referenceGrant.create: true` for cross-namespace SecurityPolicy refs.
  AppSec enabled (`crowdsecurity/appsec-virtual-patching`).
- **aclerici38/home-ops** — kgateway (not EG), but the most complete reference.
  CrowdSec chart 0.24.0 (OCI `ghcr.io/crowdsecurity/helm-charts/crowdsec`), CloudNativePG,
  LAPI 2 replicas + Cilium L2 LoadBalancer, syslog acquisition (OPNsense/pf), AppSec
  enabled (`appsec-virtual-patching appsec-crs appsec-generic-rules`), Grafana dashboard
  21689. Web UI: bjw-s app-template, image `ghcr.io/theduffman85/crowdsec-web-ui`,
  **built-in OIDC** (`CONFIG_AUTH_OIDC_*`, Pocket ID, `unmatchedRole: deny`,
  `adminGroups: [admin]`), PVC `/app/data` (SQLite), internal-only route.
  Bouncer: kdwils chart 0.6.3, gRPC 8080, WAF to `crowdsec-appsec-service:7422`.
- **TheDuffman85/crowdsec-web-ui** (451 stars, TypeScript/React+Hono, image tagged by date
  e.g. `2026.7.21`). Built-in auth (password+TOTP, passkeys, **OIDC SSO**), group roles,
  read-only mode, multi-instance, Prometheus metrics page, notifications
  (Email/Gotify/MQTT/ntfy/Webhook), SQLite retention under `/app/data`. **The corelab.tech
  guide's "no built-in auth" warning is outdated** — current images have full auth.
  Health probe `GET /api/health` (public). Gotcha: the Web UI network must be in CrowdSec
  `api.server.trusted_ips` for delete/clean operations (403 otherwise). `zekker6` Helm
  chart is **stale** (old `CROWDSEC_URL` env names vs the image's `CONFIG_*` contract) —
  use bjw-s app-template with correct `CONFIG_*` envs instead.
- **kdwils/envoy-proxy-crowdsec-bouncer** (chart latest 0.7.0). Integrates with Envoy
  Gateway via the **native `SecurityPolicy.extAuth.grpc.backendRefs`** API — NOT
  `EnvoyPatchPolicy`. Per the chart author's DEPLOYMENT.md: "SecurityPolicies must be
  created at the HTTPRoute level, not at the Gateway level, and in the same namespace as
  your HTTPRoutes." — this is a *blast-radius recommendation*, not a hard EG constraint;
  Gateway-level `SecurityPolicy` is supported by EG and is already used in this repo for
  `envoy-internal-rfc1918`. We intentionally override it for the Gateway-level bouncer
  (see Decisions). `bodyToExtAuth.maxRequestBytes: 65536` is required to forward the
  request body for WAF inspection of POST payloads (without it, WAF only sees URL/path).
  `ReferenceGrant` needed for cross-namespace Service refs (chart auto-creates via
  `referenceGrant.create` + `fromNamespaces`). Bouncer exposes no health endpoint.
  **Verified 2026-07-27 against the chart sources**: the chart ships NO SecurityPolicy
  template (templates dir: `deployment`, `service`, `referencegrant`, `httproute`,
  `servicemonitor`, `serviceaccount`, `hpa`, `configmap-*` only) — there is no
  `securityPolicy` value, so nothing to disable; we hand-write the SecurityPolicy. Value
  keys confirmed: `config.bouncer.lapiURL` (default `http://crowdsec-service:8080`),
  `config.bouncer.apiKeySecretRef`, `config.waf.enabled`/`config.waf.appSecURL` (capital S,
  default `http://crowdsec-appsec-service:7422`), `referenceGrant.create`/`fromNamespaces`.
  The bouncer Service name is `{{ include "envoy-proxy-bouncer.fullname" }}` — set
  `fullnameOverride: crowdsec-bouncer` so it renders as `crowdsec-bouncer` (without the
  override, release `crowdsec-bouncer` would render `crowdsec-bouncer-envoy-proxy-bouncer`).

## Decisions (locked with human, 2026-07-27)

Locked with human 2026-07-27; bouncer-wiring revised the same day after a review against
the live repo + EG 1.8.3 docs (see "Review correction log" at the end).

- [decision] **Bouncer wiring**: native `SecurityPolicy.extAuth.grpc` attached at **Gateway
  level** (`Gateway/envoy-external`, plus a separate policy for `Gateway/envoy-internal` in
  Stage 1), mirroring the existing `envoy-internal-rfc1918` Gateway-level authorization
  policy — **NOT** a per-route SecurityPolicy and **NOT** `EnvoyPatchPolicy + ext_authz`.
  Rationale: EG does NOT merge multiple SecurityPolicies at the same hierarchy level on the
  same target — a second route-level `extAuth` policy would `Accepted=False / Conflicted`
  against the existing route-level `oidc` policy from the `gateway-oidc` component. A
  Gateway-level (parent) `extAuth` policy combines cleanly with a route-level (child) `oidc`
  policy: different level, different feature -> both apply (this is exactly how the existing
  `envoy-internal-rfc1918` Gateway-level authorization + route-level `oidc` already coexist in
  EG 1.8.3). Filter order is `ext_authz -> oidc`, so banned IPs get 403 before reaching the
  Pocket ID OIDC login flow. `bodyToExtAuth.maxRequestBytes: 65536` forwards the request body
  for WAF inspection of POST payloads. The SecurityPolicy lives in the `networking` namespace
  (same ns as the Gateway target, alongside `rfc1918`); the ReferenceGrant in the `crowdsec`
  namespace allows `networking` to reference the bouncer Service. **This is what preserves
  Pocket ID OIDC.**
- [decision] **Gateway-level tradeoff accepted**: Gateway-level attachment loses the per-route
  incremental rollout the original plan wanted — the bouncer protects *all* routes on the
  gateway at once. Mitigation: 2-stage rollout — apply the bouncer SecurityPolicy on
  `Gateway/envoy-internal` first (LAN only; blast radius is LAN users, and `rfc1918` already
  IP-allowlists that gateway), verify no 403-storm on legitimate traffic, then apply on
  `Gateway/envoy-external`. The bouncer SPOF (single replica, fail-closed) now spans the whole
  gateway instead of one route — accepted; the bouncer-down Prometheus alert is therefore critical.
- [decision] **failOpen: false** (fail-closed), security-first. Reverses the original
  roadmap's `fail_closed: false` (Availability > Security). If the bouncer is unavailable,
  Envoy denies (5xx) — the security check always runs. **Human accepted the implication**:
  the bouncer is a hard SPOF; its outage blocks all routes on the gateway it is attached to.
  **No HA**: single replica (human declined bouncer HA). Security > Availability applied literally.
- [decision] **Phase 1 full WAF**: `bodyToExtAuth.maxRequestBytes: 65536` + AppSec collections
  (`crowdsecurity/appsec-virtual-patching`, `crowdsecurity/appsec-crs`,
  `crowdsecurity/appsec-generic-rules`) from day 1. Cost: every protected request *with a body*
  buffers up to 64KB and makes a bouncer round-trip; with fail-closed the bouncer is on the
  critical path with no bypass. Accepted.
- [decision] **Web UI auth**: app-level OIDC via Pocket ID (the Web UI's **built-in OIDC**,
  `CONFIG_AUTH_OIDC_*`), NOT the `gateway-oidc` SecurityPolicy gate (that would double-gate).
  The Web UI does app-level OIDC itself, exactly like grafana. `adminGroups` +
  `unmatchedRole: deny`. A Pocket ID client (`crowdsec-web-ui`) is provisioned via the
  Terraform pocket-id module, `gate: native` style like the `grafana` client — NOT
  `gate: envoy`, since the Web UI does app-level OIDC.
- [decision] **Web UI exposure**: internal-only (`envoy-internal` HTTPRoute), LAN-only, never
  `envoy-external`. Matches the grafana LAN-only precedent (`grafana.${PUBLIC_DOMAIN}` on
  `envoy-internal`).
- [decision] **No external DB**: CrowdSec LAPI state on SQLite (single-node, no CNPG in this
  repo — verified); Web UI SQLite under `/app/data`. Both on local-hostpath PVCs via
  `democratic-csi-local-hostpath`. Reaffirms the original roadmap's SQLite choice.
- [decision] **Log acquisition**: read Envoy JSON access logs from the Envoy proxy pods'
  stdout via the crowdsec agent (artichoked1 pattern). The repo already emits JSON access
  logs to `/dev/stdout` (`envoy.yaml` `telemetry.accessLog` with `downstream_remote_address`
  + `x_forwarded_for`), so the agent reads `/var/log/pods/...` with
  `COLLECTIONS: yanis-kouidri/envoy` + program `envoy`. Client IP detection already handled
  by `ClientTrafficPolicy` (CF-Connecting-IP via `customHeader` on `envoy-external`,
  `xForwardedFor.numTrustedHops: 0` on `envoy-internal`).
- [decision] **Web UI deployment**: bjw-s app-template (repo idiom, ~27 uses) with the
  correct `CONFIG_*` env contract, NOT the stale zekker6 chart.
- [decision] **Geo-enrichment**: MaxMind GeoLite2 via 1Password, reusing the repo's EXISTING
  `maxmind` 1Password item (already consumed by pocket-id). No new 1Password item, no
  plaintext key. ExternalSecret + CNP follow the pocket-id pattern (see Phase 1).
- [decision] **Generated credentials stay out of 1Password**: the bouncer API key, the agent
  registration token, and the Web UI's LAPI machine credential are GENERATED by the
  crowdsec chart / LAPI into K8s Secrets (referenced via `secretKeyRef`), not pre-created in
  1Password. Only externally-sourced secrets go to 1Password: the CAPI enroll token (from
  the CrowdSec Console), the MaxMind key (existing), the Web UI OIDC client secret (in the
  shared `pocket-id-clients` item).

## Execution plan (research-backed)

### Current state

- Greenfield: `grep -ril crowdsec kubernetes/ provision/` returns nothing (the Pocket ID
  client entry in `provision/pocket-id/clients.yaml` is the only crowdsec artifact yet).
- No CloudNativePG / postgres operator in the repo -> SQLite is the correct backend.
- Envoy Gateway already emits JSON access logs to stdout (`envoy.yaml`), so the detection
  feed is wired — only acquisition needs adding.
- `SecurityPolicy` is an established API in the repo (`gateway-oidc` component is route-level
  `oidc`; `envoy-internal-rfc1918` is a Gateway-level `authorization` policy — the latter is
  the pattern the bouncer reuses). `EnvoyPatchPolicy` is used only for compressor tuning —
  the bouncer will NOT use it.
- ESO + `onepassword-connect` ClusterSecretStore is the secret channel for the externally-
  sourced secrets only (CAPI enroll token, MaxMind key, Web UI OIDC client secret). The
  chart-generated credentials (bouncer API key, agent registration token, Web UI LAPI
  machine credential) live in K8s Secrets, not 1Password.
- The `maxmind` 1Password item + MaxMind GeoLite2 egress CNP pattern already exist for
  pocket-id (`kubernetes/apps/security/pocket-id/app/externalsecret.yaml`,
  `ciliumnetworkpolicy.yaml`) — reuse for CrowdSec geoip.
- The `crowdsec-web-ui` Pocket ID client already exists in `provision/pocket-id/clients.yaml`
  (key `crowdsec-web-ui`, `gate: native`, `subdomain: crowdsec`, `groups: [infra_admins]`,
  `callback_path: /api/auth/oidc/callback` — fixed 2026-07-27) AND is registered live
  (client_id `crowdsec-web-ui`, secret in `pocket-id-clients`/`crowdsec-web-ui_client_secret`,
  confirmed 2026-07-27).

### Phase 0 — Namespace + secrets

- Create `crowdsec` namespace (Flux Kustomization + Namespace). Do NOT add a
  `pod-security.kubernetes.io/enforce` label: PSA is not enforced anywhere in this repo
  (the Talos config only disables legacy PSP — `kubernetes/talos/machineconfig.yaml.j2`),
  and PSS `baseline` would *forbid* the `hostPath` `/var/log` mount the agent needs for
  `hostVarLog` log acquisition. Match the repo idiom (no PSA label). The hostPath requirement
  and the `crowdsec` namespace's eventual PSA profile are owned by the separate
  `pod-security-admission-enforcement` roadmap — coordinate there, do not pre-empt it here.
- 1Password items (only what is NOT generated by the chart/LAPI):
  - **`crowdsec`** — CAPI enroll token, field `CAPI_ENROLL_TOKEN` (created 2026-07-27; see
    CAPI followup).
  - **`pocket-id-clients`** (existing) — field `crowdsec-web-ui_client_secret` = the Web UI
    OIDC client secret (synced by `just pocket-id apply`, confirmed present 2026-07-27). The
    Web UI ExternalSecret reads from this shared item, same idiom as grafana.
  - **`maxmind`** (existing) — `MAXMIND_LICENSE_KEY`, reused for geoip (no new item).
  - The bouncer API key, the agent registration token, and the Web UI's LAPI machine
    credential are GENERATED by the chart/LAPI into K8s Secrets (referenced via
    `secretKeyRef`, NOT ESO from 1P) — verify the exact chart mechanism at Phase 1.
  - ExternalSecrets bound to `onepassword-connect`.

### Phase 1 — Engine + bouncer (the core)

- `kubernetes/apps/crowdsec/app/`: HelmRelease for the crowdsec OCI chart 0.24.0
  (`oci://ghcr.io/crowdsecurity/helm-charts/crowdsec`), digest-pinned via OCIRepository.
  Values: SQLite backend (no `db_config` override -> the container's default file SQLite
  applies); LAPI single replica (single-node); `lapi.storeCAPICredentialsInSecret: true`;
  set `api.server.trusted_ips` via the chart's `config.yaml.local` override (it is not a flat
  values key) to `[10.0.0.0/8, ${LAN_SUBNET}]` (covers the Web UI's delete-ops requirement:
  Web UI pod IPs are in `${POD_CIDR}` ⊂ 10.0.0.0/8; `10.0.0.0/8` also covers `${SVC_CIDR}`;
  `${LAN_SUBNET}` covers node + LAN); `auto_registration.enabled: true` with token for the
  agent (the chart's default `auto_registration.allowed_ranges` already includes
  `10.0.0.0/8` and `192.168.0.0/16`); postoverflow whitelist of own infra (`10.0.0.0/8` —
  covers `${POD_CIDR}` + `${SVC_CIDR}` — plus `${LAN_SUBNET}` for node + LAN) so the cluster
  never bans itself.
- Agent acquisition: read Envoy proxy pod logs
  (`podName: envoy-external-*`, `envoy-internal-*`, `program: envoy`,
  `poll_without_inotify: true`), `COLLECTIONS: yanis-kouidri/envoy`. (`hostVarLog: true` is the
  chart default -> the agent mounts hostPath `/var/log`; requires hostPath — see Phase 0 note.)
  EG 1.8.3 names the managed envoy pods `envoy-{gateway-name}-{hash}` — verified live
  2026-07-27: `envoy-external-5dd8db458d-ldpv5`, `envoy-internal-64c94974-rkctk` in the
  `networking` namespace (no `networking-` segment in the pod name, no double `envoy-`
  prefix). The EG controller pod `envoy-gateway-*` is excluded by the `program: envoy` filter
  (it runs the gateway controller binary, not envoy).
- AppSec: `appsec.enabled: true` + `appsec.acquisitions` (`source: appsec`,
  `listen_addr: 0.0.0.0:7422`, `appsec_config: crowdsecurity/appsec-default`) + collections
  `crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-crs crowdsecurity/appsec-generic-rules`.
  None of these are chart defaults (the chart's `appsec.enabled` defaults to false and 7422
  is only a commented example) — all explicit.
- Geo-enrichment: a crowdsec-namespace `ExternalSecret` reusing the existing `maxmind`
  1Password item — `dataFrom.extract.key: maxmind` -> `MAXMIND_LICENSE_KEY` — following the
  pocket-id ExternalSecret pattern (`kubernetes/apps/security/pocket-id/app/externalsecret.yaml`).
  Wire the key into the crowdsec geoip enrichment config. The crowdsec namespace CNP allows
  the MaxMind GeoLite2 egress (copy the pocket-id CNP egress rule: `download.maxmind.com`,
  `*.maxmind.com`, `mm-prod-geoip-databases.a2649acb697e2c09b632799562c076f2.r2.cloudflarestorage.com:443`
  — `kubernetes/apps/security/pocket-id/app/ciliumnetworkpolicy.yaml`).
- `kubernetes/apps/crowdsec/bouncer/`: HelmRelease for kdwils chart 0.7.0
  (`oci://ghcr.io/kdwils/charts/envoy-proxy-bouncer`), single replica, gRPC 8080.
  **`fullnameOverride: crowdsec-bouncer`** so the Service is `crowdsec-bouncer` (the chart's
  Service name is `{{ include "envoy-proxy-bouncer.fullname" }}`; without the override the
  release `crowdsec-bouncer` would render as `crowdsec-bouncer-envoy-proxy-bouncer`).
  `config.bouncer.lapiURL: http://crowdsec-service.crowdsec.svc:8080` + apiKeySecretRef (ESO),
  `config.waf.enabled: true` + `config.waf.appSecURL: http://crowdsec-appsec-service.crowdsec.svc:7422`,
  `config.trustedProxies` + `exemptIPs` = `10.0.0.0/8` + `${LAN_SUBNET}`,
  `referenceGrant.create: true`, `referenceGrant.fromNamespaces: [networking]`. The kdwils
  chart ships **no SecurityPolicy template** (verified 2026-07-27) — there is no
  `securityPolicy` value to disable; we hand-write the Gateway-level SecurityPolicy in the
  envoy-gateway config (alongside `envoy-internal-rfc1918`). Prometheus + ServiceMonitor
  enabled. (Chart value keys + service names verified 2026-07-27 against the chart sources.)
- Gateway-level `SecurityPolicy` in `kubernetes/apps/networking/envoy-gateway/config/` (same
  file pattern as `gateway-policies.yaml`, namespace `networking`):
  `extAuth.grpc.backendRefs -> crowdsec-bouncer.crowdsec.svc:8080` (matches the bouncer
  chart's Service with `fullnameOverride: crowdsec-bouncer`), `failOpen: false`,
  `bodyToExtAuth.maxRequestBytes: 65536`, `targetRefs -> Gateway/envoy-external` (and a
  second policy `targetRefs -> Gateway/envoy-internal` for Stage 1). The cross-namespace
  backendRef (networking -> crowdsec) is permitted by the ReferenceGrant the bouncer chart
  creates in the `crowdsec` namespace with `fromNamespaces: [networking]`.
- 2-stage rollout: (1) apply the `Gateway/envoy-internal` bouncer policy first — LAN-only,
  blast radius is LAN, `rfc1918` already IP-allowlists; verify no 403-storm on legitimate LAN
  traffic; (2) apply the `Gateway/envoy-external` policy. There is no finer-grained per-route
  rollout under Gateway-level attachment — this 2-stage is the coarsest safety step.

### Phase 2 — Web UI

- `kubernetes/apps/crowdsec/web-ui/`: bjw-s app-template HelmRelease, image
  `ghcr.io/theduffman85/crowdsec-web-ui:<date-tag>@sha256:...digest`. Env (verified against
  the Web UI repo README `server/app-auth.ts` 2026-07-27):
  `CONFIG_INSTANCE_LAPI_URL: http://crowdsec-service.crowdsec.svc:8080`,
  `CONFIG_INSTANCE_LAPI_AUTH_USERNAME: crowdsec-web-ui` + password secretKeyRef (the LAPI
  machine credential generated by the chart/LAPI into a K8s Secret — NOT 1Password; see
  Phase 0), `CONFIG_AUTH_OIDC_ISSUER_URL: https://idm.${PUBLIC_DOMAIN}` + client_id/secret
  (ESO from the `pocket-id-clients` item, field `crowdsec-web-ui_client_secret`),
  `CONFIG_AUTH_OIDC_SCOPE: openid profile email groups`, `CONFIG_AUTH_OIDC_GROUPS_CLAIM:
  groups`, `CONFIG_AUTH_OIDC_ADMIN_GROUPS_0: infra_admins` (the Pocket ID client's `groups:
  [infra_admins]` — same admin group as grafana), `CONFIG_AUTH_OIDC_UNMATCHED_ROLE: deny`.
  Probes on `/api/health:3000`. readOnlyRootFS, runAsNonRoot, seccomp RuntimeDefault.
  Persistence: local-hostpath PVC at `/app/data` (SQLite + WAL — mount the directory, not
  just the db file). HTTPRoute on `envoy-internal` only (LAN-only), hostname
  `crowdsec.${PUBLIC_DOMAIN}` (matches the grafana LAN-only precedent — `${PRIVATE_DOMAIN}`
  does not exist as a Flux var; `home.arpa` is not a repo pattern). **No `gateway-oidc`
  SecurityPolicy on this route** — the Web UI does its own app-level OIDC; a gateway gate
  would double-gate.
- Pocket ID client: the `crowdsec-web-ui` client already exists in
  `provision/pocket-id/clients.yaml` (key `crowdsec-web-ui`, `gate: native`, `subdomain:
  crowdsec`, `groups: [infra_admins]`, `callback_path: /api/auth/oidc/callback` — verified
  against `server/app-auth.ts:1256,1265,1296`, fixed 2026-07-27) AND is registered live
  (client_id `crowdsec-web-ui`, secret in `pocket-id-clients`/`crowdsec-web-ui_client_secret`,
  confirmed 2026-07-27). `locals.tf` derives
  `callback_url = https://crowdsec.${PUBLIC_DOMAIN}/api/auth/oidc/callback` for `gate:
  native`. PKCE stays on (the `openid-client` lib sends a challenge; `locals.tf` defaults
  `pkce_enabled: true`). **Verify the live client's callback URL** — run `just pocket-id plan`;
  if it shows a `callback_path` diff, the live client still has the pre-fix
  `/api/oauth/callback/oidc` (i.e. `apply` ran before the fix) and needs
  `just pocket-id apply` to correct it. If no diff, the live client is already correct.

### Phase 3 — Observability

- ServiceMonitors for LAPI, agent, appsec (crowdsec chart) + bouncer (kdwils chart) ->
  kube-prometheus-stack Prometheus.
- Grafana via grafana-operator (repo idiom — NOT the chart's ConfigMap-sidecar label, which
  grafana-operator does not auto-discover):
  (a) **CrowdSec dashboard 21689** — a `GrafanaDashboard` CR with `spec.url:
  https://grafana.com/api/dashboards/21689/revisions/1/download` + datasource `prometheus`
  (aclerici38 pattern; link verified 200 OK 2026-07-27). Covers LAPI/agent/appsec.
  (b) **Bouncer dashboard** — enable the chart's `grafana.dashboard.enabled: true` (ships
  `dashboards/bouncer.json` as a ConfigMap `<bouncer>-dashboard`), then bridge it to
  grafana-operator with a `GrafanaDashboard` CR using `configMapRef` to that ConfigMap (the
  `GrafanaDashboard` field is `configMapRef` — there is no `contentFrom` wrapper; see
  `kubernetes/apps/observability/victoria-logs/app/grafanadashboard.yaml` for the pattern).
  The operator watches CRs, not the `grafana_dashboard: "1"` sidecar label.
- Alerts (human-confirmed required 2026-07-27): (1) bouncer pod unavailable / 5xx spike on
  the attached gateway — **critical under fail-closed** (means all routes on that gateway
  are 5xx-ing); (2) `crowdsec_decisions_total` surge; (3) LAPI down. Wire to Pushover
  (existing alerting channel). The bouncer-down alert is the operational cost of the
  security-first fail-closed + Gateway-level choice — include a runbook for the gateway-wide
  5xx behavior.
- Web UI built-in notifications -> webhook to Pushover for Alert-Spike / IP-Ban /
  LAPI-Availability rules (the Web UI's own notification system, separate from Prometheus).

### Phase 4 — CAPTCHA (DROPPED 2026-07-28)

- Cloudflare Turnstile for "suspicious" IPs (kdwils chart supports Turnstile + reCAPTCHA v2).
  Needs a Turnstile site/secret key (ESO) + the bouncer's HTTPRoute for `/captcha`
  (chart `httproute.yaml` template). Implement only after Phase 1 (403 + WAF) is stable.

## Security review

- **fail-closed SPOF**: by design, the bouncer (single replica) on the critical path with no
  bypass. Bouncer outage = all routes on the attached gateway return 5xx. This is the
  security-first tradeoff the human accepted (and the Gateway-level choice widens it from
  per-route to per-gateway). The bouncer-down Prometheus alert is therefore critical.
- **Trusted IPs gotcha**: the Web UI pod IP range must be in CrowdSec `api.server.trusted_ips`
  for delete/clean IP operations (else 403). Covered by `10.0.0.0/8` (Web UI pods are in
  `${POD_CIDR}` ⊂ 10.0.0.0/8).
- **Self-ban guard**: postoverflow whitelist of own infra (`10.0.0.0/8` covers `${POD_CIDR}` +
  `${SVC_CIDR}`; `${LAN_SUBNET}` covers node + LAN) so CrowdSec never bans the cluster's own
  probes/healthchecks/egress or LAN clients.
- **Secrets**: externally-sourced secrets via ESO -> 1Password (`onepassword-connect`); no
  plaintext credentials in manifests (repo non-negotiable). The MaxMind key reuses the
  existing `maxmind` item; the Web UI client secret reuses the shared `pocket-id-clients`
  item (synced by `just pocket-id apply`); the CAPI enroll token is in the `crowdsec` item.
  The chart-generated credentials (bouncer API key, agent registration token, Web UI LAPI
  machine credential) live in K8s Secrets, not 1Password.
- **CiliumNetworkPolicy**: restrict LAPI (8080) to bouncer + agent + Web UI pods only;
  restrict AppSec (7422) to bouncer only; restrict bouncer gRPC (8080) to the envoy-external /
  envoy-internal proxy pods only (select by label `app.kubernetes.io/name: envoy` +
  `gateway.envoyproxy.io/owning-gateway-name`, the repo CNP idiom — never by pod name). Deny
  everything else in the `crowdsec` namespace. Egress: allow MaxMind GeoLite2 download (copy
  the pocket-id CNP egress rule) for the geoip enrichment; allow LAPI->CAPI (the CrowdSec
  Console endpoints, only if CAPI enroll is enabled); deny other egress.
- **Client IP trust**: relies on Envoy `ClientTrafficPolicy` (`customHeader` CF-Connecting-IP
  on `envoy-external`, `xForwardedFor.numTrustedHops: 0` on `envoy-internal`) already in place
  — the bouncer reads the real client IP from the ext_authz request, not a spoofable header.
- **Web UI OIDC**: `unmatchedRole: deny` — only Pocket ID users in the admin group get
  access; no open registration. App-level auth means the Web UI route does NOT get the
  gateway-oidc SecurityPolicy (avoid double-gating).
- **IdP protection (Gateway-level consequence)**: because the bouncer is Gateway-level,
  every route on the attached gateway — including Pocket ID's own `idm.${PUBLIC_DOMAIN}` login
  page on `envoy-external` (which has no `gateway-oidc` policy, being the IdP itself) — is
  bouncer-protected automatically once the `envoy-external` policy is applied. No separate
  per-route policy is needed for the IdP.

## Resource profile (single-node, conservative)

| Component | CPU Req/Lim | RAM Req/Lim | Note |
| :--- | :--- | :--- | :--- |
| LAPI (+SQLite) | 50m / 200m | 128Mi / 256Mi | Core API + state |
| Agent (envoy logs) | 50m / 200m | 64Mi / 128Mi | Log read + parse |
| AppSec | 100m / 500m | 128Mi / 256Mi | WAF body inspect burst |
| Bouncer | 20m / 100m | 64Mi / 128Mi | gRPC ext_authz, critical path |
| Web UI | 10m / null | 64Mi / 128Mi | SQLite dashboard |

## Verification steps

- [ ] `kubectl -n crowdsec get pods` — all components healthy; LAPI + agent + appsec +
  bouncer + web-ui Running.
- [ ] `kubectl -n crowdsec exec crowdsec-... -- cscli machines list` shows the bouncer +
  web-ui watcher registered; `cscli decisions add -i 1.2.3.4` then confirm a request from
  1.2.3.4 to a protected route gets 403, and `cscli decisions delete 1.2.3.4` clears it
  (trusted_ips gotcha verified).
- [ ] `cscli metrics` shows the envoy parser ingesting envoy access logs (non-zero parsed
  lines); AppSec shows requests inspected; geoip enrichment populates country/ASN fields.
- [ ] Send a malicious POST body (e.g. `' OR 1=1 --`) to a protected route -> 403 from AppSec
  (WAF body inspect verified).
- [ ] Native-OIDC app protection: with a test ban on an IP, that IP hitting the Pocket ID
  external login (`idm.${PUBLIC_DOMAIN}`) and grafana (LAN) gets 403 — confirms the
  Gateway-level bouncer covers routes without a route-level oidc policy (automatic under
  the Gateway-level design).
- [ ] Web UI: browse `https://crowdsec.${PUBLIC_DOMAIN}` -> Pocket ID OIDC redirect ->
  login as infra_admins user -> dashboard shows local alerts/decisions; a non-group user is
  denied (`unmatchedRole: deny`); the OIDC callback `/api/auth/oidc/callback` completes.
- [ ] `just pocket-id plan` shows no `callback_path` diff for `crowdsec-web-ui` (the live
  client's callback is `/api/auth/oidc/callback`); if it does show a diff, run
  `just pocket-id apply` to correct it before relying on the Web UI login.
- [ ] Prometheus: `crowdsec_*` and bouncer metrics scrape; Grafana dashboard 21689 renders;
  bouncer-down alert fires when the bouncer pod is deleted (verify the 5xx protected-route
  behavior + the alert).
- [ ] CiliumNetworkPolicy: a pod outside the allowed set cannot reach LAPI/AppSec/bouncer;
  the LAPI/agent pod CAN reach MaxMind (GeoLite2 download) and (if enrolled) CAPI.
- [ ] fail-closed: delete the bouncer pod (single replica) -> all routes on the attached
  gateway return 5xx while the bouncer is down (the accepted SPOF behavior, verified not
  silent fail-open). Confirm the exact response code (EG extAuth `failOpen: false`) at
  implementation.

## Rollback & safety

- Per-app rollback: NOT available under Gateway-level attachment — the bouncer protects all
  routes on the gateway at once. Rollback granularity is per-gateway.
- Gateway rollback: delete the bouncer `SecurityPolicy` for that gateway (`envoy-external`
  or `envoy-internal`) -> that gateway's routes revert to pre-bouncer behavior (no ext_authz).
  The other gateway is unaffected (the 2-stage deployment means the two policies are
  independent).
- Full rollback: delete both bouncer SecurityPolicies -> all routes revert; then
  suspend/remove the crowdsec + bouncer + web-ui Flux Kustomizations. SQLite PVCs remain
  (data preserved) or are deleted for a clean slate.
- fail-closed means a bad bouncer upgrade blocks all routes on the attached gateway — stage
  bouncer chart upgrades carefully; the 2-stage (internal -> external) gives a test surface:
  upgrade with only the `envoy-internal` policy active, observe, then re-apply
  `envoy-external`.
- No cluster-mutating out-of-band actions: all changes via GitOps (Flux watches main).

## Open sub-decisions / follow-ups

- [resolved 2026-07-27] **Geo-enrichment**: MaxMind GeoLite2 via 1Password, reusing the
  repo's EXISTING `maxmind` 1Password item (already consumed by pocket-id:
  `kubernetes/apps/security/pocket-id/app/externalsecret.yaml` extracts
  `MAXMIND_LICENSE_KEY` from `dataFrom.extract.key: maxmind`). Add a crowdsec-namespace
  ExternalSecret with the same `dataFrom.extract.key: maxmind` pattern. The crowdsec
  namespace CNP allows MaxMind GeoLite2 egress — copy the pocket-id CNP egress rule
  (`download.maxmind.com`, `*.maxmind.com`,
  `mm-prod-geoip-databases.a2649acb697e2c09b632799562c076f2.r2.cloudflarestorage.com:443` —
  `kubernetes/apps/security/pocket-id/app/ciliumnetworkpolicy.yaml`). No new 1Password item,
  no plaintext key.
- [followup] **CAPI community blocklist**: CAPI = the CrowdSec Central API (the CrowdSec
  Console network). Enrolling the LAPI makes it pull the aggregated **community blocklist**
  — IPs every CrowdSec user worldwide has flagged as malicious — and push your local
  decisions up (anonymized) so others benefit. This is the main value of CrowdSec: you block
  not just what your own logs detect, but what the whole network detects. **Procedure**:
  (1) sign up (free) at https://app.crowdsec.net; (2) in the Console, "Add instance" / "Enroll
  a new instance" -> it shows `cscli console enroll <TOKEN>`; (3) copy `<TOKEN>`. **1Password
  item**: `crowdsec` with field `CAPI_ENROLL_TOKEN` = the token (created 2026-07-27; store the
  Console login email in the item notes for recovery). After enrollment the LAPI mints its
  own CAPI machine credentials and (with `lapi.storeCAPICredentialsInSecret: true`) stores
  them in a K8s Secret automatically — do NOT pre-create those, do NOT put them in 1Password;
  the enroll token is the only thing brought from the website. **Wiring**: a crowdsec-ns
  ExternalSecret extracts `CAPI_ENROLL_TOKEN` from the `crowdsec` 1P item -> K8s Secret;
  enrollment runs via `cscli console enroll $TOKEN` against the LAPI pod (one-shot
  `kubectl exec`, or a chart init job if the chart exposes an enroll value — exact chart
  mechanism to verify against crowdsec chart 0.24.0 at Phase 1). Recommend: enroll (it is the
  point of running CrowdSec); keep the Web UI `includeCapi` flag default **false** initially
  to avoid alert overload (corelab warning), flip to true later. Decide at Phase 1.
- [followup] **Bouncer namespace**: planned `crowdsec` (engine + UI + bouncer together, one
  Cilium CNP to isolate). The Gateway-level `SecurityPolicy` lives in the `networking`
  namespace (alongside `envoy-internal-rfc1918`) because a SecurityPolicy must be in the same
  namespace as its Gateway target; the ReferenceGrant lives in `crowdsec` allowing
  `from: networking`. Confirmed at Phase 0.
- [verified 2026-07-27] **Envoy proxy pod naming**: the acquisition glob is
  `envoy-external-*` / `envoy-internal-*`. Verified live against the cluster: envoy proxy
  pods are `envoy-external-5dd8db458d-ldpv5` and `envoy-internal-64c94974-rkctk` in the
  `networking` namespace (label `gateway.envoyproxy.io/owning-gateway-name`). EG 1.8.3 names
  them `envoy-{gateway-name}-{hash}` — no namespace segment, no double `envoy-` prefix. (The
  earlier `envoy-networking-envoy-*` and the original `envoy-envoy-*` forms were both wrong.)
  The EG controller pod `envoy-gateway-*` is excluded by `program: envoy`.
- [verified 2026-07-27] **Chart service names + value keys**: crowdsec chart LAPI Service =
  `{{ .Release.Name }}-service` -> `crowdsec-service`; AppSec Service = `crowdsec-appsec-service`
  (confirmed via the kdwils chart default `appSecURL`). kdwils bouncer chart value keys
  confirmed: `config.bouncer.lapiURL` (default `http://crowdsec-service:8080`),
  `config.bouncer.apiKeySecretRef`, `config.waf.appSecURL` (capital S, default
  `http://crowdsec-appsec-service:7422`), `referenceGrant.create`/`fromNamespaces`.
  `securityPolicy.create` does NOT exist — the kdwils chart ships no SecurityPolicy template
  (templates: deployment/service/referencegrant/httproute/servicemonitor/serviceaccount/hpa/
  configmaps only). The bouncer Service is `{{ include "envoy-proxy-bouncer.fullname" }}` ->
  set `fullnameOverride: crowdsec-bouncer`. crowdsec `api.server.trusted_ips` is set via the
  `config.yaml.local` override, not a flat value; `auto_registration.allowed_ranges`
  defaults to `10.0.0.0/8` + `192.168.0.0/16`. AppSec 7422 + collections are explicit config
  (not chart defaults).
- [verified 2026-07-27] **Web UI OIDC = native + callback path + client live**: the Web UI
  has built-in OIDC (`CONFIG_AUTH_OIDC_*`, env contract confirmed in the repo README) — it
  does app-level OIDC itself (like grafana), so NO `gateway-oidc` SecurityPolicy gate in
  front of it (that would double-gate). The OIDC callback path is `/api/auth/oidc/callback`
  — verified against `server/app-auth.ts:1256` (redirect URI built as
  `${origin}${basePath}/api/auth/oidc/callback`), `:1265` (`auth.get('/oidc/callback')`),
  `:1296` (`app.route('${basePath}/api/auth', auth)`). The `crowdsec-web-ui` Pocket ID client
  already exists in `provision/pocket-id/clients.yaml` (key `crowdsec-web-ui`, `gate:
  native`, `subdomain: crowdsec`, `groups: [infra_admins]`) AND is registered live (client_id
  `crowdsec-web-ui`, secret in `pocket-id-clients`/`crowdsec-web-ui_client_secret`, confirmed
  2026-07-27). Its `callback_path` in `clients.yaml` was wrong
  (`/api/oauth/callback/oidc`, copied from pingvin-share-x) and is fixed to
  `/api/auth/oidc/callback`; `locals.tf:15` derives
  `callback_url = https://${subdomain}.${PUBLIC_DOMAIN}${callback_path}` for `gate: native`
  -> `https://crowdsec.${PUBLIC_DOMAIN}/api/auth/oidc/callback`. PKCE stays on (the
  `openid-client` lib sends a challenge; `locals.tf:21` defaults `pkce_enabled: true`).
  Open check: `just pocket-id plan` to confirm the LIVE client's callback matches the fix
  (in case `apply` ran before the callback-path correction).
- [confirmed 2026-07-27] **Bouncer-down Prometheus alert**: required (human-confirmed).
  Critical under fail-closed — a bouncer outage means all routes on the attached gateway
  return 5xx. Tune the alert + write a runbook for the gateway-wide 5xx behavior at Phase 3.
- [followup] **PSA profile for the `crowdsec` namespace**: the hostPath `/var/log` requirement
  (hostVarLog) needs a privileged/baseline-exempt profile; this is owned by the separate
  `pod-security-admission-enforcement` roadmap — coordinate there when that lands.

## What we gain

- Automated IP-ban enforcement + WAF (SQLi/XSS/path) at the edge for every backend, with no
  per-app bouncer code.
- A self-hosted, OIDC-protected, LAN-only security dashboard with historical alert retention
  (the Web UI's sleeper feature) — no reliance on CrowdSec Console.
- Community threat intelligence via CAPI blocklists, applied at the edge.
- Native Envoy Gateway integration (Gateway-level `SecurityPolicy.extAuth`) that combines
  with the existing route-level Pocket ID OIDC gate via EG's parent→child different-feature
  merge — the same pattern the existing `envoy-internal-rfc1918` authorization + route-level
  `oidc` already use. Native-OIDC apps (Pocket ID, grafana) are protected automatically by the
  Gateway-level policy, with no per-route policy needed.
- Geo-enrichment (country/ASN world map) reusing the repo's existing MaxMind key — no new
  secret material.
- All self-contained on SQLite — no external DB dependency for a single-node cluster.

## Effort

L (~1-1.5 days staged): Phase 0+1 (~1d: chart values, envoy acquisition tuning, Gateway-level
SecurityPolicy + ReferenceGrant, geoip ExternalSecret + CNP, CAPI enrollment, 2-stage
verification) + Phase 2 (~0.5d: Web UI + OIDC — the Pocket ID client already exists + is
live) + Phase 3 (~0.25d: dashboards + alerts + runbook) + Phase 4 deferred. The Gateway-level
design is slightly cheaper than the originally planned per-route component (no `gateway-oidc`
component refactor). The fail-closed 2-stage rollout is the slow part — staged internal ->
external to verify no 403-storm on legitimate traffic and to tune the whitelist.

## Relations

- relates_to [[docs/areas/networking]]
- relates_to [[docs/areas/k8s-workloads]]
- relates_to [[docs/areas/observability]]
- relates_to [[docs/areas/iam]]
- depends_on [[docs/areas/external-secrets]]
- relates_to [[grafana-operator-migration]]

## Review correction log (2026-07-27)

Revised against the live repo (`kubernetes/`, `provision/`), the BM area-references, and
EG 1.8.3 docs; points 1 (chart keys/service names) and 2 (envoy pod naming) then verified
against the chart sources and the live cluster; follow-ups resolved with the human 2026-07-27.

1. **Bouncer wiring → Gateway-level** (chosen "Megoldás A"): the original "two route-level
   SecurityPolicies (extAuth + oidc) coexist via section-merge" was wrong — EG does not merge
   same-level policies on the same target (would `Conflicted`). Rewired to a Gateway-level
   `extAuth` SecurityPolicy (parent), which combines with the route-level `oidc` (child) the
   same way `envoy-internal-rfc1918` already does. Tradeoff: no per-route rollout; 2-stage
   internal → external; bouncer SPOF widens to the whole gateway.
2. `${CLUSTER_POD_CIDR}` → `${POD_CIDR}` (the real Flux var; `10.244.0.0/16`) in trusted_ips /
   postoverflow / exemptIPs; `10.0.0.0/8` already covers it + `${SVC_CIDR}`, plus
   `${LAN_SUBNET}` for node/LAN.
3. `${PRIVATE_DOMAIN}` → `${PUBLIC_DOMAIN}` for the Web UI hostname
   (`crowdsec.${PUBLIC_DOMAIN}` on `envoy-internal`, grafana precedent); `home.arpa` dropped
   (not a repo pattern).
4. Envoy pod-name globs corrected to `envoy-{external,internal}-*` (see item 9 — the live
   cluster disproved the `networking-` segment).
5. Dropped the `pod-security.kubernetes.io/enforce: baseline` namespace label — PSA is not
   enforced in this repo and `baseline` would forbid the hostPath `/var/log` the agent needs;
   this is owned by the `pod-security-admission-enforcement` roadmap.
6. `GrafanaDashboard` field: `configMapRef` (no `contentFrom` wrapper).
7. bjw-s app-template uses ≈27 (not 31).
8. IdP protection reworded: under Gateway-level, Pocket ID's own external login is protected
   automatically (no per-route policy needed).
9. **Envoy pod glob re-corrected (live-verified 2026-07-27)**: the first correction
   (`envoy-networking-envoy-*`) was itself wrong — live pods are `envoy-external-*` /
   `envoy-internal-*` (EG 1.8.3 names envoy pods `envoy-{gateway-name}-{hash}`, no namespace
   segment, no double `envoy-` prefix). All prior forms corrected to
   `envoy-{external,internal}-*`.
10. **Chart verification (live + chart sources, 2026-07-27)**: kdwils bouncer chart 0.7.0
    ships NO SecurityPolicy template/value (`securityPolicy.create` absent) — the "disable
    securityPolicy.create" line was removed; the bouncer Service needs
    `fullnameOverride: crowdsec-bouncer` (else it renders `crowdsec-bouncer-envoy-proxy-bouncer`).
    crowdsec chart services confirmed `crowdsec-service` + `crowdsec-appsec-service`
    (`{{ .Release.Name }}-service` pattern). `config.waf.appSecURL` (capital S) confirmed.
    `api.server.trusted_ips` is set via the `config.yaml.local` override, not a flat value;
    `auto_registration.allowed_ranges` defaults to `10.0.0.0/8` + `192.168.0.0/16`. AppSec
    7422 + collections are explicit config (not chart defaults).
11. **Follow-up resolutions (with human, 2026-07-27)**: (a) geo-enrichment resolved — reuse
    the existing `maxmind` 1Password item (pocket-id already consumes it) + copy the pocket-id
    MaxMind egress CNP rule; (b) CAPI explained — the CrowdSec Central API community
    blocklist (the main value of CrowdSec); recommend enroll, `includeCapi` default false;
    (c) Web UI OIDC confirmed native (built-in `CONFIG_AUTH_OIDC_*`), no `gateway-oidc` gate,
    `gate: native` Pocket ID client like grafana; (d) bouncer-down Prometheus alert confirmed
    required (critical under fail-closed) + runbook. The Web UI decision block was reworded
    to state "built-in OIDC" explicitly, and Phase 1/3 gained the geoip ExternalSecret + CNP
    egress lines.
12. **Web UI callback + CAPI procedure (verified 2026-07-27)**: the OIDC callback path is
    `/api/auth/oidc/callback`, verified against `server/app-auth.ts:1256,1265,1296` (route
    `auth.get('/oidc/callback')` mounted at `${basePath}/api/auth`; redirect URI
    `${origin}${basePath}/api/auth/oidc/callback`). The env contract (`CONFIG_AUTH_OIDC_*`,
    `CONFIG_INSTANCE_*`) confirmed in the repo README. The existing `crowdsec-web-ui` entry
    in `provision/pocket-id/clients.yaml` had the WRONG `callback_path`
    (`/api/oauth/callback/oidc`, copied from pingvin-share-x) — fixed to
    `/api/auth/oidc/callback` (lint passes); `just pocket-id plan` should show only that
    callback-path diff. CAPI procedure + 1Password item recorded in the CAPI followup. Phase 2
    admin group made concrete (`infra_admins`) and the Web UI client-secret flow corrected: it
    reads from the shared `pocket-id-clients` 1Password item (synced by `just pocket-id apply`),
    not a separate `crowdsec-web-ui-oidc` item.
13. **Secrets in place + client live (human, 2026-07-27)**: the `crowdsec-web-ui` Pocket ID
    client is registered live (client_id `crowdsec-web-ui`, secret in
    `pocket-id-clients`/`crowdsec-web-ui_client_secret`). The CAPI enroll token is in a 1P
    item named **`crowdsec`** (field `CAPI_ENROLL_TOKEN`) — not `crowdsec-capi` as previously
    drafted; the CAPI followup + Phase 0 updated to the real name. Removed the unnecessary
    `crowdsec-lapi` 1P item: the bouncer API key, agent registration token, and Web UI LAPI
    machine credential are GENERATED by the chart/LAPI into K8s Secrets (a new decision block
    records this), not pre-created in 1P — only externally-sourced secrets (CAPI token,
    MaxMind key, OIDC client secret) go to 1Password. Added a verification step:
    `just pocket-id plan` to confirm the live client's callback URL matches the corrected
    `/api/auth/oidc/callback` (in case `apply` ran before the callback-path fix).

## Review correction log — 2026-07-27 second pass (Gateway-level same-level conflict)

A second evidence-based review on 2026-07-27 (live cluster + repo + EG 1.8.3 docs)
found one blocking architectural flaw in the bouncer-wiring decision. This section is
**authoritative and supersedes** the affected clauses in "Decisions (Bouncer wiring)",
"Phase 1 — Engine + bouncer", "What we gain", and the "IdP protection" claim wherever
they describe the `envoy-internal` bouncer as a *separate* Gateway-level policy living
"alongside" `envoy-internal-rfc1918`. The `envoy-external` wiring is unaffected.

### The flaw

The original decision reasons that "EG does NOT merge multiple SecurityPolicies at the
same hierarchy level on the same target" — but applies that rule only to the *route-level*
case (a second route-level `extAuth` would `Conflicted` against the existing route-level
`oidc`), and then "solves" it by attaching the bouncer at Gateway level. It does **not**
re-apply the same rule to the *Gateway-level* case it creates.

Today on `envoy-internal` there is already ONE Gateway-level SecurityPolicy:
`envoy-internal-rfc1918` (`authorization`, `defaultAction: Deny`, RFC1918 allowlist,
live 70d). The plan adds a **second** Gateway-level SecurityPolicy (`extAuth`, bouncer)
on the **same** Gateway target. That is two policies at the **same hierarchy level on the
same target** — exactly the conflict case the note itself describes.

### EG 1.8.3 documented semantics (verified)

- "When multiple SecurityPolicies target the same resource at the same hierarchy level
  ... the oldest policy (earliest creationTimestamp) takes precedence" — **single-winner,
  feature-agnostic**; there is no same-level feature merge.
- `mergeType` (StrategicMerge / JSONMerge) is **parent-child only** — it can be set on
  policies targeting HTTPRoute, **not** on Gateway-level policies. So two Gateway-level
  policies cannot be merged via `mergeType`.

Source: gateway.envoyproxy.io SecurityPolicy concepts; envoyproxy/gateway#4275, #8649.

### Consequence if left unfixed

`envoy-internal-rfc1918` is older, so it wins; the bouncer `extAuth` policy becomes
`Overridden`/`Conflicted` and is **silently inert** on `envoy-internal` — Stage 1 of
the 2-stage rollout reports a false green. (Or, if the bouncer somehow won, the rfc1918
LAN allowlist would drop off the gateway — a security regression, only masked by the
Cilium CNP at the network layer.) Either outcome is wrong.

### Corrected design (supersedes the prior wiring)

- **`envoy-internal`**: do NOT create a separate bouncer Gateway-level SecurityPolicy.
  Instead, **merge the bouncer `extAuth` block INTO the existing
  `envoy-internal-rfc1918` SecurityPolicy** — one Gateway-level policy carrying both
  `authorization` (the existing RFC1918 rules) **and** `extAuth` (bouncer,
  `failOpen: false`, `bodyToExtAuth.maxRequestBytes: 65536`,
  `backendRefs -> crowdsec-bouncer.crowdsec.svc:8080`). This is the only EG-supported
  way to get both features on the same Gateway target. The ReferenceGrant in the
  `crowdsec` namespace (`fromNamespaces: [networking]`) still permits the
  cross-namespace backendRef.
- **`envoy-external`**: unchanged — a **separate** Gateway-level bouncer SecurityPolicy
  is correct here, because there is **no** existing Gateway-level policy on
  `envoy-external` (verified live 2026-07-27: only route-level oidc policies exist on
  envoy-external-attached routes, e.g. echo-server-oidc). Route-level oidc + Gateway-level
  extAuth is the supported **parent-child, different-feature** case and combines cleanly.
- **Rollout (corrected Stage 1)**: Stage 1 is "merge `extAuth` into
  `envoy-internal-rfc1918` and verify the merged policy's status shows no
  `Conflicted`/`Overridden`", NOT "apply a second Gateway-level policy". Stage 2
  (separate bouncer policy on `envoy-external`) is unchanged.

### Corrected "precedent" framing

The earlier claim that "this is exactly how the existing `envoy-internal-rfc1918`
Gateway-level authorization + route-level oidc already coexist" is a **different-level**
(parent Gateway + child HTTPRoute) case and is real (the 8 downloads oidc routes — bazarr,
prowlarr, radarr, sonarr, seerr, maintainerr, qbittorrent, subsyncarr — attach to
`envoy-internal` with route-level oidc, live-verified 2026-07-27). But that precedent
does **not** justify a **same-level** dual-Gateway-policy on `envoy-internal`, which the
bouncer would introduce. The two cases must not be conflated.

### Corrected "What we gain" framing

The bouncer on `envoy-external` is **defense-in-depth behind Cloudflare WAF** (the
`networking` area-ref records that envoy-external rate-limiting is currently covered by
Cloudflare WAF pending the EG 1.8.x CRD regression fix). The **primary** edge-protection
gain is on `envoy-internal`, which is exposed on a Cilium L2 VIP with no WAF in front.

### New verification step (append to "Verification steps")

- [ ] After merging `extAuth` into `envoy-internal-rfc1918`:
  `kubectl -n networking get securitypolicy envoy-internal-rfc1918 -o jsonpath='{.status.conditions}'`
  shows `Accepted=True` with **no** `Conflicted`/`Overridden` condition; and a test
  ban (`cscli decisions add -i 1.2.3.4`) 403s on an `envoy-internal` route while the
  RFC1918 LAN allowlist still holds for a non-RFC1918 source (both features present in the
  single merged policy). Also confirm the separate `envoy-external` bouncer policy is
  `Accepted=True` (no same-level conflict there).

### Net effect on the plan

Effort and scope are essentially unchanged — the only implementation difference is one
merged SecurityPolicy on `envoy-internal` instead of two separate Gateway-level policies.
The fail-closed SPOF, trusted-IPs, self-ban whitelist, CNP, geoip, and Web UI sections are
unaffected and remain as written.

## Update 2026-07-27 — namespace rationale, OAuth callback resolved, PSA coordination

### OAuth callback — RESOLVED (human-verified 2026-07-27)

The live `crowdsec-web-ui` Pocket ID client's OAuth redirect URL is correct
(`/api/auth/oidc/callback` -> `https://crowdsec.${PUBLIC_DOMAIN}/api/auth/oidc/callback`).
The open `just pocket-id plan` / "verify the live client's callback URL" checks in
Phase 2 and "Verification steps" are **resolved** — no `callback_path` diff to apply.
(Closes the open check raised in the 2026-07-27 first-pass correction log item 12.)

### Namespace design — rationale (why a single dedicated `crowdsec` namespace)

Repo idiom (verified 2026-07-27): 12 app-group namespaces under `kubernetes/apps/<group>/`,
one per domain (`downloads`, `media`, `selfhosted`, `security`, `networking`,
`observability`, `cert-manager`, `volsync-system`, `system-upgrade`, `kube-system`,
`external-secrets`, `flux-system`). Platform components get their own ns. The plan puts
**all** crowdsec components — engine (LAPI + agent + AppSec) + bouncer + Web UI — in one
new `crowdsec` namespace. Reasons:

1. **One CiliumNetworkPolicy isolates the whole component.** LAPI (8080), AppSec (7422),
   and bouncer gRPC (8080) ingress restricted to the allowed callers (bouncer, agent,
   Web UI, and the envoy proxy pods on the critical path). A single namespaced CNP is
   simpler and tighter than cross-ns ClusterwideCNPs split across namespaces.
2. **Chart-generated credentials stay in-ns.** The bouncer API key, agent registration
   token, and Web UI LAPI machine credential are GENERATED by the chart/LAPI into K8s
   Secrets and consumed via `secretKeyRef` within `crowdsec` — no cross-namespace
   secret references (which would need extra wiring and widen the access surface).
3. **Distinct risk profile from the IdP.** `security` hosts pocket-id (the OIDC IdP,
   distroless nonroot, restricted-clean). CrowdSec mixes a hostPath-mounting log agent
   (privileged-ish), an AppSec WAF on the request critical path, and an internally-exposed
   LAPI — a different blast radius. A dedicated ns keeps its CNP and (future) PSA profile
   separate from the IdP rather than forcing one profile onto both.
4. **Lifecycle coupling.** Bouncer + Web UI depend on LAPI; one Flux Kustomization tree
   (`kubernetes/apps/crowdsec/`) keeps the dependency coherent.

**The one deliberate cross-namespace boundary:** the Gateway-level `SecurityPolicy` MUST
live in `networking` (EG constraint: a SecurityPolicy is in the same namespace as its
Gateway target — verified: `envoy-internal-rfc1918` is in `networking`). The bouncer
Service stays in `crowdsec`; `networking` references it cross-ns via a `ReferenceGrant`
in `crowdsec` (`fromNamespaces: [networking]`). This is the **minimal** cross-ns surface:
one CR (the SecurityPolicy in `networking`) + one ReferenceGrant (in `crowdsec`).

**Rejected alternatives:**
- **Bouncer in `networking`:** would create a cross-ns secret ref (bouncer -> LAPI API
  key in `crowdsec`), split the isolating CNP across namespaces, and decouple the bouncer
  lifecycle from LAPI. More complexity, no benefit.
- **CrowdSec in `security` (with pocket-id):** forces one PSA/CNP profile onto two
  components with different risk profiles (hostPath agent vs distroless IdP); see PSA note
  below — the hostPath requirement makes `crowdsec` need `privileged` enforce, which
  pocket-id must not carry.

### PSA coordination — detail (why the `crowdsec` ns cannot be baseline/restricted)

The crowdsec agent needs `hostVarLog: true` -> it mounts hostPath `/var/log` to read the
envoy proxy pods' stdout logs from `/var/log/pods/...` (acquisition globs
`envoy-external-*` / `envoy-internal-*`, `program: envoy`). PSS **`baseline` forbids
hostPath mounts**, and PSS has **no per-pod in-namespace exception** (the
`pod-security-admission-enforcement` roadmap states this explicitly: a single
non-compliant pod blocks the whole namespace). Therefore:

- The `crowdsec` namespace **cannot** be `enforce: baseline` (or `restricted`) while
  the agent uses `hostVarLog` — the agent pod would be rejected at admission.
- The `crowdsec` ns fits the **infra-namespace -> `privileged` enforce** pattern in the
  PSA roadmap (`kube-system`, `system-upgrade`, `volsync-system`, `cert-manager` stay
  `privileged` for legit privileged infra). The non-agent pods (LAPI, AppSec, bouncer,
  Web UI) ARE restricted-clean (runAsNonRoot, drop ALL, seccomp RuntimeDefault,
  readOnlyRootFS) — but they share the ns with the hostPath agent, so the ns-level label
  must accommodate the agent.

**Current cluster state (verified 2026-07-27):** NO `pod-security.kubernetes.io/*` labels
on any app namespace except `flux-system` (`warn=restricted`, auto-applied by the
flux-operator). So the repo idiom today is "no PSA labels"; the PSA roadmap proposes
adding them. Consistent with that, the crowdsec roadmap does **NOT** add a PSA label to
the `crowdsec` namespace now — the PSA roadmap owns that label and will classify
`crowdsec` as `enforce: privileged` (with `warn`/`audit: restricted` to keep the non-agent
pods honest).

**Alternatives that would avoid the privileged profile** (not chosen for this single-node
cluster — logged as PSA-roadmap coordination, not implemented here):
1. Ship envoy access logs to the agent over network via a Fluent Bit / Vector sidecar or
   DaemonSet (no hostPath) — adds a component and a hop.
2. CrowdSec Kubernetes-audit / API-stream acquisition instead of file acquisition —
   different detection surface (k8s audit events, not envoy HTTP logs); loses the WAF
   feed value.
3. Split: LAPI/AppSec/bouncer/Web UI in a `crowdsec` ns at `restricted` + the agent as
   a DaemonSet in a dedicated privileged infra ns — cleanest separation but
   over-engineered for a single-node cluster.

**Coordination handoff:** when the `pod-security-admission-enforcement` roadmap lands,
it must label `crowdsec` as `enforce: privileged` (NOT baseline/restricted) because of
`hostVarLog`. This is the crowdsec roadmap's only PSA contribution — a documented
constraint, not a label to add now.

### HostPath-free acquisition — the victoria-logs pipeline option (2026-07-27)

The `hostVarLog` hostPath requirement is NOT the only acquisition path. Evidence-backed
alternatives exist that keep the `crowdsec` namespace hostPath-free, which reopens the
PSA profile from `privileged` back to `restricted`.

**Existing pipeline (live-verified 2026-07-27):** `victoria-logs-collector` is a DaemonSet
in the `observability` ns mounting hostPath `/var/log` (readOnly) + `/var/lib` (ReadOnly),
shipping all pod stdout logs to `victoria-logs-server.observability.svc:9428`. The envoy
proxy pods' JSON access logs already flow through it (`envoy.yaml` `type: File -> /dev/stdout`
-> `/var/log/pods/...` -> collector -> victoria-logs-server). This is the repo's only log
shipper (no vector/fluent-bit/otel-collector DaemonSet besides it).

**CrowdSec network acquisition sources (Context7-verified, doc.crowdsec.net):** the agent
supports DataSource modules `file`, `http`, `syslog`, `kafka`, `kubernetes-audit`,
`journald`, `docker`, `Loki`, `VictoriaLogs`, `Appsec`, `AWS`. So file/hostPath is NOT
the only option — `http`, `syslog`, and a native `VictoriaLogs` source all receive logs
over the network.

**Ranked hostPath-free options:**
1. **`victorialogs` source (RECOMMENDED, zero new infra):** the crowdsec agent reads envoy
   access logs from `victoria-logs-server` via the native VictoriaLogs datasource. No new
   component, no hostPath on `crowdsec`, one CNP egress rule (crowdsec agent ->
   `victoria-logs-server.observability.svc:9428`). Verification point: the collector-stored
   envoy log field format must match the `yanis-kouidri/envoy` parser (preserve the raw
   envoy JSON line in the collector config, or write a crowdsec parser for the VL fields).
2. **`http` source + collector sink:** add a second sink to the existing victoria-logs-collector
   config that POSTs envoy log lines to the crowdsec agent's HTTP source. Reuses the
   collector; +1 sink + CNP (collector -> crowdsec http port). Raw envoy JSON line passes
   through -> existing parser stays.
3. **`syslog` source + collector syslog sink:** equivalent to 2 over syslog TCP (Vector
   supports a syslog sink).
4. **EnvoyProxy `OpenTelemetry`/`ALS` sink (EG-native, NOT reuse):** EG 1.8.3 supports
   `type: OpenTelemetry` (OTLP gRPC) and `type: ALS` (gRPC Access Log Service) access-log
   sinks — both network, not file. But no OTel collector exists in the repo today, and the
   OTLP AccessLog schema != the envoy JSON line the `yanis-koudri/envoy` parser expects
   (needs a collector transform). More new infra + a format bridge -> less attractive than
   1-3 on a single node.

**Revised PSA implication:** the earlier conclusion ("`crowdsec` ns must be `enforce:
privileged` because of `hostVarLog`") holds ONLY for the hostPath-agent path. With option
1 (`victorialogs`) or 2 (`http`), the `crowdsec` ns can be `enforce: restricted` — the agent
gets no hostPath, and the non-agent pods (LAPI/AppSec/bouncer/Web UI) are already
restricted-clean. So the PSA-roadmap table row for `crowdsec` is conditional on the chosen
acquisition path: hostVarLog -> `privileged`; victorialogs/http -> `restricted`.

**Side finding (repo-wide, affects the PSA roadmap):** the `observability` ns ALREADY hosts
hostPath-mounting DaemonSets — `victoria-logs-collector` (`/var/log`, `/var/lib`) and
`kube-prometheus-stack-prometheus-node-exporter` (`/`, `/sys`, `/proc`). PSS `baseline`
forbids hostPath, so `observability` cannot be `enforce: baseline` without exceptions — it
must be `privileged`, like the other infra namespaces. The `pod-security-admission-
enforcement` roadmap's "observability -> baseline" row is already blocked by the live
cluster; that roadmap's per-namespace table needs correcting. The hostPath problem is
repo-wide (any ns running node-level DaemonSets), not crowdsec-specific.

**Recommendation:** on a single node, `hostVarLog` remains the pragmatic default (simplest,
matches the crowdsec chart defaults, and is consistent with the existing `observability`
hostPath-DaemonSet pattern — sets no new precedent). The `victorialogs` source is the clean
upgrade when the PSA roadmap tightens, recorded here as the explicit alternative — not
implemented now. If the goal is `crowdsec` ns `restricted` from day one, take option 1 and
verify the collector's envoy-log field format as the first implementation step.

## Locked decision — 2026-07-27 (human): `restricted` PSA + `victorialogs` acquisition

Human-locked 2026-07-27. This section is **authoritative** and supersedes every prior
clause about (a) the `crowdsec` namespace PSA profile, (b) envoy log acquisition, and
(c) the acquisition-alternatives ranking. Specifically it supersedes:
- the Phase 0 line "Do NOT add a pod-security.kubernetes.io/enforce label ... coordinate
  with the pod-security-admission-enforcement roadmap";
- the Phase 1 "Log acquisition" / agent `hostVarLog: true` hostPath plan;
- the "PSA coordination — detail" conclusion that `crowdsec` must be `enforce: privileged`;
- the "HostPath-free acquisition" ranked alternatives list (options 2-5 are DROPPED).

### Decision 1 — `crowdsec` ns is `enforce: restricted` from day one

The `crowdsec` namespace gets the strict PSA label **self-applied by this roadmap in Phase 0**
(not deferred to the `pod-security-admission-enforcement` roadmap):
```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.36
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.36
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.36
```
Every pod in `crowdsec` must satisfy PSS `restricted`: `runAsNonRoot: true`,
`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` (no `add` except
`NET_BIND_SERVICE`, and none is needed — LAPI 8080, AppSec 7422, bouncer gRPC 8080,
Web UI 3000 are all unprivileged ports), `seccompProfile: RuntimeDefault`, and NO
`hostPath`/`hostNetwork`/`hostPID`/`hostIPC`. `readOnlyRootFilesystem` is NOT required by
`restricted` (SQLite PVCs on local-hostpath are fine).

**Implementation blocker to verify BEFORE applying the label:** the crowdsec OCI chart
0.24.0 (LAPI/agent/AppSec) and the kdwils bouncer chart 0.7.0 must support these
securityContexts. The crowdsec image has historically run as root — confirm the chart
exposes `securityContext` overrides AND the image runs non-root (or supports a non-root
UID). The Web UI (bjw-s app-template) is already restricted-clean per the plan. If any
chart forces root / privilege escalation, that is a **hard blocker** — resolve it (chart
values, or a different image) before creating the namespace with the label, otherwise the
pods are rejected at admission. Run `kubectl label --dry-run=server ns crowdsec
pod-security.kubernetes.io/enforce=restricted` after a staged apply to preview rejections.

### Decision 2 — acquisition via the crowdSec `victorialogs` datasource (no hostPath)

The agent does NOT use `hostVarLog`, does NOT mount hostPath `/var/log`, does NOT read
envoy proxy pod log files. Instead it uses CrowdSec's native **`victorialogs`** DataSource
(Context7-verified, doc.crowdsec.net) to query envoy access logs from the existing
`victoria-logs-server.observability.svc:9428`, where the `victoria-logs-collector` DaemonSet
already ships all pod stdout logs (including the envoy proxy pods' JSON access logs —
live-verified 2026-07-27). Configure the acquisition in the crowdsec chart's
`config.yaml.local` override (a `victorialogs` source pointing at
`victoria-logs-server.observability.svc:9428`, label `type: envoy`, collection
`yanis-kouidri/envoy`).

**CNP change:** add `crowdsec` agent egress to `victoria-logs-server.observability.svc:9428`
(TCP) — copy the egress-label idiom used for the observability plane. The hostPath `/var/log`
mount + its node RBAC concern are removed entirely. The agent's only egress is now: LAPI
(in-ns), `victoria-logs-server:9428` (observability), MaxMind GeoLite2, CAPI (if enrolled).

**Gate verification (FIRST implementation step, before anything else):** confirm the
victoria-logs-collector stores the envoy access log such that the `yanis-kouidri/envoy`
parser can parse it — i.e. the raw envoy JSON line is preserved as the log body in
VictoriaLogs (not collapsed into unrelated structured fields). If the collector parses the
envoy JSON into VL structured fields, either (a) adjust the collector config to preserve
the raw line for envoy pods, or (b) write a small crowdsec parser for the VL field shape.
Do not proceed to bouncer wiring until this gate passes — it is the load-bearing
assumption of the whole acquisition change.

### Dropped alternatives (NOT in the plan)

Closed 2026-07-27 — option 1 (`victorialogs`) chosen; the rest are dropped:
- `hostVarLog` hostPath agent reading envoy pod stdout from `/var/log/pods/...` (the
  original Phase 1 plan) — DROPPED.
- `http` source + a second collector sink POSTing to the crowdsec agent — DROPPED.
- `syslog` source + collector syslog sink — DROPPED.
- EnvoyProxy `OpenTelemetry` / `ALS` access-log sink + an OTel collector / custom ALS
  receiver — DROPPED.

### Updated implications

- **PSA coordination:** the `crowdsec` row in the `pod-security-admission-enforcement`
  roadmap's per-namespace table is now "`restricted`, self-applied by the crowdsec roadmap
  in Phase 0" — the PSA roadmap must NOT re-label `crowdsec` (no drift). The repo-wide
  side-finding (observability ns already blocked from `baseline` by its hostPath
  DaemonSets) stands and is a PSA-roadmap correction, independent of this decision.
- **Security review:** the hostPath trust-boundary concern is gone — the agent no longer
  touches node `/var/log`. The `restricted` label is itself an admission guarantee that no
  future crowdsec pod can regress to privileged/hostPath.
- **Scope/effort:** roughly unchanged — +1 CNP egress rule (crowdsec -> victoria-logs-server),
  -1 hostPath mount + its RBAC, +1 namespace label, +1 gate verification (envoy log format
  match).

### Updated verification steps (supersede the hostVarLog ones)

- [ ] `crowdsec` ns labeled `enforce: restricted` (+warn/audit, *-version: v1.36);
  every crowdsec pod (LAPI, agent, AppSec, bouncer, Web UI) admits and stays Running — no
  PodSecurity admission denials (confirms all charts are restricted-clean).
- [ ] **Gate:** envoy log field format match verified — a test request to a protected route
  produces an envoy access-log line in VictoriaLogs that the `yanis-kouidri/envoy` parser
  ingests (`cscli metrics` shows non-zero parsed envoy lines). This MUST pass before bouncer
  wiring.
- [ ] `victorialogs` source egress: crowdsec agent can reach `victoria-logs-server:9428`
  (CNP egress rule); a pod outside the allowed set cannot.

## Gate verification — 2026-07-27 (live)

Both gates run live against the cluster (victoria-logs-server port-forward + LogsQL), the chart sources (helm pull), and the image registries (docker.io / ghcr.io config blobs). Results below supersede the optimistic assumptions in the locked decision.

### Gate 1 — envoy log format vs yanis-kouidri/envoy parser: CONDITIONAL FAIL (rework needed)

Evidence (live LogsQL, query kubernetes.pod_name:envoy-external* and envoy-internal*):
- envoy-external / envoy-internal proxy access logs ARE collected into VL (container envoy, ns networking).
- The victoria-logs-collector (vlagent v1.52.0) runs with --kubernetesCollector.msgField=message,msg,log . Envoy JSON access logs have NO message/msg/log field, so _msg is set to the literal placeholder "missing _msg field; see https://docs.victoriametrics.com/victorialogs/keyconcepts/#message-field".
- The envoy access-log fields are decomposed into structured VL top-level fields: method, path, response_code, downstream_remote_address, x_forwarded_for, start_time, authority, bytes_received, bytes_sent, duration_ms, protocol, request_id, route_name, upstream_cluster, upstream_host, user_agent, response_code_details, response_flags.
- CrowdSec victorialogs datasource (Context7-confirmed: source: victorialogs, mode: tail, query: <LogsQL>) tails VL and feeds log lines to parsers; the type label directs to the parser. CrowdSec parsers grok a log-line string (Str), not flat VL fields.

Verdict: the raw envoy JSON access-log line is NOT preserved as _msg; the victorialogs + yanis-kouidri/envoy parser plan does NOT work as-is IF the datasource feeds only _msg (placeholder) to the parser -> acquisition would produce nothing. The structured fields are present in VL but unusable by a line-grok parser.

Definitive verification requires a running crowdsec + cscli explain --log <VL-returned envoy line> --type envoy -v — not possible pre-deployment.

Mitigation paths (pick before implementation):
1. Adjust the envoy access log so a usable line reaches _msg — e.g. add a second access-log sink in the EnvoyProxy telemetry config that emits a raw text line the collector keeps verbatim, or add a message-style field to the JSON body. Touches shared envoy-gateway config (external + internal) — needs its own change evaluation.
2. Reconfigure the collector to not decompose envoy JSON (keep the raw line as _msg) — needs a vlagent flag investigation; risks the shared observability pipeline (AD-023).
3. Verify the victorialogs datasource actually returns the full VL record as a JSON line (not just _msg) — if so, the yanis-kouidri/envoy parser may grok the reconstructed envoy fields. Needs datasource source/docs dive or the post-deploy cscli explain.

### Gate 2 — chart securityContext / non-root: SPLIT verdict

Bouncer (oci://ghcr.io/kdwils/charts/envoy-proxy-bouncer, image ghcr.io/kdwils/envoy-proxy-bouncer):
- Chart version 0.7.0 (locked decision) DOES NOT EXIST in the registry; latest is 0.6.0 (appVersion v0.6.0). Correction required.
- Image USER=1000 (non-root).
- Chart container securityContext defaults: runAsNonRoot:true, runAsUser:1000, allowPrivilegeEscalation:false, capabilities.drop:[all], readOnlyRootFilesystem:true. No hostPath/hostNetwork.
- Only seccompProfile:RuntimeDefault missing — add via podSecurityContext (chart allows toYaml).
- VERDICT: restricted-READY with one seccompProfile line. PASS.

Crowdsec (oci://ghcr.io/crowdsecurity/helm-charts/crowdsec 0.24.0, image crowdsecurity/crowdsec:v1.7.8):
- Image USER empty (root). Entrypoint [/bin/bash, /docker_start.sh], WorkingDir /.
- LAPI entrypoint (docker-start-custom.sh) does chown -f ":$GID" <db_path> — explicitly assumes root (chown needs CAP_CHOWN). The GID env (default 1000) is a group-based DB-access mechanism for sidecar/non-root-group patterns, NOT full non-root support.
- Chart container securityContext defaults: only allowPrivilegeEscalation:false, privileged:false — missing runAsNonRoot, runAsUser, capabilities.drop:[ALL], seccompProfile. All configurable via values.
- agent DaemonSet/Deployment mounts /var/log hostPath (agent.hostVarLog:true default) + /var/lib/docker/containers if container_runtime:docker. With victorialogs acquisition: set agent.hostVarLog:false + non-docker runtime -> hostPath removed. LAPI + AppSec deployments are hostPath-free.
- VERDICT: restricted-PSA NOT feasible out-of-the-box. restricted requires runAsNonRoot:true; the image runs as root, so the kubelet rejects the pod unless runAsUser:<nonzero> is set AND the crowdsec process functions as that UID. The entrypoint chown calls are guarded (fail gracefully) and writable paths are mounted volumes (emptyDir/PVC), so a non-root run with runAsUser:1000 + fsGroup:1000 is PLAUSIBLE but UNVERIFIED and not officially supported (docs always show a root container). Real crash-loop risk if any image-owned root path needs writing.

### Impact on the locked decision — two revisions required

1. restricted PSA on the crowdsec ns from day 1 is AT RISK. Revise to: start the crowdsec ns at baseline (hostPath already avoided via victorialogs), deploy crowdsec with runAsUser:1000, runAsNonRoot:true, fsGroup:1000, capabilities.drop:[ALL], seccompProfile:RuntimeDefault + agent.hostVarLog:false, confirm a non-root smoke test (LAPI ready, cscli works, no chown-permission crash-loop), THEN promote the ns to enforce: restricted. restricted is gated on the empirical non-root run, not applied blind.
2. victorialogs acquisition is NOT implementation-ready as-is. Before building the crowdsec acquisition, resolve Gate 1: either verify the datasource returns a parser-grokable envoy line (post-deploy cscli explain), or adjust the envoy access-log / collector so a raw envoy line reaches _msg. The hostPath-free benefit of victorialogs stands; the parser-ingestion path does not.
3. Chart version correction: bouncer chart is 0.6.0, not 0.7.0.

Net: the locked decision two pillars (restricted from day 1; victorialogs works for envoy) both need the revisions above before this roadmap item is implementation-ready.

## Close-out (2026-07-28)

- [observation] **Status: done.** Phase 0–3 implemented and live (engine +
  bouncer + Web UI + observability + both-gateway extAuth wiring). Full
  execution log in [[envoy-crowdsec-bouncer]] (progress), Sessions 1–4; Session
  4 has the soak verification and the follow-up resolution.
- [dropped] **Phase 4 — CAPTCHA (Cloudflare Turnstile).** Turnstile is free,
  unlimited, and works on any origin (no Cloudflare proxy required), but the
  bouncer's gRPC extAuth wiring makes the chart's CAPTCHA flow unverified, and
  the threat model is thin with only hard-deny rules remaining. Dropped, not
  deferred.
- [dropped] **All remaining follow-ups** (VolSync for the Web UI PVC, body-based
  WAF detection, `crowdsecurity/appsec-crs` re-evaluation, mTLS to LAPI). Each
  dropped with rationale in the progress note Session 4.
- [observation] The "Open sub-decisions / follow-ups" section above is resolved
  by the implementation: CAPI community blocklist enrollment wired (Session 2),
  bouncer namespace `crowdsec` (engine + UI + bouncer together), PSA profile
  `restricted` (owned by this roadmap, not deferred to
  `pod-security-admission-enforcement`).
- [observation] Two roadmap claims were disproved during execution and
  corrected in the progress note: the locked `victorialogs` acquisition (Gate
  1) does not work as written — fixed with a LogsQL `copy`+`pack_json` pipe
  inside the crowdsec acquisition config; and the "Phase 1 full WAF"
  `bodyToExtAuth.maxRequestBytes: 65536` decision was reversed after a live 413
  regression on uploads over 64 KB.
