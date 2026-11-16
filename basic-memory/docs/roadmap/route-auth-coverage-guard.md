---
title: route-auth-coverage-guard
type: roadmap
permalink: home-ops/docs/roadmap/route-auth-coverage-guard
topic: Route auth coverage guard — every published hostname must have a declared Pocket
  ID gate or a justified exemption
status: proposed
priority: high
scope: 'A two-layer, fail-closed check that every HTTPRoute hostname in the repo is
  owned by a Pocket ID client (gate envoy or native) or by an explicit, justified
  exemption in provision/pocket-id/clients.yaml. Layer 1: offline static scan (pre-commit,
  just, CI). Layer 2: rendered-manifest check in CI that proves each gate-envoy route
  really carries a matching OIDC SecurityPolicy. Out of scope: fixing the currently
  unprotected apps (separate remediation work), runtime probing, Cloudflare Access
  cross-checks.'
rationale: 'The 2026-11-15 coverage audit found home-gallery (photos/fenykepek) on
  envoy-external with no Pocket ID gate and fully open from the LAN, plus crosswatch,
  jellyfin and llm on envoy-internal without Pocket ID. Nothing in the repo stops
  this: provision/pocket-id/lint.sh only cross-checks apps that already use gateway-oidc
  and runs only before pocket-id plan/apply; the admission policy checks hostnames
  and gateways, not auth. The security guide''s rule "Every app must be protected"
  is therefore convention only.'
options:
- Static registry check (L1) + rendered-manifest check (L2) — RECOMMENDED
- Admission-time annotation (VAP requiring auth.home.arpa/gate) — rejected as primary
  (self-declared, CEL cannot look up SecurityPolicies)
- Gateway-level default-deny with route opt-in — rejected (route authorization replaces
  parent rules; conflicts with the geo/RFC1918/CrowdSec gates)
- Runtime blackbox probing of every host — deferred to a follow-up (second line, high
  maintenance for native apps)
related_areas:
- iam
- networking
- flux-gitops
---

# Route auth coverage guard

## Metadata (observation-form, schema validation)

- [topic] Route auth coverage guard — every published hostname has a declared Pocket ID gate or a justified exemption
- [status] proposed
- [priority] high
- [researched_at] 2026-11-15
- [effort] M

## What we gain

- An unprotected route can no longer appear silently: a hostname nobody has claimed fails the commit (pre-commit) and the PR / push check (CI).
- Every exception is explicit, has a written reason and a compensating control, and is scoped to the gateways it may use.
- The one thing the 2026-11-15 audit could not verify offline — that each gate-envoy route really carries an OIDC SecurityPolicy with the right target name (HTTPROUTE_NAME), mergeType and redirect host — becomes a CI assertion.
- Renovate chart bumps that change generated routes are caught on the PR, before Flux applies them.

## What we accept

- `main` has no required status checks and maintainer commits go straight to `main` (see [[main-branch-protection-and-commit-signing]]): CI is a post-hoc signal for direct pushes. Pre-commit is the primary gate and can be skipped with `--no-verify`.
- The guard proves that a gate is *declared and wired*, not that the app enforces it: a native-OIDC app with a local password fallback (calibre OPDS, paperless API basic auth) still passes. That needs live verification and is a separate follow-up.
- Layer 2 needs network access to chart registries; it runs in CI only, not in pre-commit.

## Research findings (2026-11-15)

### Current enforcement gaps
- [evidence] `provision/pocket-id/lint.sh` only collects `gate: envoy` clients and ks.yaml files that include `gateway-oidc`; a route with neither is invisible to it.
- [evidence] The lint runs only as a dependency of `just pocket-id plan|apply` (`provision/pocket-id/mod.just:25-35`); it is not in `.pre-commit-config.yaml` or any GitHub workflow.
- [evidence] `ValidatingAdmissionPolicy httproute-reserved-hostnames` (`kubernetes/apps/networking/envoy-gateway/config/validatingadmissionpolicy.yaml:36-49`) checks the reserved idm host, wildcard placement (http listener only) and known gateways. It does not check auth, and CEL cannot look up whether a SecurityPolicy targets the route.
- [evidence] `kubernetes/apps/security/CLAUDE.md:24` states "Every app must be protected …" with no enforcing mechanism.
- [evidence] `.github/workflows/flux-local.yaml` triggers on `pull_request` with paths `kubernetes/**` only.

