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
- [status] in-progress
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
