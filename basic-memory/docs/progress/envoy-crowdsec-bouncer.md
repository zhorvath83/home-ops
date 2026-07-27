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