### Audit result the guard must reflect (repo state 2026-11-15)
- [fact] 33 route definitions; static scan output reproduced below under *Layer 1 prototype*.
- [fact] Not owned by any Pocket ID client: `photos`, `fenykepek` (home-gallery, envoy-external + envoy-internal), `crosswatch`, `jellyfin`, `llm` (all envoy-internal).
- [fact] Legitimately non-OIDC: `idm` (the IdP itself), `flux-webhook` (GitHub hooks CIDR + Flux Receiver HMAC), `*` (`networking/https-redirect`, http listener, redirect only, no backend).
- [fact] The live cluster was unreachable during the audit; SecurityPolicy `Accepted` / `Overridden` status was not verified.

### Layer 1 prototype — schema-agnostic static scan
- [verified] A recursive yq walk (`.. | select(tag == "!!map" and has("hostnames"))`) over every YAML document under `kubernetes/` found all 33 route definitions. That includes the victoria-logs (`server.route`) and open-webui (flat `route:`) chart schemas, which a chart-specific `.spec.values.route` query had missed. Conclusion: the scan must key on the `hostnames` field anywhere in a document, never on a chart-specific path.
- [fact] No HelmRelease uses `valuesFrom` today, so no route definition hides in a ConfigMap string. A future `valuesFrom` would be an L1 blind spot; L2 covers it.

### Layer 2 spike — rendered manifests
- [verified] `flux-local build all --enable-helm --skip-secrets kubernetes/flux/cluster` returned **exit 0 with empty output** when a chart fetch failed (ghcr.io unreachable). A rendered check must never trust the renderer's exit code alone.
- [fact] flux-local 8.4.0 (pinned in `.mise.toml`, used by `flux-local.yaml`) prints "flux-local is deprecated and has been sunsetted. Please migrate to flate … and konflate".
- [fact] flate (home-operations/flate README, read 2026-11-15): Go successor to flux-local, single binary. Renders Kustomizations with postBuild substitution, HelmReleases incl. OCI charts, and source objects. `flate test` exits 1 on failure; `--strict-substitutions` fails on unresolved `${VAR}` (default: substituted as empty). GitHub Action `home-operations/flate/action`, image `ghcr.io/home-operations/flate`. Not documented: the `build` output format/destination, and the exit code on a chart-fetch failure. Both must be tested in Phase 0.
- [blocked] A full local render could not complete during research (ghcr.io refused connections from the current network). Phase 0 runs it in CI.

## Design

### Registry: `provision/pocket-id/clients.yaml` stays the single source of truth
Add one top-level map, `exempt`, beside `groups` and `clients`. The key is the subdomain (`*` for the redirect wildcard).

```yaml
exempt:
  idm:
    reason: The identity provider itself.
    control: Admin API, setup and signup paths 403 on the public route; passkey-only.
    gateways: [envoy-external, envoy-internal]
  flux-webhook:
    reason: GitHub webhook receiver, machine caller.
    control: Cloudflare Access GitHub-hooks CIDR bypass, route SecurityPolicy GitHub CIDR authorization, Flux Receiver HMAC token.
    gateways: [envoy-external]
  "*":
    reason: Plain-HTTP to HTTPS redirect, no backend.
    control: RequestRedirect only; http listener only (admission policy).
    gateways: [envoy-external, envoy-internal]
    redirect_only: true
```

- `reason`, `control` and `gateways` are mandatory and non-empty.
- `temporary: true` + `tracking: <BM permalink>` marks a known gap accepted until remediation (see D1). The lint prints every temporary exemption as a warning on each run, so the debt stays visible while the check is green.
- A subdomain may appear in `clients` or `exempt`, never both.

