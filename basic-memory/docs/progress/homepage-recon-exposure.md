---
title: homepage-recon-exposure
type: progress-note
permalink: home-ops/docs/progress/homepage-recon-exposure
topic: 'Stop the dashboard (homepage) from handing out the internal

  service/host/IP topology and a cluster-read service-account token to an

  unauthenticated origin request — a measured exposure, not an inferred one.'
status: done
priority: high
scope: 'The homepage pod on the envoy-external Gateway. The pod automounts a

  service-account token with a broad cluster-read ClusterRole, runs mode: cluster

  service discovery, exposes a server-side widget proxy that is a credentialed

  in-cluster relay, and sets HOMEPAGE_ALLOWED_HOSTS to "*" (host validation off);
  it

  also falls under the baseline cluster-egress + all-port world egress. Bringing the

  route under an identity gate is [[app-auth-coverage]]''s job; THIS item owns the

  data exposure and blast-radius remediation — the SA token, the RBAC breadth, the

  host validation, and the egress.'
rationale: 'Measured live by the Maestro lane (trusted over the finders): an anonymous

  request to the dashboard API returns the full internal service inventory — service

  groups, internal IP:port endpoints, and internal hostnames — with no credentials
  of

  its own (recon, not credential theft), AND the pod automounts a service-account

  token whose ClusterRole grants get/list across namespaces, pods, nodes, ingresses,

  HTTPRoutes, gateways, and metrics. So an unauthenticated origin request maps the

  whole internal surface, and any path that exfiltrates the mounted token hands over

  cluster-wide read. This is one of the two highest-REAL-value exposures measured

  today. Verified against repo file:line (helmrelease.yaml automount + ClusterRole
  +

  ALLOWED_HOSTS; config/kubernetes.yaml mode: cluster) and live read-only kubectl.

  Secret resources were never read; nothing was mutated.'
related_areas:
- networking
- k8s-workloads
- observability
options:
- Treat the SA token and the widget proxy as the exposure, not just the API response
  — the recon is harmless on its own, but the mounted cluster-read token and the credentialed
  widget relay turn a recon surface into a pivot.
- The identity gate is owned by [[app-auth-coverage]]; this item must land even if
  the gate is added, because a gate bypass or a misconfigured widget still exposes
  the token and the topology.
tags:
- roadmap
- security
- networking
- k8s-workloads
- homepage
- service-account
- proposed
---

# homepage-recon-exposure — stop the dashboard from leaking topology + a cluster-read token

## Metadata (observation-form, schema validation)

- [topic] Stop the dashboard from handing out internal topology and a cluster-read SA token to an unauthenticated origin request
- [status] proposed
- [priority] high
- [area] networking / k8s-workloads / observability
- [created] 2026-08-14

## Verification basis (how this item was built)

- Source: an adversarial audit produced 98 unverified findings; its verification phase did NOT complete. The homepage recon cluster — ids 22, 31, 23, 57 — was collapsed to ONE root cause (an unauthenticated dashboard API + an over-scoped mounted SA token + host validation off + loose egress) and carried here.
- Method: verified against repo file:line (helmrelease.yaml automount + ClusterRole + ALLOWED_HOSTS; config/kubernetes.yaml mode: cluster) and live read-only kubectl. Secret resources were never read; nothing was mutated.
- What was NOT carried here: the absence of an identity gate on this route is [[app-auth-coverage]]'s problem, not this item's. The sibling origin exposures from the same audit (home-gallery data, IdP admin surface, kopia UI, flux-webhook) were not carried into this split — this item is scoped to the dashboard only.
- Today's measured reachable state (Maestro lane, trusted over the finders): the dashboard route sits behind a Cloudflare Access gate today, but the audit premise ("assume Cloudflare provides zero protection") plus real gate-bypass / widget-misconfig risk means the origin-level exposure must be fixed regardless of the gate.

## What we gain

- An unauthenticated origin request can no longer enumerate the internal service inventory (groups, IP:port endpoints, hostnames) — the recon surface closes.
- The pod no longer carries a cluster-read service-account token, so a widget/SSRF or gate-bypass path cannot exfiltrate cluster-wide read.
- Host validation is on, so a request with a forged Host cannot trick the dashboard into rendering for a different virtual host.
- The pod's egress is scoped, so the credentialed widget proxy cannot be pivoted to arbitrary in-cluster endpoints.

## What to do (phased; each phase independently shippable)

### Phase 1 — Remove the cluster-read service-account token

