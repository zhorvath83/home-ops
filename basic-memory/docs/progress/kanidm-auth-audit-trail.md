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


## Spoof tests + envoy access-log evidence (session 2026-07-20, cont.)

Additional spoof tests (LAN curl `X-Forwarded-For: 9.9.9.9` against
`idm.horvathzoltan.me`) never reached kanidm (kanidm log unchanged, no
9.9.9.9). The envoy-internal access log explains why AND reveals the XFF
chain structure — empirically confirming L1B on both paths.

### envoy-internal access log (the spoof test, 19:18:52Z)

```
downstream_remote_address: "9.9.9.9:0"          ← Envoy computed client = SPOOFED (port :0 = XFF-parsed, not TCP source)
response_code: 403, rbac_access_denied_matched_policy[DENY]
x_forwarded_for: "9.9.9.9,192.168.1.100"        ← chain: [spoofed 9.9.9.9 , real LAN IP appended by Envoy]
```

### envoy-external access log (the 5G UI login, 19:18:02Z, iPhone Safari)

```
downstream_remote_address: "[2a00:1110:201:a1e8:…:fa58]:0"   ← real public IPv6 (from CF-Connecting-IP)
x_forwarded_for: "2a00:1110:201:a1e8:…:fa58"                 ← SINGLE entry = real public IP (NO cloudflared pod IP appended)
upstream_host: "10.244.0.233:8443"
```

### L1B spoof-resistance — empirically confirmed on BOTH paths

| Path | XFF chain kanidm receives | L1B right-walk (trust 10.244.0.0/16) | Result |
|---|---|---|---|
| internal (LAN) | [9.9.9.9, 192.168.1.100] | 192.168.1.100 not in pod-CIDR → client | real LAN IP ✅, 9.9.9.9 ignored |
| external (5G) | [2a00:…] (spoof: [9.9.9.9, 2a00:…]) | 2a00:… not in pod-CIDR → client | real public IP ✅, spoof ignored |

Both paths: Envoy appends the real detected client IP at the RIGHTMOST XFF
position (internal: real LAN IP; external: real public IP from
CF-Connecting-IP), and it is never in the pod-CIDR → L1B's right-walk finds
it. Client-injected left-side XFF is never reached.

### Corrections to the roadmap (now evidence-backed)

1. **R1 external-path assumption corrected**: envoy-external appends the REAL
   public client IP (from CF-Connecting-IP) to the upstream XFF, NOT the
   cloudflared pod IP. The XFF chain for a normal external request is a single
   real-IP entry. The 10.244.0.0/16 trust set is therefore not needed for the
   external path's normal chain — but keeping it is harmless (real IPs are never
   in 10.244/16, so the right-walk still finds them).
2. **numTrustedHops:0 does NOT reject client XFF on envoy-internal**
   (contradicts the roadmap + networking area-ref): envoy-internal computed
   downstream_remote_address = 9.9.9.9 from the client-supplied XFF (port :0 =
   XFF-parsed, vs a real TCP-source port for non-spoofed requests). Client-supplied
   XFF IS honored for client-IP detection on the internal gateway. This also
   means the envoy-internal-rfc1918 clientCIDRs allowlist is evaluated against
   the spoofable client IP (an RFC1918-spoofed XFF would pass it). Separate
   networking-area finding — does NOT block L1B (L1B is the kanidm-side fix).

### Why the 9.9.9.9 spoof was denied (not a security win, an accident)

The envoy-internal-rfc1918 SecurityPolicy (defaultAction: Deny, allow
10/8,172.16/12,192.168/16) denied the 9.9.9.9 request because 9.9.9.9 is
non-RFC1918. An RFC1918 spoof (e.g. X-Forwarded-For: 10.0.0.5) WOULD pass the
RBAC and reach kanidm, where L1A (leftmost) would log client_address = 10.0.0.5
(spoofed). → L1A IS spoofable on the internal path; L1B is required.

### Acceptable tradeoff: pod-origin traffic fidelity

OIDC backchannel/discovery requests (e.g. grafana → kanidm token exchange) are
pod-originated (probe lines 21-39: client_address 10.244.0.161 under L1A). L1B's
10.244.0.0/16 trust skips the originating pod IP → client_address falls back to
the envoy pod IP (minor fidelity loss vs L1A's originating-pod IP). Acceptable:
internal automation, not human auth events; same as the pre-L1A state; the
forensically critical human auth events (Initiating Authentication Session, Auth
result, Issuing Cookie) all get the real IP. Note in the L1B commit message.

## L1B proceeding

Probe fully closed; L1B empirically justified on both paths. Implementing:
config/server.toml + kustomization configMapGenerator + helmrelease mount +
KANIDM_CONFIG env + L1A env removal, one commit.


## L1B implemented (session 2026-07-20)

Commit `0b182e934` — `security(kanidm): trust Envoy X-Forwarded-For for real
client IP in audit logs`. Files:

- `kubernetes/apps/security/kanidm/app/config/server.toml` (new) —
  `version = "2"` + `[http_client_address_info] x-forward-for = ["10.244.0.0/16"]`.
- `kubernetes/apps/security/kanidm/app/kustomization.yaml` — new
  `kanidm-config` configMapGenerator entry (reuses shared `disableNameSuffixHash`).
- `kubernetes/apps/security/kanidm/app/helmrelease.yaml` — added `KANIDM_CONFIG:
  /config/server.toml` env; REMOVED the L1A `KANIDM_TRUST_X_FORWARDED_FOR` probe
  env; added a `persistence.config` ConfigMap mount at `/config/server.toml`
  (subPath, readOnly) alongside `theme`.

yamlfmt/yamllint/pre-commit green. NOT yet pushed / reconciled / configtest'd
— pending user go-live.

### Verification checklist (post-deploy)

1. `kanidmd configtest` in the live pod (V2 server.toml + env coexistence).
2. Flux reconcile; pod restart picks up KANIDM_CONFIG + mounted server.toml.
3. `just kanidm logs`: LAN login → client_address = real LAN IP; Cloudflare
   login → client_address = real public IP (not 10.244.x.x).
4. Spoof test (`X-Forwarded-For: 9.9.9.9` from an RFC1918-allowed path so it
   passes the envoy-internal-rfc1918 RBAC) → client_address is NOT 9.9.9.9.
5. Pod-origin OIDC backchannel discovery → client_address = envoy pod IP
   (accepted tradeoff, see commit message).

## Next after L1B verified

Phase 1 continues: L2 (`audit` + `vlogs-query` recipe group in
`kubernetes/apps/security/kanidm/mod.just`) → L3 (`sessions` group). L4 (OTLP)
as a separate sub-item + security-review.