### Layer 1 — static, offline (pre-commit + just + CI)
Extends `provision/pocket-id/lint.sh` and keeps all existing checks. Inputs: every YAML document under `kubernetes/`, every ks.yaml (for `postBuild.substitute` and components), and `clients.yaml`.

1. **Discover** every map that has a `hostnames` key, in any document kind (HTTPRoute, HelmRelease values, anything else). Record the file, the hostnames, the parentRefs (name + sectionName) and whether rules carry backendRefs.
2. **Resolve the owner Kustomization**: the ks.yaml Kustomization whose `spec.path` is the longest prefix of the file's directory. Substitute `${APP}`, `${APP_SUBDOMAIN}` (default `${APP}`) and other `postBuild.substitute` values from it.
3. **R1 — host form**: after substitution each hostname must be `<sub>.${PUBLIC_DOMAIN}` or `*.${PUBLIC_DOMAIN}`. Anything else (an unresolved variable, another domain, a bare host) fails. Fail-closed on anything the parser does not understand.
4. **R2 — ownership**: `<sub>` must be a key in `clients` or `exempt`.
5. **R3 — gate envoy wiring**: the owner ks includes `components/gateway-oidc`, its `APP` is the client key and its `APP_SUBDOMAIN` (or `APP`) equals the client's subdomain. The route carries **exactly one hostname**, because the gateway-oidc `redirectURL` is single-host (`kubernetes/components/gateway-oidc/securitypolicy.yaml:30`). A second hostname would loop the login. This matters for the home-gallery remediation: photos + fenykepek cannot share one gate.
6. **R4 — gate native**: the owner ks must not include `gateway-oidc` (no double gate; matches the crowdsec-web-ui intent).
7. **R5 — exemption scope**: every parentRef gateway of the route is in `exempt.<sub>.gateways`. `redirect_only` entries must have no backendRefs and only `sectionName: http` parents. `temporary` entries must carry `tracking`.
8. **R6 — no stale entries**: every `clients` and `exempt` subdomain is claimed by at least one route. This extends today's envoy-only reverse check to native and exempt.
9. **R7 — catch-all**: a route map with no `hostnames` must attach only to `sectionName: http`, mirroring the admission policy.
10. Output: one line per violation (file, host, rule, fix hint) and a summary of temporary exemptions. Exit 1 on any violation.

### Layer 2 — rendered (CI only)
A separate entry point (`provision/pocket-id/lint-rendered.sh <rendered.yaml>`) reads the fully rendered stream (HelmReleases templated, postBuild substituted):

1. **Fail-closed sanity**: the stream contains at least one HTTPRoute and one SecurityPolicy, and no hostname still contains `${`. Run the renderer with strict substitutions where supported.
2. **Parity with L1**: the set of rendered HTTPRoute hostnames equals the L1 set. A host only L2 sees comes from a chart default or `valuesFrom` and fails until claimed. A host only L1 sees means the render dropped something, which fails too. This makes an empty or partial render impossible to pass.
3. **Gate envoy proof**: for every host owned by a `gate: envoy` client there is, in the route's namespace, a SecurityPolicy with `spec.oidc` whose `targetRefs` names that exact HTTPRoute (kind HTTPRoute), with `mergeType: StrategicMerge` and `redirectURL` host equal to the client host. This catches a wrong `HTTPROUTE_NAME`, which today would leave the policy targeting nothing.
4. **Gate native proof**: a gate-native host has no oidc SecurityPolicy targeting its route.

### Enforcement surfaces
- **pre-commit**: a local hook `pocket-id-route-guard`, entry `provision/pocket-id/lint.sh`, `pass_filenames: false`, `files: '^(kubernetes/.*\\.ya?ml|provision/pocket-id/(clients\\.yaml|lint\\.sh))$'`.
- **just**: `just pocket-id lint` keeps running L1 (still the first dependency of plan/apply).
- **CI**: a new workflow `route-auth-guard.yaml`, triggered on `pull_request` and `push` to `main`, paths `kubernetes/**` and `provision/pocket-id/**`. Job `static` runs L1. Job `rendered` renders with the Phase 0 engine and runs L2. Rules: `permissions: contents: read`, SHA-pinned actions, `persist-credentials: false`, yq/jq versions identical to `.mise.toml`. Must pass actionlint and zizmor.
- **Language and tooling**: bash + yq + jq, the tools the existing lint already uses and `.mise.toml` already pins. No new dependency.