- Set automountServiceAccountToken: false on the homepage pod (helmrelease.yaml).
- Narrow the ClusterRole to the few resource types homepage actually displays, read-only (get/list only), and drop the rest (namespaces/pods/nodes/ingresses/httproutes/gateways/metrics is far wider than a status board needs).
- Verify the narrowed role still lets every configured widget render; add back only the specific resources a widget genuinely needs.

### Phase 2 — Lock host validation and service-discovery scope

- Set HOMEPAGE_ALLOWED_HOSTS to the real hostname(s) the dashboard is served on (today it is "*", which disables host validation).
- Reconsider mode: cluster service discovery: keep it only if the displayed widgets genuinely require cluster-wide discovery; otherwise scope discovery to the services homepage should show, so the API does not enumerate the whole cluster by default.

### Phase 3 — Constrain the widget proxy and egress

- Add a per-app egress CiliumNetworkPolicy that selects the homepage pod and allows only the upstreams its widgets actually reach (today the pod falls under the baseline cluster-egress + all-port world egress).
- Treat the server-side widget proxy as a credentialed in-cluster relay: the egress CNP is the boundary that stops a widget-config / SSRF path from pivoting to arbitrary in-cluster endpoints using the pod's identity.

## Acceptance criteria

- automountServiceAccountToken is false on the homepage pod (kubectl get pod -o yaml).
- The ClusterRole is narrowed: kubectl auth can-i --as=system:serviceaccount:selfhosted:homepage --list returns only the resources the configured widgets need, and no cluster-wide get/list on nodes/ingresses/gateways/metrics.
- HOMEPAGE_ALLOWED_HOSTS is the real hostname (a request with a different Host is rejected).
- A per-app egress CNP selects the homepage pod; a test request from the pod to an unrelated in-cluster endpoint is denied.
- An unauthenticated origin request to the dashboard API no longer returns the full internal service inventory (manual check).

## Risks / what could break (blast radius per change)

- **Narrowing the ClusterRole (Phase 1):** too-aggressive a cut makes configured widgets error (broken status tiles). Mitigation: verify each widget after the cut, add back only what a widget needs.
- **ALLOWED_HOSTS (Phase 2):** a wrong hostname value makes the dashboard unreachable. Mitigation: set it to the exact hostname the route serves, test immediately.
- **mode: cluster → scoped (Phase 2):** some widgets may stop discovering their target service. Mitigation: keep mode: cluster if any widget needs it, and rely on the SA-token cut + egress CNP for the blast radius instead.
- **Egress CNP (Phase 3):** a too-tight CNP breaks widget upstream calls (tiles show errors). Mitigation: derive the allowlist from the actually-configured widgets, not from a guess.

## Explicitly out of scope

- The identity gate for this route → [[app-auth-coverage]] (owns "which apps lack a gate").
- The CSP / frame-ancestors / Permissions-Policy header in front of the dashboard → [[gateway-guardrails-response-headers]].
- The 4xx/401/429-spike and auth-failure alerts that would flag a recon flood against this route — edge-detection-observability (roadmap item lost from BM, not git-recoverable; descoped pending rebuild).
- The sibling origin exposures from the same audit (home-gallery data, IdP admin surface, kopia UI, flux-webhook) — not carried into this split; this item is the dashboard only.

## Related

- relates_to [[app-auth-coverage]] — owns the identity gate for this route; this item owns the data/blast-radius and must land even if the gate is added.
- relates_to [[gateway-guardrails-response-headers]] — owns the CSP / frame-ancestors header in front of the dashboard.
- (descoped) edge-detection-observability — owned the external-surface alerts (4xx/401/429 spikes, auth failures) that would flag recon against this route; item lost from BM, pending rebuild.
- relates_to [[networking]] — envoy-external route, Cilium egress CNP.
- relates_to [[k8s-workloads]] — SA token automount, ClusterRole scoping, pod egress.

## Update 2026-08-15 — Phase 2 half-landed alongside the auth gate

