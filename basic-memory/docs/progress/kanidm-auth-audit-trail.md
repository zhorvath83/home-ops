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