## Plan

### Phase 0 — Render-engine spike (CI, no repo behavior change)
- Run flate and flux-local over `kubernetes/flux/cluster` in a throwaway workflow run. Record wall time, the output format, whether HTTPRoutes and SecurityPolicies from charts and components appear with substituted names, and the exit code with one chart reference deliberately broken.
- Decide the engine (D2). Abort criterion: if neither engine fails loudly on a fetch error, L2 relies solely on the parity check (L2.2) for fail-closed behavior. Record that explicitly.

### Phase 1 — Test harness first (TDD)
- `REPO_ROOT` and `REGISTRY` env overrides in `lint.sh`. Fixture trees under `provision/pocket-id/tests/fixtures/<case>/` (a minimal `kubernetes/` + `clients.yaml`) and a plain bash runner `provision/pocket-id/tests/run.sh` that asserts the exit code and the violation text per case.
- Cases, all written red first: unclaimed host; host claimed twice (clients + exempt); unresolved `${VAR}`; foreign domain; gate envoy without gateway-oidc; gate envoy subdomain mismatch; gate envoy route with two hostnames; gate native with gateway-oidc; exempt on a non-listed gateway; exempt without reason or control; temporary without tracking; redirect_only with a backendRef; stale clients / exempt entry; catch-all route on https; a route nested in a non-standard values path (the open-webui / victoria-logs shape). Plus a clean fixture that must pass.
- L2 fixtures: a rendered stream with a matching policy (pass), wrong targetRef name, missing mergeType, wrong redirect host, empty stream, and a host present in L2 but absent from L1.

### Phase 2 — Layer 1 + registry
- Implement R1–R7 until the fixtures pass. Add `exempt` to `clients.yaml` with idm, flux-webhook and `*`.
- Run against the real repo. Expected violations: photos, fenykepek, crosswatch, jellyfin, llm. Handle them per D1.
- Add a test-runner hook so the tests run whenever `lint.sh`, `lint-rendered.sh` or the fixtures change.

### Phase 3 — Wire pre-commit + CI static job
- Add the pre-commit hook and the workflow's `static` job. Verify: a commit adding an unclaimed hostname is rejected locally, and the same change on a PR turns the check red.

### Phase 4 — Layer 2 + CI rendered job
- Implement `lint-rendered.sh` against the L2 fixtures, then wire the `rendered` job with the Phase 0 engine.
- Verify on a PR: renaming a gated route without updating `HTTPROUTE_NAME` turns the job red. A broken chart reference turns it red (via the exit code or the parity check).

### Phase 5 — Documentation
- `kubernetes/apps/security/CLAUDE.md`: turn "Every app must be protected" into "… enforced by `just pocket-id lint` (pre-commit + CI)", and document how to add an exemption.
- `provision/pocket-id/CLAUDE.md`: the `exempt` schema, the rules and the L2 entry point.
- `kubernetes/apps/networking/CLAUDE.md`: one line in Envoy Gateway Conventions pointing to the guard.
- BM: `docs/areas/iam` (new enforcement mechanism). `.claude/skills/k8s-workloads` onboarding checklist: the skill directory is write-protected in the session sandbox, so the user applies that change or approves it.

## Decisions needed

- **D1 — Gaps at go-live**: (a) `temporary` exemptions with `tracking` and warnings, green from day one (RECOMMENDED: the guard protects against *new* gaps immediately while remediation proceeds); or (b) land the guard red and fix every gap first; or (c) a date-based expiry on temporary exemptions (rejected: surprise reds on unrelated commits).
- **D2 — Render engine**: flate (RECOMMENDED pending Phase 0: maintained successor, strict substitutions, documented non-zero exits) or flux-local (deprecated; observed exit 0 on a fetch failure). Migrating the existing `flux-local.yaml` workflow is a separate item.
- **D3 — Required status check on `main`**: not part of this item (RECOMMENDED: keep direct pushes; pre-commit is the primary gate). Revisit if direct-push bypasses happen.
- **D4 — jellyfin**: native SSO plugin (keeps TV/mobile clients) or a permanent exemption with Jellyfin's own auth as the control. To be decided in remediation, but the exemption shape must allow either.

