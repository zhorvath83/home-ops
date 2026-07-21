---
title: kanidm-auth-audit-trail
type: roadmap
permalink: home-ops/docs/roadmap/kanidm-auth-audit-trail
topic: Make Kanidm authentication events observable and durable
status: in-progress
priority: medium
scope: Close the four gaps that make the IdP an audit black box today — (1) client-IP
  fidelity behind Envoy is lost, (2) auth events only live in the pod stdout buffer
  + VictoriaLogs with no operational recipes, (3) no surface to list/revoke live user
  sessions, (4) no structured export path. Deliver a forensic-grade auth-audit trail
  aligned with Kanidm's documented OpenTelemetry direction.
rationale: Kanidm already emits rich auth-audit events at the default `info` log level,
  but they currently show the Envoy gateway pod IP as `client_address` (forensically
  useless), live only in the pod stdout buffer plus an un-gated VictoriaLogs store
  with no query recipes, and there is no operational way to list or revoke active
  user sessions. Closing these turns the IdP from a black box into an auditable trust
  boundary — "who authenticated, from where, when, and who is logged in right now"
  becomes answerable.
related_areas:
- iam
- observability
- networking
options:
- L1 Client-IP fidelity fix (config — verify XFF behaviour, then env or mounted server.toml)
- L2 stdout auth-event mining recipes (just kanidm audit group) + optional vlogs-query
- L3 Live session recipes via CLI (just kanidm sessions group)
- L4 OpenTelemetry OTLP tracing path (new in-cluster infra)
---

# Kanidm auth-audit trail

## Metadata (observation-form, schema validation)

- [topic] Make Kanidm authentication events observable and durable
- [status] in-progress
- [priority] medium
- [areas] iam, observability, networking

## What we gain

- Auth events become forensically useful: `client_address` shows the real user IP, not the Envoy pod IP.
- "Who authenticated / failed / from where / when" is one just recipe away, with 14d durable history queryable via VictoriaLogs.
- "Who is logged in right now" is answerable via the CLI (`kanidm person session status`) and revocable on demand (`session destroy`).
- A structured, docs-blessed export path (OTLP) becomes available for span-level correlation with the rest of the platform once an OTel backend is stood up.

## What to do

1. **L1 — Client-IP fidelity**: verify Envoy→XFF + kanidm XFF-parsing behaviour, then tell kanidm to trust Envoy's `X-Forwarded-For` so audit events carry the real user IP (see Risks #1–#2 before choosing env vs server.toml).
2. **L2 — stdout auth-event mining**: add a `just kanidm audit` recipe group that filters the server logs to auth events (tail / recent / failed / per-user / oauth2-token-issuance); optionally a `vlogs-query` recipe for the 14d durable history.
3. **L3 — Live sessions**: add a `just kanidm sessions` recipe group wrapping `kanidm person session status|destroy`.
4. **L4 — OTLP tracing**: set `KANIDM_OTEL_GRPC_URL` and stand up an in-cluster OTel collector + trace backend (separate, larger phase).

## Options

1. **L1 Client-IP fidelity fix (config)** — env var or mounted `server.toml`; choice gated on XFF-verification (see execution plan).
2. **L2 stdout auth-event mining recipes** — `audit` group on `kubectl logs statefulset/kanidm` + optional `vlogs-query`.
3. **L3 Live session recipes (CLI)** — `sessions` group on the existing client-pod pattern.
4. **L4 OTLP tracing path** — `KANIDM_OTEL_GRPC_URL` + OTel collector + backend (Tempo / VictoriaTraces; external backend flagged out on privacy grounds).

## Related

- relates_to [[iam]]
- relates_to [[observability]]
- relates_to [[networking]]
- relates_to [[AD-023-cnp-threat-model-audit]]

## Evidence base (research-backed)

### Kanidm server already logs auth-audit events at `info` level (live evidence)

`kubectl -n security logs statefulset/kanidm` at the current default log level (no `KANIDM_LOG_LEVEL` set → defaults to `info`, `server/core/src/config.rs:292-293`) emits, with a `kopid` correlation ID and `client_address`:

- `Initiating Authentication Session | username: <user>@idm.<DOMAIN> | issue: Cookie | privileged: false | uuid: …`
- `Auth result: Choose(passkey)` / `Continue (Passkey)` / `Success(Cookie)` (and `Denied` — not observed in sample, see Risks #3)
- `Issuing Cookie session (privilege_capable) <session-id> for <user>`
- `Persisting auth session | session_id: …`
- `handle_oauth2_token_exchange` (OAuth2 token issuance — which RS got a token; the client_id is NOT in this event line, see Risks #4)
- `handle_oauth2_openid_userinfo`
- `Invalid identity: NotAuthenticated` (ERROR)

**Critical finding**: every `client_address` in the current logs is an Envoy gateway pod IP (e.g. `::ffff:10.244.0.76`), never the real user IP. Cause: `[http_client_address_info]` is unset → `HttpAddressInfo::None` (default) → the server ignores `X-Forwarded-For` and records the TCP source, which is Envoy. (`server/core/src/config.rs:183-197`, `:441`)

### Kanidm documentation (authoritative)

- [Monitoring the platform](https://kanidm.github.io/kanidm/stable/monitoring_the_platform.html): **no built-in audit-log subsystem**; "The monitoring design of Kanidm is still very much in its infancy" (GitHub #216). The docs-blessed structured-export path is **OpenTelemetry OTLP tracing** via `otel_grpc_url` / `KANIDM_OTEL_GRPC_URL` (+ `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_SERVICE_NAME`, default `kanidmd`). `/status` health endpoint + `x-kanidm-opid` header.
- [Server configuration](https://kanidm.github.io/kanidm/stable/server_configuration.html): `[http_client_address_info]` table accepts `x-forward-for` / `proxy-v2` / `proxy-v1` (list of trusted CIDRs); default `none` (no trusted sources). `log_level` = `info|debug|trace`, overridable by `KANIDM_LOG_LEVEL`.
- [Security hardening](https://kanidm.github.io/kanidm/stable/security_hardening.html): no audit-logging section (file perms / non-root / TLS key minimums only) — confirms there is no documented built-in audit log.
- [Client tools](https://kanidm.github.io/kanidm/stable/client_tools.html): `kanidm session list/cleanup` = **client-side local token store**, not an audit surface.

### Kanidm source v1.10.4 (`server/core/src/config.rs`) — env-var vs server.toml for L1

- `HttpAddressInfo` enum (`:183-197`): `None` (default), `XForwardFor(Vec<IpCidr>)` (`x-forward-for`), `XForwardForAllSourcesTrusted` (`x-forward-for-all-source-trusted` — comment `:189-192`: *"This is undocumented, and only exists for backwards compat with config v1"*), `ProxyV2`/`ProxyV1`.
- **Two code paths yield `XForwardForAllSourcesTrusted`**, and they are NOT the same setting:
  - **CLI flag** `--trust-all-x-forwarded-for` → `cli_config.trust_all_x_forwarded_for` (`:771`). NOT env-overlayable.
  - **ENV var** `KANIDM_TRUST_X_FORWARD_FOR=true` → `ServerConfig.trust_x_forward_for` (`:299`, on the env-overlayable `ServerConfig` struct at `:262`; doc comment `:252-256`: *"Server Configuration as read from `server.toml` or environment variables … prefix them with `KANIDM_`"*) → applied at `:853-854` (`if config.trust_x_forward_for == Some(true) { self.http_client_address_info = HttpAddressInfo::XForwardForAllSourcesTrusted; }`). **This is the env var to use for L1A.**
- **Trust-set semantics** (`:200-206`): `XForwardForAllSourcesTrusted => AddressSet::All` (`:202`) — every XFF source is trusted. `XForwardFor(trusted) => AddressSet::NonContiguousIpSet(trusted)` (`:203`) — only the listed CIDRs are trusted; the HTTP layer walks XFF from the right, skipping trusted proxies, and takes the first untrusted entry as the client. **This difference is security-relevant** (see Risks #1–#2).
- **TOML form** `[http_client_address_info] x-forward-for = ["CIDR", …]` → `XForwardFor([trusted CIDRs])` — the documented, least-trust form. Only parseable from a `server.toml` file; there is **no env flattening for this table** (the comma-split at `:660-667` is for `bindaddress`/`ldapbindaddress` only).
- `otel_grpc_url: Option<String>` (`:319`, `:406`) — OTLP trace export endpoint; unset → disabled.

### Repo facts (cited)

- **Envoy XFF**: Envoy appends the downstream remote address to XFF by default (no explicit add/remove in `kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml`; identity-header stripping at `:55-65` and `:99-106` does not touch XFF). `envoy-external` Service is `type: ClusterIP` (`envoy.yaml:41-42`) fronted by cloudflared → Envoy sees cloudflared pod IP as TCP source; `clientIPDetection.customHeader.name: CF-Connecting-IP`, `failClosed: false` (`gateway-policies.yaml:49-52`). `envoy-internal` Service is `type: LoadBalancer` with `externalTrafficPolicy: Local` (`envoy.yaml:117-119`) → preserves LAN client IP at LB→Envoy; `clientIPDetection.xForwardedFor.numTrustedHops: 0` (`gateway-policies.yaml:93-95`) → **envoy-internal rejects client-supplied XFF**. **In both paths the backend pod (kanidm) sees the Envoy gateway pod IP as TCP source; the real client IP is conveyed only via the XFF header Envoy appends.** Whether Envoy appends the *real* client IP (CF-Connecting-IP for external, TCP source for internal) vs the cloudflared/envoy pod IP into the upstream XFF is **not verified** (Risks #1).
- **kanidm ingress restriction (the L1A safety basis)**: the per-app kanidm CNP (`kubernetes/apps/security/kanidm/app/ciliumnetworkpolicy.yaml`) is **egress-only** (`spec.egress: []`, no `ingress:` section). Ingress is restricted by the **cluster-wide CCNPs** `ingress-from-gateway-external` and `ingress-from-gateway-internal` (`kubernetes/apps/kube-system/cilium/netpols/ingress-from-gateway-external.yaml`, `…-internal.yaml`), which select pods carrying `ingress.home.arpa/allow-gateway-external`/`allow-gateway-internal` labels and allow ingress ONLY from `envoy-external`/`envoy-internal` pods respectively. The kanidm pod carries both labels (`helmrelease.yaml:19-22`), so it is in Cilium ingress-enforcement mode and is reachable on `:8443` **only from the two Envoy gateway pods**. This blocks cluster-pod XFF spoofing but **not external-client XFF spoofing** (Risks #2).
- **VictoriaLogs query endpoint**: `logs.${PUBLIC_DOMAIN}` HTTPRoute attaches to `envoy-internal` only (NOT external) — `kubernetes/apps/observability/victoria-logs/app/helmrelease.yaml:27-53`. **No `SecurityPolicy`/OIDC/basic-auth/Cloudflare-Access** on it; the only gates are the Gateway-wide `envoy-internal-rfc1918` SecurityPolicy (default-deny, allow RFC1918, `gateway-policies.yaml:202-220`) and the vlogs CNP (ingress `:9428` from collector + gateway, `ciliumnetworkpolicy.yaml:17-34`). vlogs HTTP query API (`/select/logsql/query`, `/select/vmui/`) is served on `:9428`, exposed on the internal gateway with no app-level auth. Collector ships every pod's stdout to vlogs (14d retention, `victoria-logs/app/helmrelease.yaml`).
- **No OTel collector / Tempo / Jaeger / Loki anywhere** in `kubernetes/` (`kubernetes/apps/observability/kustomization.yaml:8-16` = namespace, kube-prometheus-stack, grafana, speedtest-exporter, victoria-logs, blackbox-exporter, prometheus-adapter, silence-operator). Grafana is grafana-operator-provisioned with **no Tempo datasource / tracing config**. No OTLP receiver (`:4317/:4318`) exists in-cluster.
- **Kanidm config form**: entirely `KANIDM_*` env vars, no `server.toml` mounted — `kubernetes/apps/security/kanidm/app/helmrelease.yaml:43-51` (`KANIDM_ADMIN_BIND_PATH`, `KANIDM_DOMAIN`, `KANIDM_ORIGIN`, `KANIDM_BINDADDRESS`, `KANIDM_DB_PATH`, `KANIDM_TLS_CHAIN`, `KANIDM_TLS_KEY`). `readOnlyRootFilesystem: true` (`:68`) → any config file must come via a mount. **Precedent for a ConfigMap-mounted file**: the `theme` ConfigMap (`configMapGenerator kanidm-theme` from `config/override.css`, `disableNameSuffixHash: true`, `kustomization.yaml:9-14`; mount `helmrelease.yaml:100-106`). A `server.toml` can be added the same way.
- **Existing just module**: `kubernetes/apps/security/kanidm/mod.just` — `status`, `logs` (raw `kubectl logs statefulset/kanidm -f --tail=100`), client-pod pattern (`ensure-client`/`ensure-login`), `run` escape hatch, `entity-exists` probe, person/group/oauth2 recipes + wizards.

## Execution plan

### Current state

- Auth events are logged at `info` and shipped to VictoriaLogs (14d) cluster-wide by `victoria-logs-collector` — but unreachable operationally except via the raw `just kanidm logs` follow or the un-gated vlogs UI.
- `client_address` is the Envoy pod IP on every event → "from where" is unanswerable.
- No CLI surface is wired for `kanidm person session status|destroy` (the command exists — verified from the live pod's `kanidm person session --help` — but no recipe wraps it).
- No OTLP/trace infrastructure exists; `KANIDM_OTEL_GRPC_URL` is unset.

### Target state

- kanidm audit events carry the real user IP for both external (Cloudflare) and internal (LAN) traffic, robust to client-supplied XFF injection.
- `just kanidm audit …` filters server logs to auth events; `just kanidm vlogs-query …` (optional) queries the 14d durable history; `just kanidm sessions …` lists/revokes live sessions.
- (Phase 3, optional) kanidm auth spans flow to an in-cluster OTel backend.

### Layer 1 — Client-IP fidelity

**Verify before choosing (Risks #1–#2).** The choice between env and server.toml is NOT just a convenience trade-off — it changes the XFF trust-set (`AddressSet::All` vs `AddressSet::NonContiguousIpSet`) and therefore the audit-integrity posture.

- **L1A — env var (quick experiment, audit-integrity caveat).** Add `KANIDM_TRUST_X_FORWARD_FOR: "true"` to the kanidm container env block (`helmrelease.yaml:43-51`). Enables `XForwardForAllSourcesTrusted` = `AddressSet::All` (`config.rs:202`) — **trusts every XFF entry from every source**. The cluster-wide `ingress-from-gateway-*` CCNPs block cluster-pod XFF spoofing (only Envoy pods reach kanidm), but **external clients can still inject `X-Forwarded-For` headers** that flow through Envoy into the audit log → the logged `client_address` is spoofable from the internet. Acceptable only if audit-integrity against external clients is not required, or if Envoy is confirmed to strip/overwrite client-supplied XFF (it does NOT today on envoy-external; envoy-internal does via `numTrustedHops: 0`).
  - **Caveat**: the variant is "undocumented, backwards-compat" (`config.rs:189-192`) — could be removed upstream.
- **L1B — mounted `server.toml` (likely the correct endpoint).** Add `config/server.toml` with:
  ```toml
  [http_client_address_info]
  x-forward-for = ["10.244.0.0/16"]
  ```
  (cluster pod CIDR covers both envoy-external and envoy-internal gateway pods). `XForwardFor([envoy CIDR])` = `AddressSet::NonContiguousIpSet` (`:203`); the HTTP layer walks XFF from the right, skips the trusted envoy entry, and takes the first untrusted entry as the client → **robust to client-supplied XFF injection** (injected values sit to the left and are never reached), PROVIDED Envoy appends the real client IP (CF-Connecting-IP for external, TCP source for internal) to the right of the chain. Requires: new `config/server.toml`, a `configMapGenerator` key in `app/kustomization.yaml` (reuse `disableNameSuffixHash`), a `persistence` mount in `helmrelease.yaml` alongside `theme`, and pointing `kanidmd` at the file (verify the config-path flag/env at implementation time — currently all config is env).

**Recommendation**: **do not ship L1A blindly.** First run the Risk #1 verification (log in via Cloudflare and via LAN, observe `client_address`). If Envoy appends the real client IP to XFF, ship L1B (CIDR list) as the correct endpoint — it is both safer (audit-integrity) and documented. Keep L1A only as a throwaway probe to confirm XFF flows at all. If Risk #1 shows Envoy does NOT append the real IP (only the cloudflared pod IP), the fix is on the Envoy side first (a `ClientTrafficPolicy`/`EnvoyPatchPolicy` to set upstream XFF from `CF-Connecting-IP` and strip client-supplied XFF on envoy-external), and L1B is applied after that.

**Implementation steps (L1B, post-verification)**:
1. Add `kubernetes/apps/security/kanidm/app/config/server.toml` with the `[http_client_address_info]` block above.
2. Add it to the `configMapGenerator` in `app/kustomization.yaml` (new key alongside `override.css`, reuse `disableNameSuffixHash`).
3. Add a `persistence` mount in `helmrelease.yaml` (alongside `theme`) projecting the ConfigMap file; confirm the `kanidmd` config-path flag/env (verify via `kanidmd --help` / rustdoc `ServerConfig` loader).
4. Commit: `🔒 security(kanidm): trust Envoy X-Forwarded-For for real client IP in audit logs`.
5. Let Flux reconcile; `just k8s flux-reconcile` if needed.

### Layer 2 — stdout auth-event mining recipes

New `audit` group in `kubernetes/apps/security/kanidm/mod.just`. Recipes read `kubectl -n security logs statefulset/kanidm` (pod buffer) — no client-pod dependency (standalone like `logs`). Note the buffer limitation in the recipe docs; the durable 14d store is VictoriaLogs (see optional `vlogs-query` below).

- `auth-tail` — `kubectl logs -f`, piped to a grep matching the auth-audit lines: `Initiating Authentication Session|Auth result|Issuing Cookie session|Persisting auth session|Invalid identity|handle_oauth2_token_exchange`.
- `auth-recent <N=200>` — snapshot `kubectl logs --tail=<N>` filtered to the same auth pattern (no `-f`).
- `auth-failed` — filter for `Auth result: Denied|Invalid identity|ERROR|softlock|CredentialError` — **exact denied/softlock strings must be confirmed from a live failed login before finalizing** (Risks #3); some may only appear at `KANIDM_LOG_LEVEL=debug` (Risks #5).
- `auth-user <user>` — filter auth events for one user (`username: <user>@` and `for <user>@`).
- `oauth2-tokens` — `handle_oauth2_token_exchange` events; **correlate by `kopid` to the `POST /oauth2/token` request URI / `GET /ui/oauth2?...client_id=…` query to surface which RS got the token** (the token-exchange event line itself carries no client_id — Risks #4).
- **Optional `vlogs-query <query>`** — query the 14d durable history via the vlogs HTTP API (`/select/logsql/query`) on `logs.${PUBLIC_DOMAIN}` (internal gateway, RFC1918 gate, no app-auth — Risks #6). This is the first-class path to "last week's failed logins" that `kubectl logs` cannot reach. Recommend making this a real deliverable, not an aside.

Implementation steps:
1. Add the `audit` group recipes to `mod.just`, modeled on the existing `logs` recipe.
2. Optionally add `vlogs-query` (decide whether the no-app-auth exposure model is acceptable — Risks #6).
3. Local smoke-test each recipe against live logs (trigger a failed login to capture `auth-failed` strings).
4. Commit: `✨ feat(kanidm): add audit log-mining recipes`.

### Layer 3 — Live session recipes (CLI)

New `sessions` group in `mod.just`, on the existing client-pod pattern (`ensure-login`):
- `session-status <user>` → `kanidm person session status <user> -D idm_admin` (DB-backed, survives pod restart).
- `session-destroy <user> <uuid>` → `kanidm person session destroy <user> <uuid> -D idm_admin`, gated by `gum confirm` (destructive to that user's session; not a cluster-mutating action per `.claude/settings.json`, but a user-facing mutation → confirm).

Implementation steps:
1. Add the `sessions` group to `mod.just` modeled on the `person-*` recipes (`ensure-login` dependency, `-D idm_admin`).
2. Smoke-test: `session-status <user>` lists sessions; `session-destroy` revokes one and it disappears from `session-status`.
3. Commit: `✨ feat(kanidm): add live session status/destroy recipes`.

### Layer 4 — OTLP tracing path (larger, separate phase)

Set `KANIDM_OTEL_GRPC_URL` + stand up an in-cluster OTel collector + trace backend. Backend options:
- (a) **Tempo** — Grafana ecosystem; add a Tempo datasource to the grafana-operator `Grafana` spec.
- (b) **VictoriaTraces** — stay in the VictoriaMetrics ecosystem (verify production-readiness at implementation time).
- (c) ~~External managed backend (Grafana Cloud / Honeycomb)~~ — **flagged out on privacy grounds**: it exports auth trace data (user identities, client IPs) to a third party, conflicting with the repo's "treat as potentially public" / no-external-identifiers posture and adding an external egress dependency.

Implementation steps (sketch):
1. Decide backend; deploy collector + backend under `kubernetes/apps/observability/` (new subdir, Flux-wired).
2. Set `KANIDM_OTEL_GRPC_URL: http://otel-collector.<ns>.svc:4317` + `OTEL_SERVICE_NAME: kanidmd` (+ `OTEL_EXPORTER_OTLP_HEADERS` if the collector requires auth) on the kanidm container.
3. Add a CCNP for kanidm → collector egress (kanidm currently has `egress.home.arpa/custom-egress` and an empty egress CNP → no outbound path; this is a new egress path that must be explicitly allowed and audited under AD-023).
4. Verify traces appear with `service.name=kanidmd` and auth spans.

**Note**: L4 is not a prerequisite for an audit trail — L2 already covers audit coverage via stdout → VictoriaLogs (14d). L4 buys span correlation and structured fields. Gate L4 on a separate backend + resource-cost decision; likely its own roadmap sub-item if pursued.

### Sequencing

- **Phase 0 (verification, blocking L1)**: run Risk #1 — log in via Cloudflare and via LAN, observe `client_address` in raw `just kanidm logs`. Determine whether Envoy appends the real client IP to XFF.
- **Phase 1 (quick wins, one PR each)**: L1 (A or B per Phase 0) → L2 → L3. Immediate audit value.
- **Phase 2 (hardening)**: if Phase 0 showed Envoy does not append the real IP for external traffic, add the Envoy `ClientTrafficPolicy`/`EnvoyPatchPolicy` to set upstream XFF from `CF-Connecting-IP` and strip client-supplied XFF on envoy-external, then apply L1B. Confirm L1B `client_address` is real and not spoofable.
- **Phase 3 (structured export, optional)**: L4 — gated on a trace-backend + resource-cost decision.

## Verification

- **L1**: `just kanidm logs` (or `auth-tail` after L2) — log in from an external (Cloudflare) and an internal (LAN) client; confirm `client_address:` shows the real user IP, not `10.244.x.x`. Then attempt to spoof with a client-supplied `X-Forwarded-For: 9.9.9.9` header and confirm the logged IP is NOT `9.9.9.9` (audit-integrity check for L1B).
- **L2**: `just kanidm auth-tail` / `auth-recent` / `auth-failed` / `auth-user <u>` / `oauth2-tokens` produce clean filtered output; a known login appears in `auth-tail` and `auth-user`; `oauth2-tokens` shows the RS client_id via kopid correlation.
- **L3**: `just kanidm session-status <user>` lists active sessions; `session-destroy <user> <uuid>` revokes one, it disappears from `session-status`, and the user is logged out.
- **L4 (if pursued)**: traces appear in the backend with `service.name=kanidmd` and auth spans; kanidm pod egress to the collector is allowed by CCNP and visible in Hubble.

## Risks & open questions

1. **Envoy→XFF behaviour unverified (blocking L1).** Envoy's `clientIPDetection` on `envoy-external` reads `CF-Connecting-IP` for its own purposes, but what Envoy **appends to the upstream XFF** to kanidm is not verified — it may append only the cloudflared pod IP, not the real user IP. If so, NO kanidm-side setting surfaces the real external IP; an Envoy `ClientTrafficPolicy`/`EnvoyPatchPolicy` to set upstream XFF from `CF-Connecting-IP` is required first. Internal (LAN) traffic is expected to work (envoy-internal `externalTrafficPolicy: Local` + `numTrustedHops: 0`). **Verify empirically before L1.**
2. **External-client XFF spoofing / audit integrity (the L1A-vs-L1B decider).** `XForwardForAllSourcesTrusted` (L1A) = `AddressSet::All` — trusts every XFF entry. The `ingress-from-gateway-*` CCNPs block cluster-pod spoofing but NOT external-client spoofing: an internet client can send `X-Forwarded-For: <fake>` and pollute the audit log. `XForwardFor([envoy CIDR])` (L1B) walks XFF from the right and ignores left-side injected entries → robust, provided Risk #1 holds. **Prefer L1B; treat L1A as a probe only.** Confirm by spoofing `XFF: 9.9.9.9` and checking the logged IP is not `9.9.9.9`.
3. **`auth-failed` filter strings unconfirmed.** The live log sample showed `Success/Choose/Continue` and `Invalid identity: NotAuthenticated` but no `Denied` or softlock event. Trigger a failed login (wrong passkey / locked account) and capture the exact strings before finalizing the `auth-failed` grep pattern. Some denial/softlock events may only surface at `KANIDM_LOG_LEVEL=debug` — weigh the perf/log-volume cost before bumping the level cluster-wide.
4. **`oauth2-tokens` client_id.** The `handle_oauth2_token_exchange` event line carries no client_id; surface it by correlating `kopid` to the `POST /oauth2/token` request URI or the `GET /ui/oauth2?...client_id=…` query string.
5. **L1B `server.toml` path mechanism.** Currently all kanidm config is env-based; the exact flag/env to point `kanidmd` at a mounted `server.toml` must be confirmed against `kanidmd --help` / the rustdoc `ServerConfig` loader at implementation time. `readOnlyRootFilesystem: true` means the file must come via a ConfigMap mount (precedent: `theme`).
6. **VictoriaLogs query exposure model.** `logs.${PUBLIC_DOMAIN}` has no app-level auth (RFC1918 network gate only). An optional `vlogs-query` recipe hitting the HTTP API inherits that exposure model — acceptable for LAN-only, but decide explicitly. The durable 14d history is reachable via the vlogs UI regardless; L2 covers the pod-buffer operational path.
7. **L4 egress.** kanidm currently has `egress.home.arpa/custom-egress` and an empty egress CNP → no outbound path. OTLP export requires a new kanidm → collector CCNP egress rule (and the collector must be reachable). New egress surface to audit under AD-023.
8. **Env var name empirical confirmation.** The source analysis (`config.rs:262/299/853`) identifies `KANIDM_TRUST_X_FORWARD_FOR=true` as the env var for L1A, distinct from the CLI flag `--trust-all-x-forwarded-for` (`:771`). Confirm by setting it and observing `client_address` change (or via `kanidmd --help` / a debug print) before relying on it.


## Refinements — critical review 2026-07-20

A manifest-level verification pass (kanidm HelmRelease/CNP/kustomization, envoy-gateway
gateway-policies, ingress-from-gateway-* CCNPs, victoria-logs HelmRelease/CNP, envoy service
types) confirmed the evidence base and surfaced seven corrections/additions. The L1–L4
skeleton stands; the items below refine it to a worked-out plan.

### R1 — L1B CIDR rationale corrected (the XFF trust-set is over *XFF entries*, not TCP source)

The original L1B text said the trusted CIDR `10.244.0.0/16` "covers both envoy-external and
envoy-internal gateway pods". **That conflates the TCP source with the XFF entry.** Kanidm
`XForwardFor([trusted CIDR])` walks the XFF list from the right and trusts *XFF entries* in
the CIDR, not the pod that opened the TCP connection. What Envoy appends to the upstream XFF is
its *downstream remote address* (who connected to Envoy), which is **not** the Envoy pod's own IP:

- **envoy-external**: Envoy downstream remote = **cloudflared pod IP** (10.244.x.y); Cloudflare
  already wrote the real client IP to the left of the chain. Walk right→left: 10.244.x.y
  (trusted) skipped → real IP recorded as client. ✓
- **envoy-internal**: `externalTrafficPolicy: Local` preserves the real LAN client IP as
  Envoy's downstream remote (e.g. 192.168.1.50) — **not** in 10.244.0.0/16, correctly taken as
  the client (that is what we want). ✓

So `10.244.0.0/16` works — but because it covers the **cloudflared/envoy pod IPs that Envoy
appends on the external path**, not because it "covers the gateway pods" as TCP sources. A
client-injected left-side `X-Forwarded-For: 9.9.9.9` is never reached by the right-walk. The
implementer must NOT narrow the CIDR to "envoy pod IPs only" (that would break the external
path, where the appended entry is the *cloudflared* pod IP). Keep the full pod CIDR; document
the per-path trust analysis (external: cloudflared-pod-IP trusted; internal: LAN-IP
untrusted-and-captured) in the L1B commit message, not the generic "covers gateway pods" line.

### R2 — vlogs ingestion is a blocking Phase 0 prerequisite, not a fact

The `observability` area-ref's own Open Questions list states the cluster log pipeline
indexing of security-namespace audit logs (Kanidm) into victoria-logs is **unconfirmed**. The
roadmap treats "14d durable history queryable via VictoriaLogs" as established. Insert as a
blocking Phase 0 step before L2's `vlogs-query` is promised:

```
just k8s vlogs-query '_namespace:security AND _pod:kanidm'   # or kubectl logs ds/victoria-logs-collector -n observability
```

If the collector is not ingesting the security namespace, L2's durable-history half is empty
and the deliverable shrinks to pod-buffer-only (`kubectl logs`, lost on reloader pod-recreate
— see R6).

### R3 — L3 may not surface `client_address`; verify before promising "from where"

`kanidm person session status` returns the DB-backed server-side session list, but it is
**unverified that it prints the session's `client_address`**. If it does not, L3 answers
"who is logged in / when" but NOT "from where" — the *where* for live sessions would then
require correlating each session-id to an L2 audit event by kopid. Add as a Risk and verify
on the live pod (`kanidm person session status --help` + one real session) before the
headline benefit is claimed. (Confirmed correct surface choice: `person session` is
server-side; `kanidm session list/cleanup` is the client-side token store and is NOT the
audit surface — the roadmap already picks the right one.)

### R4 — `oauth2-tokens` client_id may require L4, not L2

The `kopid` correlation assumed in Risk #4 presumes the same kopid spans the authorize
request (`GET /ui/oauth2?client_id=…`) and the token exchange (`POST /oauth2/token`).
These are distinct requests and may carry distinct kopids; if the kopid does not bridge
both, the client_id is **not recoverable from stdout**. Honest reframe: `oauth2-tokens`
without client_id is the L2 deliverable; `oauth2-tokens` *with* reliable client_id is an
L4 (OTLP structured-field) deliverable. Update the sequencing accordingly, or accept that
`oauth2-tokens` lists token issuances without naming the RS until L4 lands.

### R5 — L4 doctrinal tension with the "no legitimate egress" CNP posture (escalate Risk #7)

The kanidm CNP comment asserts: *"kanidm is a pure OIDC/LDAP server with no legitimate
outbound (no SMTP, no replication, no OCSP/CRL, no telemetry) … a compromised pod cannot
probe east-west or exfil."* OTLP export IS telemetry egress — it breaks that stated posture.
Two in-lockstep consequences the original Risk #7 under-stated:

1. The CNP comment's "no legitimate outbound" claim becomes **false** the moment
   `KANIDM_OTEL_GRPC_URL` is set — the comment must be rewritten alongside the egress rule,
   or the manifest self-contradicts.
2. The "compromised pod cannot exfil" guarantee is weakened: OTLP is a structured exfil
   channel if the collector is ever misconfigured or the kanidm pod is compromised. The
   collector-side mitigation (mutual TLS / header auth on the OTLP receiver, tight
   kanidm→collector:4317 CNP) must be part of the L4 design, not an afterthought.

L4 wiring is also heavier than the "sketch": the collector needs an OTLP receiver
(:4317/:4318) + its own ingress CNP admitting kanidm from the security namespace; the kanidm
CNP needs an egress rule to the collector Service. Treat L4 as its own roadmap sub-item with
a security-review pass, not a Phase 3 add-on.

### R6 — Forensic-durability gap: stdout buffer loss on reloader pod-recreate

The kanidm pod carries `reloader.stakater.com/auto: "true"` (`helmrelease.yaml:36`); every
secret rotation (`kanidm-tls`, future `kanidm-secret`) triggers a pod recreate. The
victoria-logs-collector scrapes stdout periodically, so **audit events between the last
collector scrape and the pod kill are lost** (pod stdout buffer is not persisted; VolSync
backs up `kanidm.db`, not logs). *Durability* holds (vlogs, different namespace, 14d,
survives pod destruction), but *completeness* has a small, indeterminate window. State this
explicitly in the Verification section so "forensic-grade" is not over-claimed. Likely
acceptable at homelab scale; revisit if the collector scrape interval is widened.

### R7 — L2 is forensic post-hoc; real-time brute-force detection already exists at the edge

An audit trail that nobody watches is a museum. The roadmap presents L2 as if `auth-failed`
were a detection surface — it is not (no kanidm Prometheus exporter exists; stdout → metrics
needs a log-to-metrics pipeline that is out of scope). Reframe L2 explicitly as **post-hoc
forensic**, and cross-reference the **already-deployed real-time controls** as the detection
layer:

- `rate-limit` BackendTrafficPolicy — **enabled** (Local, 600 req/min,
  `gateway-policies.yaml:186-200`; recent commit `1a7ac6cd5` "enable Local rate-limit").
  Note: the `iam` area-ref still describes rate-limiting as "commented out" — that area-ref
  is stale on this point and should be refreshed separately.
- Cloudflare WAF — external rate-limiting / brute-force at the edge.

A stdout → Alertmanager → Pushover alerting path for auth failures is a **known limitation**,
not a `just` recipe — state it honestly. The realistic real-time signal is the edge controls;
L2 is the after-the-fact "who/when/from-where" record.

### Updated sequencing (incorporating R1–R7)

- **Phase 0 (blocking)**: (a) Risk #1 empirical XFF verification — log in via Cloudflare and
  via LAN, observe `client_address` in raw `just kanidm logs`; (b) R2 — confirm vlogs ingests
  the security namespace; (c) R3 — confirm `kanidm person session status` prints
  `client_address`.
- **Phase 1**: L1B (CIDR per R1) → L2 (forensic recipes; `oauth2-tokens` without client_id per
  R4; durable-history gated on R2) → L3 (sessions; "from where" gated on R3).
- **Phase 2**: if Phase 0 showed Envoy does not append the real external IP, add the
  envoy-external `ClientTrafficPolicy`/`EnvoyPatchPolicy` to set upstream XFF from
  `CF-Connecting-IP` and strip client-supplied XFF, then apply L1B; re-verify + spoof test.
- **Phase 3 (optional, separate sub-item + security-review)**: L4 OTLP — with R5 CNP-comment
  rewrite + collector receiver hardening + kanidm→collector egress CNP, audited under AD-023.

### Sibling drift (not this roadmap, but surfaced during review)

The `iam` area-ref "Rate Limiting on External Gateway" block says `rate-limit-external` is
"commented out due to Envoy Gateway v1.8.0 CRD regression". The live
`gateway-policies.yaml` has `rate-limit` **enabled** (Local, 600/min; commit `1a7ac6cd5`).
Refresh the `iam` area-ref's rate-limiting block to match reality.


## Fact-based verification pass 2 — live cluster + v1.10.4 source (2026-07-20)

Method: read-only live cluster inspection (`kubectl logs/exec`, Envoy `config_dump` via
port-forward, VictoriaLogs LogsQL API) + a source-grounded pass over the kanidm **v1.10.4** git
tag. This pass RESOLVES the Phase 0 blockers that Pass 1 left empirical, and **corrects several
factual errors** in the sections above. Where this pass and an earlier section conflict, THIS
pass is authoritative.

### Corrections to the text above (verified wrong)

1. **Env-var name was wrong (L1A, Risks #2/#8).** The XFF-trust env var is
   **`KANIDM_TRUST_X_FORWARDED_FOR`** (with the "D"), a clap option `hide=true` (hence absent
   from `--help`), field `trust_all_x_forwarded_for` → `HttpAddressInfo::XForwardForAllSourcesTrusted`
   (`proto/src/cli.rs:93-99`, `server/core/src/config.rs:770-773`). The name used above
   (`KANIDM_TRUST_X_FORWARD_FOR`, no "D") **does not exist**. The no-"D" spelling
   `trust_x_forward_for` is a *legacy TOML key only* (file-only, `config.rs:299,853-854`) — the
   two were conflated. The env var and the CLI flag `--trust-all-x-forwarded-for` are the SAME
   clap field (identical effect).

2. **No env→TOML overlay exists (Risk #5 mechanism).** `kanidmd` does NOT overlay arbitrary
   `KANIDM_*` env vars onto `server.toml`; `ServerConfigUntagged::new()` reads the file only
   (`config.rs:322-367`). The existing `KANIDM_DOMAIN/ORIGIN/BINDADDRESS/DB_PATH/TLS_*` work
   because each is a clap `env=` option merged via `add_cli_config()`, NOT via file-env overlay.
   Consequence: a mounted `server.toml` (carrying only `[http_client_address_info]`) and the
   existing env config **coexist** — but the file MUST declare `version = "2"` to select the V2
   parser, and `[http_client_address_info]` is applied only from that file
   (`config.rs:395,937-938`). Validate with the built-in `kanidmd configtest` before rollout.

3. **Config-path is `KANIDM_CONFIG` (Risk #5, resolved live).** `kanidmd server -c/--config-path`,
   `[env: KANIDM_CONFIG=]` (confirmed from the live binary's `--help`; `server/daemon/src/opt.rs:117-118`).
   The **container image's default config path is `/data/server.toml`** — but `/data` is the
   kanidm PVC (non-declarative), so DO NOT use it. Mount a ConfigMap file (e.g. `/config/server.toml`,
   precedent: the `theme` ConfigMap) and point `KANIDM_CONFIG` at it.

4. **`Invalid identity: NotAuthenticated` is NOT an auth failure (L2/Risk #3, live).** It fires
   on every pre-login `GET /ui/oauth2` authorise (normal unauthenticated state; observed on real
   OIDC flows). Including it in `auth-failed` produces massive false positives — **remove it**.

5. **`auth-failed` grep strings were guessed wrong (L2/Risk #3, source).** There is no literal
   `"Auth result: Denied"`, `"Account is softlocked"`, or `"CredentialError"`. The correct anchor
   is **`Result::Denied`** — emitted via `security_error!` at **ERROR** level, so denials are
   visible at the current `info` config (no `debug` bump needed; Risk #3's debit-cost worry is
   moot). Canonical strings (`server/lib/src/idm/authsession/mod.rs`): `Handler::Password -> Result::Denied - incorrect password`,
   `Handler::Webauthn -> Result::Denied - webauthn error` (**the relevant one — this deployment is
   passkey/Webauthn-first**), `Handler::PasswordMfa -> Result::Denied - ...`. Account-state cases
   are lower severity: `account expired` (INFO) and `Account is temporarily locked` (softlock,
   INFO/TRACE — `idm/server.rs:1341-1347`). Robust filter = `Result::Denied` + `account expired` +
   `Account is temporarily locked`.

6. **`oauth2-tokens` client_id: recover from the AUTHORISE event, not token-exchange (L2/R4, live+source).**
   Confirmed each HTTP request gets its own `kopid` (`https/middleware/mod.rs:58-96`); authorise
   and token-exchange are separate handlers with separate kopids (`https/oauth2.rs:158-193` vs
   `:449-463`) → kopid does NOT bridge them. BUT the `GET /ui/oauth2?client_id=...` request line
   carries `client_id` in its URI, and the `handle_oauth2_authorise` span records
   `o2rs.name: "<client>"`. So `oauth2-tokens` should filter the **authorise** event for the RS
   name; `POST /oauth2/token` alone cannot name the RS. (This is an L2 deliverable after all — no
   L4 needed for it, contra R4's fallback framing.)

### Phase 0 blockers — resolution status

| Blocker | Status | Evidence |
|---|---|---|
| Risk #1 — client_address is the Envoy pod IP | **CONFIRMED (live)** | Every `client_address` = `::ffff:10.244.0.189` (=envoy-internal pod) or `::ffff:10.244.0.76` (=envoy-external pod); pod IPs verified via `get pods -o wide`. No real client IP ever appears (`http_client_address_info` unset). |
| Risk #1 — does Envoy put the real client IP into upstream XFF? | **PARTIALLY RESOLVED — one true empirical gate remains** | Envoy `config_dump` (both gateways): **`use_remote_address: false`**; external = `original_ip_detection custom_header CF-Connecting-IP`; internal = XFF numTrustedHops 0, `skip_xff_append: false`. `use_remote_address:false` means Envoy does NOT reliably append the *detected* IP to upstream XFF the way Pass 1 assumed. The exact XFF chain kanidm receives per path must be observed empirically (see the L1A probe below). |
| R2 — VictoriaLogs ingests security/kanidm | **RESOLVED — POSITIVE (strong)** | `kubernetes.pod_namespace:security` present; **8907 kanidm lines / 24h** in VictoriaLogs (14d retention). Durable filters proven: by `client_address`, by message (`"Initiating Authentication Session"` → real accounts over 7d). Stream selector: `{kubernetes.pod_namespace="security", kubernetes.pod_name="kanidm-0"}`, container `app`. |
| R3 — does `person session status` show client_address? | **RESOLVED — NO (source)** | `UatStatus` Display prints only `account_id, session_id, state, issued_at, purpose` (`proto/src/v1/mod.rs:78-98`). No source IP, no label. |

### Refined per-layer plan

**L1 — client-IP fidelity (decisive path).**
- The one remaining unknown is purely empirical and cheaply resolved. Phase-0 probe: add the
  single env line `KANIDM_TRUST_X_FORWARDED_FOR: "true"` (L1A, trust-all — trivially revertible),
  reconcile, then log in once via LAN and once via Cloudflare and read `client_address` in
  `just kanidm logs`. This reveals, per path, whether the real IP reaches kanidm via XFF at all
  and what the chain looks like.
- Then ship **L1B** (the spoof-resistant endpoint): mount `config/server.toml`
  (`version = "2"` + `[http_client_address_info] x-forward-for = ["10.244.0.0/16"]`) via a
  ConfigMap (precedent: `theme`), set `KANIDM_CONFIG=/config/server.toml`, validate with
  `kanidmd configtest`. L1B walks XFF from the right, trusting only the pod-CIDR proxy entries →
  client-injected left-side XFF is never reached. **Do NOT ship L1A as the endpoint** —
  `XForwardForAllSourcesTrusted` takes the leftmost (client-claimed) XFF entry → externally
  spoofable (the ingress CCNPs block only *pod* spoofing, not external clients).
- **If the LAN probe shows no real IP even with trust-all** (possible given `use_remote_address:false`),
  the fix is Envoy-side first: on `envoy-internal` ensure the real downstream is appended to
  upstream XFF; on `envoy-external` a `ClientTrafficPolicy`/`EnvoyPatchPolicy` to set upstream
  XFF from `CF-Connecting-IP` and strip client-supplied XFF — then L1B. This Envoy dependency is
  now more likely than Pass 1 implied (both gateways run `use_remote_address:false`).

**L2 — stdout auth-event mining + durable history (forensic, post-hoc).**
- `auth-tail` / `auth-recent <N>` filter pattern (corrected):
  `Initiating Authentication Session|Auth result|Result::Denied|Issuing.*session|Persisting auth session|account expired|Account is temporarily locked`.
- `auth-failed`: anchor on `Result::Denied` (+ `account expired`, `Account is temporarily locked`).
  Drop `Invalid identity: NotAuthenticated`.
- `oauth2-tokens`: filter `handle_oauth2_authorise` / `uri: /ui/oauth2?...client_id=` for the RS name.
- **`vlogs-query` is now a first-class deliverable** (R2 positive). Query VictoriaLogs via
  `kubectl exec`/port-forward to the vlogs Service (`:9428`, LogsQL `/select/logsql/query`) — NOT
  the un-authed `logs.${PUBLIC_DOMAIN}` HTTPRoute → sidesteps Risk #6 entirely. This is the
  14d durable path that survives pod restarts, largely closing the R6 completeness gap (vlogs
  persists independently of the kanidm pod's stdout buffer).

**L3 — live sessions (`who / when / purpose`, NOT `from where`).**
- `session-status <user>` → `person session status`: shows session_id, state/expiry, issued_at,
  purpose. Reframe the headline benefit: "from where" for a LIVE session is answerable ONLY by
  correlating its `session_id` back to an L2 authorise/auth audit line — not from L3 itself.
- `session-destroy <user> <uuid>` → `person session destroy`, `gum confirm`-gated.

**L4 — OTLP (unchanged direction; hardening confirmed necessary).**
- `KANIDM_OTEL_GRPC_URL` (gRPC/tonic, URL-supplied port, std 4317), honors `OTEL_SERVICE_NAME`
  (default `kanidmd`) and the `authorization` header from `OTEL_EXPORTER_OTLP_HEADERS`
  (`libs/sketching/src/pipeline.rs:72-134`). Sampler is **`AlwaysOn`** → exports the full
  per-request spans incl. `client_address`, `uri`, and `security_*` auth events (user
  identities). This confirms R5: OTLP is a full-fidelity auth-data channel — collector-side
  auth (mTLS/header) + a tight kanidm→collector egress CCNP are mandatory, and the kanidm CNP's
  "no legitimate outbound / no telemetry" comment must be rewritten in lockstep. Keep L4 a
  separate sub-item with its own security-review.

### Updated sequencing (supersedes both prior sequencing blocks)

- **Phase 0 (blocking, mostly DONE here)**: R2 ✅ positive; R3 ✅ (no client_address); Risk #1 IP
  ✅ confirmed. Remaining: the L1A trust-all **XFF probe login** (LAN + Cloudflare) to read the
  actual per-path client_address — the sole empirical gate for L1.
- **Phase 1**: L1B (server.toml + `KANIDM_CONFIG`, `configtest`-validated) → L2 (corrected
  filters + `vlogs-query` via kubectl) → L3 (sessions; "from where" documented as L2-correlation).
- **Phase 2 (only if the probe shows the real IP does not reach kanidm)**: Envoy-side XFF fix
  (internal append / external CF-Connecting-IP → upstream XFF + strip), then re-verify L1B + spoof test.
- **Phase 3 (optional, separate + security-review)**: L4 OTLP with collector hardening + egress CNP + CNP-comment rewrite, audited under AD-023.

### Remaining true unknowns (honest)

- The exact upstream XFF chain kanidm receives per path (the L1A probe resolves it in minutes).
- Exact live denial strings on THIS passkey deployment (source gives `Handler::Webauthn ->
  Result::Denied - webauthn error`; confirm by triggering one failed passkey attempt when
  finalizing the `auth-failed` filter).
- Whether a V2 `server.toml` carrying ONLY `[http_client_address_info]` cleanly composes with the
  clap/env config in practice — gate on `kanidmd configtest` at implementation.

## Pass 3 — XFF spoof-resistance empirical test (2026-07-21)

Method: live cluster read-only inspection — sent a spoofed-XFF request through the
external gateway and read the Envoy access log plus the live kanidm `server.toml`
ConfigMap. This pass RESOLVES Risk #1 for the external path, confirms L1B is already
live (so the roadmap's `status: proposed` / "Phase 0 L1A probe pending" framing is
stale), and leaves exactly one small empirical gap.

### Test

    curl -H "X-Forwarded-For: 9.9.9.9" https://idm.horvathzoltan.me

Sent twice (IPv4 and IPv6) from a host OFF the LAN, so the request traversed Cloudflare
Tunnel → envoy-external → kanidm (NOT envoy-internal; the internal path was not tested
this round — see Open).

### Findings

1. **Envoy forwards the spoof plus the real client to kanidm.** The `envoy-external`
   access log (`kubectl -n networking logs envoy-external-... -c envoy`) shows:

       "downstream_remote_address":"178.164.250.100:0",
       "x_forwarded_for":"9.9.9.9,178.164.250.100"

   (IPv6 variant: `x_forwarded_for":"9.9.9.9,2a00:1110:21d:4387:dde7:8419:48b2:6537"`.)
   The client-supplied `9.9.9.9` is preserved on the LEFT; Envoy appends the real client
   IP as the RIGHTMOST entry. `downstream_remote_address` = the real client public IP
   (178.164.250.100), i.e. cloudflared conveys the original client to Envoy (PROXY
   protocol, or the `CF-Connecting-IP` custom-header effective downstream remote).

2. **Risk #1 RESOLVED for the external path — and it corrects R1 / Pass 2.** R1 and
   Pass 2 assumed envoy-external appends the *cloudflared pod IP* to upstream XFF and
   would need an Envoy-side `ClientTrafficPolicy`/`EnvoyPatchPolicy` to set XFF from
   `CF-Connecting-IP`. Empirically Envoy ALREADY appends the real client IP as the
   rightmost XFF entry → **no Envoy-side fix is needed for the external path.** Phase 2
   (Envoy XFF rewrite for external) is not required; revisit only if the live-auth-event
   check below fails.

3. **L1B is ALREADY shipped — roadmap status is stale.** The live kanidm ConfigMap
   `kanidm-config` (`server.toml`) contains:

       [http_client_address_info]
       x-forward-for = ["10.244.0.0/16"]

   i.e. the L1B endpoint (mounted `server.toml` + pod-CIDR trust) is deployed. The
   roadmap's `status: proposed`, the "Phase 0 L1A trust-all probe" framed as the sole
   remaining gate, and the treatment of L1B as a future deliverable are all STALE —
   L1B is live. Refresh the roadmap status: L1 = effectively done, pending only the
   live-auth-event confirmation below (and the IPv6-dual-stack decision).

4. **Spoof-resistance confirmed by config + algorithm analysis.** Kanidm
   `XForwardFor([10.244.0.0/16])` walks XFF right→left, skips entries in the trusted
   CIDR, and takes the first non-trusted entry as `client_address` (the MDN "trusted
   proxy list" method; kanidm issue #3837 + server_configuration docs). For the observed
   chain `9.9.9.9,178.164.250.100`: rightmost = 178.164.250.100, not in 10.244.0.0/16
   → taken as the client. The spoofed 9.9.9.9 sits on the left and is never reached.
   Because Envoy always appends the real downstream as the rightmost entry and an
   external client cannot place a trusted (pod-CIDR) entry to its right, the spoof is
   structurally ignored. → `client_address` will be the real client IP, not 9.9.9.9 and
   not the Envoy pod IP. **L1B is spoof-resistant by design; this test passed.**

### NOT yet confirmed (the one remaining empirical gap)

The curls were unauthenticated `GET /` → kanidm returned 303 (redirect to login) and
emitted NO auth-audit event, so the actual `client_address` value in a kanidm auth log
line was NOT observed this round. The spoof-resistance above is established from config
+ algorithm + the Envoy XFF chain, not from a live auth-event line. Close this with one
real (failed) login through the external gateway and read `client_address` in
`just kanidm logs` / vlogs — expect the real public IP, not 9.9.9.9 and not 10.244.x.x.

### Residual risk — IPv4-mapped IPv6 (kanidm issue #3837)

The trusted CIDR `10.244.0.0/16` is IPv4. If an Envoy→kanidm connection ever goes IPv6,
the peer appears as `::ffff:10.244.0.x` and the IPv4 CIDR does NOT match (a `rust-cidr`
limitation) → kanidm stops trusting XFF and falls back to the TCP peer (the Envoy pod
IP) → the real client is lost again, silently. The current path is IPv4
(10.244.0.229 → 10.244.0.211:8443), so it works today. Mitigation when needed: add
`::ffff:10.244.0.0/112` to the `x-forward-for` list (note the `/112` prefix for a `/16`
range — see issue #3837), or constrain Envoy→kanidm to IPv4. Add as a Risk and a gated
follow-up; it is the most likely way this setup silently regresses.

### Open / next

- Internal-gateway spoof test not run this round (the host was off-LAN). The logic is
  symmetric (`numTrustedHops: 0`, Envoy appends the real LAN client as the rightmost XFF
  entry); re-test from the LAN when convenient to close the internal half.
- One live (failed) login through envoy-external to read `client_address` and confirm
  it is the real IP (closes the last L1 empirical gap).
- Decide on the IPv4-mapped-IPv6 mitigation above (proactive, before any IPv6 path
  appears).
- Other backends: the same spoofed XFF reaches every backend. Kanidm is safe; any
  backend that parses XFF leftmost (or trusts without the rightmost-trusted walk) is
  still spoofable. A gateway-side `earlyRequestHeaders.remove: [X-Forwarded-For]`
  (defense-in-depth for the whole backend population) remains a separate, justified
  task — not for kanidm, but for the other apps.

### Pass 3 update — live auth-event confirmation (2026-07-21)

A real kanidm login flow through BOTH gateways was captured in
`kubectl -n security logs kanidm-0`. This closes the "NOT yet confirmed" gap from
Pass 3 and resolves more of the Open/next list than expected — including the internal
half and the IPv4-mapped-IPv6 residual risk.

Decisive evidence — `client_address` is now the REAL client IP on both gateways:

- External (envoy-external pod, `connection_address: [::ffff:10.244.0.229]:43312`):
  `client_address: "178.164.250.100"` (the real public IP). Before L1B this was the Envoy
  pod IP; now it is the real client.
- Internal (envoy-internal pod, `connection_address: [::ffff:10.244.0.206]:...`):
  `client_address: "192.168.1.100"` (the real LAN client IP). The internal half is now
  empirically confirmed too — not just by symmetric-logic argument.

The auth-audit events nest under the carrying `request` line (linked by `kopid`):
`Initiating Authentication Session | username: aliz@idm.horvathzoltan.me`,
`Auth result: Choose(passkey)`, `Continue (Passkey)`, `Success(Cookie)`. The parent
request line carries the real `client_address`, so "who / when / from-where" is now
answerable by kopid correlation — the L1 goal is fully, empirically met on both paths.

IPv4-mapped-IPv6 residual risk — EMPIRICALLY NOT MANIFESTING (softens Pass 3 risk):
`connection_address` is `[::ffff:10.244.0.229]` / `[::ffff:10.244.0.206]` — the
IPv4-mapped IPv6 form is PRESENT on both Envoy→kanidm paths (kanidm binds `[::]:8443`
dual-stack). Yet the trust gate passes and `client_address` is the real IP, not the
Envoy pod IP. So this kanidm build matches the IPv4 CIDR `10.244.0.0/16` against the
`::ffff:10.244.0.x` mapped form — the kanidm issue #3837 IPv4-mapped-IPv4 case is NOT a
problem here. Narrow the residual risk to a PURE-IPv6 Envoy→kanidm path (a real IPv6
peer, not IPv4-mapped), which is not the current setup. Drop the proactive
`::ffff:10.244.0.0/112` mitigation from "required"; keep it only as a note if a
pure-IPv6 upstream path is ever introduced.

Caveats (honest):
- The captured flow ended in `Auth result: Success(Cookie)` for `aliz` — a SUCCESS, not
  a `Result::Denied`. No `Result::Denied` / softlock / `account expired` line appeared
  in this window, so the exact `auth-failed` grep strings for L2 (Risk #3) are STILL
  unconfirmed. That is an L2 task, not an L1 gap.
- This login flow did not carry a client-injected `X-Forwarded-For: 9.9.9.9` (it was a
  normal browser login), so this confirms real-IP FIDELITY, not spoof-RESISTANCE on an
  auth event. Spoof-resistance remains established by the Pass 3 Envoy XFF chain +
  kanidm rightmost-trusted algorithm analysis. A spoofed-header login would close that
  last nuance if desired, but is not required given the structural argument.

Net: L1 is DONE and empirically verified on both gateways. Remaining L1-adjacent items
are the (optional) spoofed-header auth-event nuance and the (narrowed) pure-IPv6
theoretical case; the `auth-failed` strings are an L2 task.

### Pass 3 IPv6 precision (2026-07-21, follow-up)

Clarifying what `connection_address: [::ffff:10.244.0.206]` does and does not test,
since the `::ffff:` notation reads as IPv6:

- `::ffff:10.244.0.206` is an IPv4-MAPPED IPv6 address: it is the IPv4 address
  10.244.0.206 (the envoy-internal pod) represented in IPv6 notation, because kanidm
  binds `[::]:8443` dual-stack and accepts the IPv4 upstream connection in mapped
  form. This IS the kanidm issue #3837 scenario (IPv4 CIDR vs IPv4-mapped-IPv6 peer),
  and it is TESTED above — trust passes, `client_address` is the real client IP. So
  #3837 is tested-and-dismissed, not merely "narrowed".
- A PURE-IPv6 Envoy→kanidm upstream path does NOT EXIST in this cluster: the pod CIDR
  is IPv4-only (10.244.0.0/16) and observed pod IPs are IPv4; the mapped form on
  kanidm socket confirms upstream arrives as IPv4. There is no pure-IPv6 peer case
  to test — it is moot, not an open risk. This replaces the softer "narrow to
  pure-IPv6 / not the current setup" wording in the block above.
- One sub-case genuinely NOT yet observed in the kanidm pod buffer: kanidm recording a
  real IPv6 CLIENT IP (e.g. the MBP public IPv6 2a00:1110:...) parsed from the XFF
  rightmost entry. Envoy forwards it (the 19:26 IPv6 spoof curl showed
  `x_forwarded_for: "9.9.9.9,2a00:1110:..."`), and kanidm parses XFF entries as
  strings regardless of family, so it should record the IPv6 — but the kanidm pod
  buffer has 0 `2a00` entries in 90m (the 19:26 line rotated out / was not captured).
  One fresh IPv6 request (curl over IPv6, or a login over IPv6) and a grep for the IPv6
  client_address would close this last sub-case. Mechanism is clear; this is
  confirmation, not risk.
## Pass 4 — L2 shipped: vlogs-backed audit recipes (2026-07-22)

Method: implemented the `audit` recipe group in `kubernetes/apps/security/kanidm/mod.just`
(commit `7c26c1f37`), then smoke-tested every recipe against the live cluster + 14d
VictoriaLogs history. This pass RESOLVES Risk #3 (empirical denial catalog), closes the
R6 completeness gap by design (vlogs-first), and closes the last Pass 3 sub-case (real
IPv6 client IP). L2 is DONE.

### What shipped — 6 recipes, two helpers

Two private helpers back the group:

- `_vlogs <query> [limit]` — port-forward to `svc/victoria-logs-server:9428` + local
  `curl` to `/select/logsql/query` (LogsQL). Reached via port-forward, NOT the un-authed
  `logs.${PUBLIC_DOMAIN}` HTTPRoute → sidesteps Risk #6 entirely (the same call Pass 2
  made, now the backbone of every history recipe). Returns raw JSONL; callers do their
  own jq/awk so the kopid recipes can two-pass the same stream.
- `_vlogs_kopid <query> <correlate>` — pulls a window from vlogs, then awk two-pass:
  mark every line whose `_msg` matches the correlate regex, keep every line sharing a
  marked kopid. This joins a parent `request` line (which carries `client_address`) to
  its auth-event child spans (`Auth result`, `Issuing Cookie session`), which do NOT
  carry `client_address`. LogsQL is snapshot-only with no group-by-kopid, so the
  correlation is local awk (the kopid UUID prefixes every `_msg`, so it is awk `$2`
  of the `_time  <kopid> INFO ...` line).

The 6 recipes:

| Recipe | Source | What it shows |
|---|---|---|
| `auth-tail` | live pod buffer (`kubectl logs -f --tail=1000`) | all auth events streamed forward — start it, then trigger the login |
| `auth-success` | vlogs 14d (kopid-correlated) | per login: `client_address` + user + `Success(Cookie)` |
| `auth-failed` | vlogs 14d | auth denials, chronologically sorted |
| `authz-denied` | vlogs 14d | scope-limit denials (authenticated user hit a scope limit — not a failed login) |
| `auth-user <u>` | vlogs 14d (kopid-correlated) | full auth flow for one user |
| `vlogs-query [q]` | vlogs 14d | arbitrary LogsQL query (empty = default auth-event view) |

### vlogs-first redesign (R6 closed by design)

The original L2 plan read the pod stdout buffer (`kubectl logs`) for every recipe. R6
flagged that the kanidm pod carries `reloader.stakater.com/auto: "true"` → every secret
rotation recreates the pod and the stdout buffer is lost. Redesign: **every history
recipe reads VictoriaLogs** (14d durable, persists independently of the kanidm pod).
`auth-tail` is the ONLY pod-buffer recipe, and it is forward-follow (`-f`) — its
purpose is "start it, then trigger the login", not backlog mining, so pod-restart
fragility does not apply to it. This nearly fully closes R6: the only residual window
is vlogs ingestion latency (seconds), not pod-buffer loss.

### Empirical denial catalog — Risk #3 CLOSED

Risk #3 / Pass 2 correction #5 guessed the passkey-denial string from source as
`Handler::Webauthn -> Result::Denied - webauthn error`. The 14d vlogs history shows
the REAL denial strings on this build (UI passkey cancellation does NOT trigger a
`Result::Denied` — the WebAuthn API refuses a fake passkey client-side, so no
server-side denial fires; the denials below come from password attempts and credential-
state failures):

- `Auth result: Denied: invalid credential state` — the passkey/credential-state failure path
- `Handler::Password -> Result::Denied - incorrect password`
- `Credentials denied | reason: incorrect password`
- `Auth result: Denied: incorrect password`

The shipped `auth_failed_re` filter is `Result::Denied|Auth result: Denied|Credentials denied`
— empirically complete for this build. `Invalid identity: NotAuthenticated` is correctly
excluded (Pass 2 correction #4: it fires on every pre-login authorise, normal state).
`account expired` / `Account is temporarily locked` were not observed in 14d (no such
event occurred) — the filter stays source-informed for those, empirically informed for
the rest.

`authz-denied` is split out as a SEPARATE recipe because `denied ❌ - identity access
scope is not permitted to modify/delete` is an AUTHORIZATION denial (an authenticated
user hit a scope limit), not an AUTHENTICATION failure — mixing them into `auth-failed`
would conflate two different trust-boundary events.

### auth-success rename + oauth2-tokens dropped (scope decisions)

- `auth-recent <N>` (pod-buffer snapshot, original L2 plan) → renamed to **`auth-success`**
  and moved to vlogs. It is now kopid-correlated so each login block shows the
  `client_address` from the parent request line plus the `Issuing Cookie session ...
  for <user>@` + `Auth result: Success(Cookie)` lines — the L1 client-IP payoff lands
  directly in the success view.
- **`oauth2-tokens` dropped** (per scope decision). Pass 2 correction #6 showed the RS
  name is recoverable from the `handle_oauth2_authorise` event (`o2rs.name` /
  `uri: /ui/oauth2?client_id=`), not the token-exchange line. That remains true, but the
  token-issuance surface is not part of the delivered audit trail — it can be added later
  as its own recipe if token-issuance auditing becomes a need. `vlogs-query` covers
  ad-hoc exploration in the meantime.

### IPv6 client-IP sub-case — CLOSED (Pass 3 last open item)

Pass 3 IPv6 precision left one sub-case unobserved: kanidm recording a real IPv6 CLIENT
IP (not IPv4-mapped) parsed from the XFF rightmost entry. `auth-success` smoke-test
surfaced it empirically — a login over IPv6 produced:

- `client_address: "2a00:1110:201:a1e8:2c90:4237:89da:fa58"` (real public IPv6)

alongside the already-known `192.168.1.100` (LAN) and `::ffff:10.244.0.206`
(cluster-internal login). Kanidm parses XFF entries as strings regardless of family, so
the IPv6 client IP is recorded correctly. **This closes the last Pass 3 sub-case**: L1
client-IP fidelity is empirically verified for IPv4 LAN, IPv4 public, AND IPv6 public,
on both gateways, spoof-resistant by the rightmost-trusted algorithm.

### Smoke-test results (all 6 verified)

- `auth-tail` — 13 auth events from the backlog stream immediately (needed
  `--line-buffered` on the grep so output flushes in the pipe, and `--tail=1000`
  because the unfiltered 100-line buffer was often 0 auth events given the tombstone-purge
  noise ratio — ~14 auth events vs ~488 tombstone-purge lines per 2000).
- `auth-success` — per-login blocks with `client_address` (LAN / IPv6 / cluster-internal).
- `auth-failed` — real denial strings, chronologically sorted.
- `authz-denied` — scope-limit denials.
- `auth-user aliz` — kopid-grouped full flow: Initiating → Choose(passkey) → Continue
  (Passkey) → Issuing → Success.
- `vlogs-query` — default view + custom queries.

### Status

- **L1 — DONE** (Pass 3, both gateways, IPv4+IPv6, spoof-resistant).
- **L2 — DONE** (this pass; commit `7c26c1f37`). Forensic post-hoc audit trail is
  operational: `just kanidm auth-tail|auth-success|auth-failed|authz-denied|auth-user|vlogs-query`.
- **L3 — pending** (live sessions: `session-status` / `session-destroy`; "from where"
  for a live session is L2-correlation only, per R3).
- **L4 — optional, separate sub-item + security-review** (OTLP; R5 CNP-comment rewrite +
  collector hardening + egress CNP, audited under AD-023).
- Real-time brute-force detection remains the edge controls' job (R7: rate-limit
  BackendTrafficPolicy + Cloudflare WAF); L2 is the after-the-fact record, not a
  detection surface.

### Remaining true unknowns

- L3 `person session status` live output shape (R3 confirmed no `client_address` from
  source; the recipe wiring + smoke-test is the L3 task).
- L4 backend choice (Tempo vs VictoriaTraces) + collector hardening details — gated on a
  separate decision.