The dashboard received a native OIDC gate (Homepage 2.0's built-in auth, Pocket ID client `homepage`, group `infra_admins`). That gate is [[app-auth-coverage]]'s scope, not this item's, but two things this item owns moved with it.

- [done] **HOMEPAGE_ALLOWED_HOSTS is pinned** (Phase 2, first half): `"*"` became `dash.${PUBLIC_DOMAIN}` in kubernetes/apps/selfhosted/homepage/app/helmrelease.yaml. Host validation is now on.
- [observation] [gotcha] **Pinning ALLOWED_HOSTS alone would have CrashLooped the pod.** Upstream `src/middleware.js` runs host validation BEFORE the `/api/healthcheck` auth exemption, and the route matcher does not exclude the healthcheck path, so the kubelet probe (Host = pod IP) receives a 400 and trips `failureThreshold: 3`. The probes now carry an explicit `Host: localhost:3000` header, which the middleware always allows. Any other app that pins ALLOWED_HOSTS must check for the same trap.
- [measured] **The unauthenticated recon surface is closed.** Measured over envoy-internal, which bypasses Cloudflare Access and therefore measures the ORIGIN: `/api/services` returns 307 to `/auth/signin`; it previously returned the full internal service inventory. `/api/healthcheck` stays 200 as intended.
- [open] Phase 2's second half is UNTOUCHED: config/kubernetes.yaml still uses `mode: cluster` service discovery.
- [open] Phase 1 (automountServiceAccountToken false, ClusterRole narrowing) and Phase 3 (per-app egress CNP) are UNTOUCHED. The item's rationale is unchanged by the gate: the pod still mounts a cluster-read service-account token and still runs a credentialed widget proxy, and a gate bypass or widget misconfiguration still reaches both. Status stays `proposed`.
- [observation] The decision to keep Cloudflare Access in front (double gate) was taken explicitly, so the item's premise that Cloudflare provides zero protection remains the operating assumption for the remaining phases.


## Update 2026-08-15 (2) — Phase 1 RBAC hygiene landed (option A)

Delivered on main via commit f6d648887 (pushed with the user's parallel 355a6af48). Maestro lane: brief + independent verification; the Llama subterminal made the edits and the commit.

- [decision] **Option A chosen over token removal.** `automountServiceAccountToken: false` and `mode: cluster` are MUTUALLY EXCLUSIVE — cluster-mode discovery authenticates with exactly that mounted token. The roadmap's Phase 1 asks for both; they cannot both land while cluster discovery is wanted. Kept the token and the `resources` widget; removed only what grants nothing.
- [done] **ClusterRole narrowed 7 rules → 4** (kubernetes/apps/selfhosted/homepage/app/helmrelease.yaml). Dropped: the exactly-duplicated `""`/namespaces,pods,nodes rule (two upstream examples had been pasted together), and BOTH `ingresses` rules (`networking.k8s.io` + `extensions`). Kept: core namespaces/pods/nodes, gateway.networking.k8s.io httproutes+gateways, metrics.k8s.io nodes+pods, apiextensions customresourcedefinitions/status.
- [done] **`config/kubernetes.yaml`: `ingress: true` → `false`** so the discovery code path matches the revoked RBAC.
- [measured] **Zero Ingress objects in this cluster carry a `gethomepage.dev/*` annotation.** All 26 discovered entries sit on HTTPRoutes (verified by checking the parent key of every annotation block repo-wide). Only 6 annotation keys are in use: enabled, name, group, icon, pod-selector (4 entries), href (1). No `gethomepage.dev/widget.*` API widget exists anywhere in the repo.
- [observation] **What each grant actually buys** (evidence-backed): httproutes+gateways = all 26 tiles; namespaces = cluster-mode enumeration; pods = the 4 pod-selector status dots + the resources widget; nodes + metrics.k8s.io = ONLY the `resources: backend: kubernetes` CPU/memory tile (widgets.yaml:2-7); customresourcedefinitions/status = CRD-presence probe; ingresses = nothing.
- [observation] **services.yaml is not in git** — it is a 1Password field mounted as a Secret subPath (comment at helmrelease.yaml:195-196: personal/financial URLs). Its entries could in principle add `namespace:`/`podSelector:` usage that the repo cannot show. Nothing broke, so no such dependency was violated.
- [verified] Live, read-only: ClusterRole in-cluster shows the 4 rules; HelmRelease `Helm upgrade succeeded … v15`; pod 1/1 Running, 0 restarts; pod log has zero error/forbidden/warning lines; `kubectl auth can-i --as=system:serviceaccount:selfhosted:homepage` → list httproutes **yes**, list ingresses **no**, list nodes **yes**, list secrets **no**.
- [observation] **This was hygiene, not blast-radius reduction.** The revoked permissions granted nothing in practice, so the token still carries cluster-wide read. The real remediation left is Phase 3 (per-app egress CNP), which is what actually stops a widget/SSRF path from pivoting with the pod's identity.

### Still open after this round

- Phase 1 remainder: the SA token stays mounted (blocked by design on `mode: cluster` — see the decision above). A genuine cut requires giving up cluster discovery and hand-maintaining 26 entries in the 1Password services.yaml (option C, rejected today).
- Phase 2 second half: `mode: cluster` unchanged.
- Phase 3: per-app egress CiliumNetworkPolicy — UNTOUCHED, now the highest-value remaining work. Note the allowlist must cover kube-apiserver, DNS, api.openweathermap.org (widgets.yaml), the Unsplash background fetch (settings.yaml:5), the favicon fetch from ${PUBLIC_DOMAIN} (settings.yaml:11), plus whatever siteMonitor/ping targets the 1Password services.yaml holds — that last set is invisible from git and must be derived from the live config or from Hubble flow capture before the CNP is tightened.
- Further RBAC cuts are possible only by trading features: dropping the `resources` widget would additionally release nodes + all of metrics.k8s.io (option B).


## Update 2026-08-15 (3) — Phase 3 delivered: per-app egress CNP live-verified

Delivered on main via commit 5b33ccb21. Maestro lane: live measurement, design, verification; the Llama subterminal made the edits and the commit.

### The measurement that unblocked it

The previous update flagged the 1Password-held `services.yaml` as an unknown that had to be resolved before the allowlist could be trusted. Resolved by reading the live file out of the running pod:

- [measured] **`services.yaml` contains only `href` (36) and `icon` (36) keys — nothing else.** No `ping`, no `siteMonitor`, no `widget.*`, no `namespace`/`podSelector`, no `server`/`container`. Both key types are rendered client-side, so the file contributes **zero server-side egress**. The 36 hrefs are personal/financial destinations and stay out of the repo; nothing about them had to enter the policy.
- [measured] A 120s cluster-wide Hubble capture while idle showed the homepage pod opening **no outbound connections at all** — all 72 of its flows were replies from source port 3000 to kubelet probes. Homepage reaches the API and the weather service only while serving a request, so flow capture alone can never enumerate its egress; the allowlist had to come from config, with live probing as the check.

### Design — the additive-policy trap

- [gotcha] **A per-app CNP alone would have changed nothing.** Cilium policy is a union of allows, so it can only ADD. The pod sat under `allow-cluster-egress` (selector: `egress.home.arpa/custom-egress` DoesNotExist) and carried `egress.home.arpa/allow-world: "true"` — i.e. all cluster endpoints on all ports, plus 0.0.0.0/0 minus RFC1918. The CNP only bites after the pod labels flip: drop `allow-world`, add `custom-egress`. Any future per-app egress policy in this repo needs the same label swap or it is decorative.
- [decision] **`egress.home.arpa/allow-gateways: "true"` added** instead of putting the IdP in the CNP. `HOMEPAGE_OIDC_ISSUER` is the public `idm.${PUBLIC_DOMAIN}`, which resolves in-cluster to 10.245.247.245 = the `networking/envoy-internal` Service (443 → targetPort 10443) — verified live. The existing allow-gateways CCNP covers exactly that hairpin, so no hostname or IP had to be written into the repo.
- [decision] kube-apiserver rule allows **both 6443 and 443**. `KUBERNETES_SERVICE_HOST/PORT` is 10.245.0.1:443 in the pod, while the repo's only prior per-app apiserver rule (silence-operator) uses 6443 post-translation. Allowing both costs nothing and removes the guess.

### What shipped

- New `kubernetes/apps/selfhosted/homepage/app/ciliumnetworkpolicy.yaml`: egress to `toEntities: kube-apiserver` (6443 + 443) and `toFQDNs: api.openweathermap.org` (443). Wired into `kustomization.yaml`.
- `helmrelease.yaml` label block: `egress.home.arpa/allow-world` removed; `custom-egress` + `allow-gateways` added.

### Live verification (all probes run from inside the pod)

| Path | Result |
|---|---|
| `/apis/gateway.networking.k8s.io/v1/httproutes` | OK — discovery for all 26 tiles works |
| `/apis/metrics.k8s.io/v1beta1/nodes` | OK — the resources widget works |
| `/api/v1/secrets` | **403 Forbidden** — RBAC holds |
| `https://idm.${PUBLIC_DOMAIN}/.well-known/openid-configuration` | OK — the OIDC gate still works |
| `https://api.openweathermap.org/...` | HTTP 401 (auth-less probe) — TCP+TLS established, the FQDN rule works |
| `https://github.com` | **timed out — blocked** (world egress genuinely revoked) |
| `http://paperless.selfhosted.svc:8000` | **timed out — blocked** (the in-cluster pivot path is closed) |

Also: CNP `VALID=True`, pod 1/1 Running with the new labels, 0 restarts.

- [gotcha] The homepage image ships **no `curl`** — only busybox `wget` and node. A first probe round using curl reported every destination as failed, which read as a total egress outage; it was a missing binary. Busybox wget also rejects `--ca-certificate`; use `--no-check-certificate --header=` instead. Any future in-pod connectivity check here must start by confirming the client binary exists.

### Roadmap status after this round

Phase 3 is **done and live-verified** — this is the item's actual blast-radius remediation: the credentialed widget proxy can no longer reach any in-cluster endpoint other than the API server, so a widget-config or SSRF path has nowhere to pivot with the pod's identity.

Remaining, all deliberate:
- Phase 1's token cut stays blocked by the `mode: cluster` dependency (see update 2).
- Phase 2's second half (`mode: cluster` → scoped) untouched; with Phase 3 landed its value is now mostly redundant, since the egress boundary already contains the blast radius.
- Further RBAC narrowing only by trading features (option B: drop the resources widget to release nodes + metrics.k8s.io).

- [verified] 2026-08-15, human visual confirmation after the Phase 3 deploy: the dashboard was loaded in a browser and **every tile renders correctly**. This closes the one check the in-pod probes could not make. Phase 3 needs no follow-up.
- [status] partially-delivered — Phase 3 done and verified; Phase 1's token cut blocked by design (`mode: cluster`); Phase 2's second half deliberately left, its value now largely redundant behind the egress boundary.


## Closure 2026-08-15 — item closed, remaining phases deliberately dropped

Closed with the human after Phase 3 landed and the dashboard was visually confirmed. Moved from docs/roadmap to docs/progress following the repo's closure precedent ([[crowdsec-blocklist-import]]): the design rationale above is preserved in place rather than summarized away, so the reasoning survives the roadmap entry.

### What the item actually achieved

- The unauthenticated recon surface is closed (native OIDC gate; `/api/services` returns 307 to signin, measured over envoy-internal so it measures the origin, not Cloudflare).
- Host validation is on (`HOMEPAGE_ALLOWED_HOSTS` pinned), with the probe `Host: localhost:3000` workaround for the upstream middleware ordering trap.
- The ClusterRole carries only what a configured widget consumes; `get/list` on Ingress is gone along with the duplicated rule.
- The pod's egress is default-deny except kube-apiserver and the weather API, so the credentialed widget proxy has no in-cluster pivot.

### Why each remaining phase was dropped (not deferred)

- [decision] **Phase 1's token cut — impossible, not postponed.** `automountServiceAccountToken: false` and `mode: cluster` are mutually exclusive; cluster discovery authenticates with that exact token. The only way through is option C (abandon discovery, hand-maintain 26 entries in the 1Password `services.yaml`), rejected as a bad trade: permanent maintenance load for a token that grants read-only recon, on a pod that can no longer reach anything but the API server.
- [decision] **Phase 2's second half — redundant after Phase 3.** Narrowing `mode: cluster` was a blast-radius measure. The egress CNP now bounds the blast radius more strongly, since it closes the exit path rather than narrowing what discovery enumerates.
- [decision] **Option B (drop the `resources` widget to release `nodes` + `metrics.k8s.io`) — not worth it.** Those grants are read-only and the exit path is shut; the trade would cost a working tile for no measurable gain.

### Residual risk, accepted knowingly

The pod still mounts a service-account token granting cluster-wide read (namespaces, pods, nodes, httproutes, gateways, node/pod metrics). An attacker who achieves code execution inside the pod can still enumerate cluster topology. What they cannot do: read Secrets (403, verified), reach any other in-cluster service (blocked, verified), or reach the internet beyond `api.openweathermap.org` (blocked, verified). That residue is the accepted price of automatic service discovery.

### Follow-ups owned elsewhere

- The identity gate for this and other routes → [[app-auth-coverage]].
- CSP / frame-ancestors / Permissions-Policy in front of the dashboard → [[gateway-guardrails-response-headers]].
- Recon-flood detection (4xx/401/429 spikes) — was edge-detection-observability, lost from BM, still unbuilt. This item's closure does not restore it.
- [gotcha] Any future per-app egress CNP in this repo must also flip the pod labels (`allow-world` out, `custom-egress` in) or it is decorative — Cilium policy only adds allows.