## Risks & mitigations

- **False negative from an unusual route shape** → L1 keys on `hostnames` anywhere (fail-open only if a chart builds hosts without that key); L2 parity catches the rest in CI.
- **False positives slowing commits** → the hook runs only on `kubernetes/**` YAML and registry changes. Every violation names the rule and the fix.
- **Empty or partial render passing L2** → the sanity and parity checks (L2.1, L2.2). The renderer's exit code is never the only signal.
- **Exemption creep** → mandatory reason, control and gateway scope. Temporary entries warn on every run. A diff to `exempt` is reviewable in one place.
- **Guard and gateway-oidc component drift** (e.g. the component gains a second redirect host) → R3 and L2.3 derive expectations from the component's contract; change both together. A note goes in the component header.

## Acceptance criteria

1. Adding a route with an unclaimed hostname to any app fails `pre-commit` locally and the `route-auth-guard` check on a PR (both demonstrated).
2. Every fixture case in Phase 1 passes; the clean fixture exits 0.
3. On the real repo, L1 reports exactly the D1-handled gaps (as warnings under D1a) and nothing else.
4. Renaming a gate-envoy HTTPRoute without updating `HTTPROUTE_NAME` fails L2 on a PR.
5. An empty or partial render fails L2 (demonstrated with a broken chart reference).
6. The workflow passes actionlint and zizmor; actions are SHA-pinned with least-privilege permissions.
7. The docs from Phase 5 are updated and the BM `iam` area records the mechanism.

## Follow-ups (not in this item)

- Remediation of the audit gaps: home-gallery (gateway-oidc; split or drop one of photos/fenykepek per R3, then retire its Cloudflare Access app), crosswatch (gateway-oidc), jellyfin (D4), llm (gateway-oidc or remove the route if only open-webui uses it in-cluster).
- Live verification of native-gate bypass paths: calibre-web-automated (local login, anonymous browse, `/opds` basic auth, `/kobo/<token>`; `books` is in the Cloudflare `public_bypass_apps`) and paperless (`/api/` basic auth with the local admin despite `PAPERLESS_DISABLE_REGULAR_LOGIN`).
- Optional runtime net: blackbox probes asserting a 302 to `idm` for gate-envoy hosts.
- Optional: cross-check the Cloudflare Access `public_bypass_apps` hosts against the registry.
- Migrate `flux-local.yaml` to flate (D2).

## Related

- relates_to [[iam]]
- relates_to [[networking]]
- relates_to [[flux-gitops]]
- relates_to [[main-branch-protection-and-commit-signing]]

## Update — 2026-11-16: live verification (LAN, unauthenticated probes)

