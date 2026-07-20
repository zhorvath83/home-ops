---
title: kanidm-auth-audit-trail
type: progress-note
permalink: home-ops/docs/progress/kanidm-auth-audit-trail
status: in-progress
implements: home-ops/docs/roadmap/kanidm-auth-audit-trail
relates_to:
- home-ops/docs/areas/iam
- home-ops/docs/areas/observability
- home-ops/docs/areas/networking
- home-ops/docs/decisions/AD-023-cnp-threat-model-audit
---

# Progress — kanidm-auth-audit-trail

Implementation journal for [[kanidm-auth-audit-trail]] (roadmap). Work runs
sequentially on `main` per explicit user decision (GitHub project; the
GitLab branch-first/MR model is overridden — see project CLAUDE.md "Source
Control Platform"). L4 (OTLP) is a later separate sub-item with its own
security-review; this note tracks Phase 0–1 (L1–L3) until then.

## Decisions (session 2026-07-20)

- Scope: the whole roadmap, sequentially, on `main` (no per-phase branch).
- Probe approach: ship the L1A trust-all env (`KANIDM_TRUST_X_FORWARDED_FOR=true`)
  as a throwaway Phase-0 probe to read the per-path `client_address`, then
  revert it when L1B (spoof-resistant `server.toml` + CIDR list) lands.
- Env-var name corrected from the roadmap's earlier spelling: the live var is
  `KANIDM_TRUST_X_FORWARDED_FOR` (with the "D"); `KANIDM_TRUST_X_FORWARD_FOR`
  does not exist (roadmap Pass 2 correction #1).

## Phase 0 — verification gate

| Blocker | Status |
|---|---|
| R2 — VictoriaLogs ingests security/kanidm | DONE (positive, 8907 lines/24h, 14d) |
| R3 — `person session status` shows client_address | DONE (NO — "from where" needs L2 correlation) |
| Risk #1 — client_address is Envoy pod IP today | DONE (confirmed) |
| L1A XFF probe login (LAN + Cloudflare) | PENDING — env committed, awaits user login + read |

### Session 2026-07-20 — L1A probe env

- Commit `8d9f954b4` — `wip(kanidm): add L1A XFF trust-all probe env`:
  added `KANIDM_TRUST_X_FORWARDED_FOR: "true"` to the kanidm container env
  (`kubernetes/apps/security/kanidm/app/helmrelease.yaml`). yamlfmt/yamllint
  green. Pre-commit green.
- NOT yet pushed / reconciled — pending user approval (remote + cluster op).

## Next

1. Push `8d9f954b4` and let Flux reconcile (or `just k8s flux-reconcile`).
2. User: log in once via LAN (envoy-internal) and once via Cloudflare
   (envoy-external); read `client_address` in `just kanidm logs` for each
   path. Record the observed IPs + XFF chain here.
3. Decide L1 path from the probe result:
   - real IP reaches kanidm on both paths → ship L1B (`config/server.toml`
     with `version = "2"` + `[http_client_address_info] x-forward-for =
     ["10.244.0.0/16"]`, ConfigMap-mount like `theme`, `KANIDM_CONFIG=/config/server.toml`,
     `kanidmd configtest`-validated) and REVERT the L1A env.
   - real IP missing on a path → Phase 2 Envoy-side XFF fix first
     (`envoy-internal` append downstream; `envoy-external` ClientTrafficPolicy/
     EnvoyPatchPolicy to set upstream XFF from CF-Connecting-IP + strip
     client-supplied XFF), then L1B.
4. Then Phase 1 continues: L2 (`audit` + `vlogs-query` recipes) → L3
   (`sessions` group). L4 (OTLP) as a separate sub-item + security-review.

## Verification criteria (per roadmap)

- L1: `client_address` shows real user IP on both paths; `XFF: 9.9.9.9`
  spoof test does NOT log 9.9.9.9 (audit-integrity for L1B).
- L2: `audit-tail`/`auth-recent`/`auth-failed`/`auth-user`/`oauth2-tokens`
  produce clean filtered output; `vlogs-query` reaches 14d history.
- L3: `session-status <user>` lists sessions; `session-destroy` revokes one
  and it disappears.
- L4 (if pursued): traces with `service.name=kanidmd`; kanidm→collector
  egress allowed by CCNP and visible in Hubble.


## Probe results — L1A XFF probe (session 2026-07-20, post-reconcile)

Env live on the kanidm pod (`KANIDM_TRUST_X_FORWARDED_FOR=true`). Two UI logins
(LAN then 5G) + one LAN curl spoof test (`X-Forwarded-For: 9.9.9.9`); the 5G
curl timed out (could not connect on 443) → no external spoof data.

`connection_address` = TCP source (always an Envoy gateway pod IP).
`client_address` = XFF-derived value (now populated by the trust-all env).

| Event | connection_address | client_address | Verdict |
|---|---|---|---|
| LAN UI login (passkey → Success) | 10.244.0.206 (envoy-internal) | **192.168.1.100** (real LAN IP) | real IP ✅ |
| 5G UI login (passkey → Success) | 10.244.0.229 (envoy-external) | **2a00:1110:201:a1e8:…:fa58** (real public IPv6) | real IP ✅ — NOT cloudflared pod IP |
| LAN curl XFF:9.9.9.9 ("RBAC: access denied") | — | **9.9.9.9 absent from log** | internal-path spoof did not pollute audit ✅ |
| 5G curl | — | — (timeout, never reached kanidm) | no data |

Full auth flow visible on both logins: `Initiating Authentication Session` →
`Auth result: Choose(passkey)` → `Continue (Passkey)` → `Issuing Cookie session`
→ `Success(Cookie)` → `Persisting auth session` — matches the L2 filter pattern.

### Key findings

1. **Critical unknown resolved POSITIVELY**: the external (Cloudflare/5G) path
   surfaces the **real public client IP** (2a00:…), NOT the cloudflared pod IP.
   envoy-external appends the real client IP to the upstream XFF (from
   CF-Connecting-IP). → **Phase 2 Envoy-side XFF fix is NOT needed; L1B proceeds directly.**
2. **Internal-path spoof blocked**: 9.9.9.9 never reached the kanidm audit log.
   Either envoy-internal `numTrustedHops: 0` stripped the client XFF, or the
   "RBAC: access denied" response came from an Envoy-side RBAC/SecurityPolicy
   (no `uri: /` in the kanidm log → request may not have reached kanidm). Both
   are good for audit integrity. OPEN: if the latter, there is an undocumented
   Envoy RBAC on the kanidm route worth tracing separately (non-blocking).

### Gap

External-path spoof test not obtained (5G curl timed out at the network level).
Not blocking for L1B — its spoof-resistance is by construction (right-walk XFF
trusts only pod-CIDR entries; client-injected left-side XFF is never reached).
The post-L1B verification step will confirm empirically.

## Decision

L1B is the next step (both paths surface the real IP via XFF). L1A env will be
reverted in the same L1B commit.

## Next (L1B implementation)

1. Add `kubernetes/apps/security/kanidm/app/config/server.toml`:
   `version = "2"` + `[http_client_address_info] x-forward-for = ["10.244.0.0/16"]`.
2. `configMapGenerator` entry in `app/kustomization.yaml` (model on
   `kanidm-theme`, reuse `disableNameSuffixHash`).
3. `persistence` mount in `helmrelease.yaml` (`/config/server.toml`, alongside `theme`).
4. `KANIDM_CONFIG: /config/server.toml` env; REMOVE `KANIDM_TRUST_X_FORWARDED_FOR`.
5. `kanidmd configtest` in the live pod; Flux reconcile.
6. Verify: LAN + 5G login → real client_address; spoof test → not 9.9.9.9.
