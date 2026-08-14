---
title: homepage-recon-exposure
type: roadmap
permalink: home-ops/docs/roadmap/homepage-recon-exposure
topic: 'Stop the dashboard (homepage) from handing out the internal

  service/host/IP topology and a cluster-read service-account token to an

  unauthenticated origin request — a measured exposure, not an inferred one.'
status: proposed
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