- [verified] Live HTTPRoutes match the repo one-to-one (34 objects incl. pocket-id-external/-internal); no route has a non-True parent condition.
- [verified] All 14 gateway-oidc SecurityPolicies are `Accepted=True, Merged=True`, `mergeType: StrategicMerge`, and each targets the exactly matching live HTTPRoute (incl. `victoria-logs-server`). The HTTPROUTE_NAME risk is not live today; L2.3 keeps it that way.
- [verified] Gate-envoy hosts (subs, logs, hubble, echo) answer 302 → `idm/authorize` without a session.
- [verified] Native-gate apps reject unauthenticated API calls (mealie, open-webui, actual, crowdsec-web-ui → 401; pingvin → 403). Only public bootstrap/config endpoints answer 200, and pingvin's `/api/configs` (44 keys) carries no secrets.
- [verified] **home-gallery is open on the LAN**: `photos` and `fenykepek` answer 200 with no auth, and `/api/database.json` returns the full media index (9.4 MB) unauthenticated. No `cf-ray` header, so this is the envoy-internal path.
- [verified] crosswatch has its own login (`/` → 302 `/login`, `/api/status` and `/api/config` 401; `/api/health` 200). Not Pocket ID.
- [verified] jellyfin: `/` → 302 `/web/` (own login). Not Pocket ID.
- [verified] llm: API key enforced (`/v1/models`, `/props`, `/slots`, `/metrics` → 401; `/health` 200). Not Pocket ID.
- [verified] **paperless accepts HTTP Basic on the REST API**: dummy Basic credentials get `Invalid username/password.` (evaluated), while no credentials get `Authentication credentials were not provided.`. Any local user with a password, including the env-provisioned admin (`PAPERLESS_ADMIN_PASSWORD`), can reach `/api/` without Pocket ID. From outside this needs the Cloudflare service token or an Access login first; on the LAN nothing else.
- [verified] calibre-web-automated: anonymous browsing is off (`/` → 302 `/login`), and the login page shows only the SSO button (no password field). `/opds` still demands HTTP Basic (`WWW-Authenticate: Basic`), i.e. local passwords remain a Pocket-ID-free path wherever a local user has one. Not tested with real credentials, by design.

## Update — 2026-11-16: remediation progress

- [done] home-gallery gated (a7208d57e): gateway-oidc on `fenykepek`, `photos` dropped. Pocket ID client and group applied; secret synced to 1Password.
- [done] paperless local-password paths blocked at the route (788e5ab1d); the paperless client was made public for Swift Paperless OIDC (a57bd368c).
- [done] calibre `/opds` and `/kobo` blocked at the route (30d017bd1).
- [open] crosswatch, jellyfin, llm still have no Pocket ID gate (own login or API key). D1 decides how the guard treats them.
- [note] Design input for the guard: the `is_public` / `extra_callback_urls` registry fields exist now; R3 must also allow the home-gallery shape (gate envoy, single hostname).

## Scope extension — 2026-11-16: remaining gaps and the LAN-side password audit

Folded into this item at the user's request (replaces the first "Follow-ups" bullet). The guard alone only stops *new* gaps; this phase closes the known ones.

### Phase 6 — Remaining Pocket ID gaps (LAN-only hosts)
- [open] **crosswatch** (`crosswatch.`, envoy-internal): own login (`/` → 302 `/login`, API 401). Add the gateway-oidc component + a `gate: envoy` client (group `media_users` or `infra_admins`). Its own login then sits behind the gate; disable it if the app allows.
- [open] **jellyfin** (`jellyfin.`, envoy-internal): own login. D4: the native SSO plugin (keeps the TV/mobile clients, which cannot do a browser OIDC redirect through Envoy) or a permanent exemption with Jellyfin auth as the control. Do not put gateway-oidc in front: it breaks every non-browser client.
- [open] **llm** (`llm.`, envoy-internal): API key enforced; only `/health` open. If nothing outside the cluster uses it (open-webui calls the Service in-cluster), remove the route. Otherwise add an exemption with the API key as the control.

### Phase 7 — LAN-side Basic / password audit
The 2026-11-16 Basic-auth analysis covered only the public gateway. Repeat it for every native-OIDC app reachable only on envoy-internal: actual (`pfm`), wallos (`subscriptions`), open-webui (`chat`), crowdsec-web-ui (`crowdsec`), grafana, sure (internal route incl. `/api`, `/admin`, `/sidekiq`).
- Method (same as the public audit): unauthenticated and dummy-credential probes per auth surface (`WWW-Authenticate`, password login, token-for-password endpoints, password reset, signup, admin paths), plus an upstream source check where a response is ambiguous.
- Known item: grafana keeps HTTP Basic for the provisioning admin (operator credential, LAN-only); decide between exemption and an internal-only path.
- Output: per app, either "no password path" or a route block like paperless/calibre, recorded here.

### Acceptance (additional)
8. crosswatch, jellyfin and llm are each either Pocket ID-gated, removed, or a justified exemption in `clients.yaml`.
9. The Phase 7 table is recorded, and every password path found is blocked or a justified exemption.
