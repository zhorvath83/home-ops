---
title: cnp-per-app-audit
type: roadmap
permalink: home-ops/docs/roadmap/cnp-per-app-audit
topic: CNP rollout by egress shape, Hubble-driven
status: proposed
priority: medium
scope: Execution path for AD-023 — classify the fleet by egress shape, build a reusable
  Tier I ingress component, and roll out per-app contained-egress CNPs (no-world /
  narrow-world / broad-world-lite) from Hubble observations, value × tractability
  first.
rationale: AD-023 defines the model; this roadmap is the how and the order. Every
  egress allowlist is built from hubble-live captures, not guessed.
options:
- 'Phase 0: cluster-wide Hubble baseline survey — confirm shapes and east-west pairs'
- 'Phase 1: Tier I ingress component + migrate existing ingress-only CNPs'
- 'Phase 2: crown-jewel narrow-world — onepassword-connect first'
- 'Phase 3: no-world class — cheap, high-value, no churn'
- 'Phase 4: broad-world-lite — downloads/* and media/* per-app'
- 'Phase 5: narrow-world remainder — open-webui, backup plane'
- 'Deferred: baseline world-deny tightening (separate decision, survey-gated)'
related_areas:
- networking
- k8s-workloads
decision_link: AD-023-cnp-threat-model-audit
---

# CNP rollout by egress shape, Hubble-driven

## Metadata (observation-form, schema validation)

- [topic] CNP rollout by egress shape, Hubble-driven
- [status] proposed
- [priority] medium

## Goal

- [observation] Implement AD-023 so a compromised pod cannot freely move east-west or exfiltrate, with maintenance proportional to risk
- [observation] Drive every egress allowlist from observed traffic (`just k8s hubble-live`), not guesswork — this is what makes egress containment sustainable this time

## Current state

- [observation] Ingress-only CNPs: paperless, paperless-gpt, pingvin-share-x, tinyauth, pocket-id (+ envoy ext/int, cloudflare-tunnel)
- [observation] [gap] No per-app egress except cloudflare-tunnel; onepassword-connect (crown jewel) has NO CNP at all
- [observation] No reusable ingress component yet (`components/`: common, forward-auth, gpu, volsync)

## Hubble survey methodology (`hubble-live`)

`just k8s hubble-live [label] [secs] [verdict]` (kubernetes/mod.just) captures live Hubble flows and prints a deduped `COUNT VERDICT SRC DEST PORT PROTO DIR REASON` table.

- [observation] [step] **Cluster-wide baseline**: `just k8s hubble-live` during normal activity → steady-state east-west + egress graph; confirms shape classification and east-west pairs
- [observation] [step] **Per-app capture**: `just k8s hubble-live k8s:app.kubernetes.io/name=<app>` → real destinations (FQDNs via L7 DNS, in-cluster peers, apiserver, world)
- [observation] [step] **Draft egress** from observed flows AND threat-model reasoning — question every destination; pick the shape (no-world / narrow-world / broad-world-lite)
- [observation] [step] **Deploy** ingress + egress CNP + opt-out label (same commit) → reconcile
- [observation] [step] **Verify**: `just k8s hubble-live k8s:app.kubernetes.io/name=<app> 120 DROPPED` → catch over-tight drops under real usage, iterate until clean

## Tier I ingress component (design direction — decide at Phase 1)

- [observation] [option-A] Generic label-selected component: CNP matches a shared opt-in label, allows ingress from envoy-external+internal to all ports. Zero per-app params; less port precision
- [observation] [option-B] Component + Flux postBuild substitution: per-app `${APP_NAME}`/`${APP_PORT}` vars drive a templated CNP. Port-precise, matches existing postBuild pattern
- [observation] Tier II apps add their east-west ingress (sibling/consumer rules) on top of the component baseline, like pocket-id does today
- [observation] LoadBalancer-exposed apps (plex, k8s-gateway) take a LAN-client ingress rule (fromCIDR/fromEntities on the LB ports), NOT the gateway component — the component is gateway-ingress only

## Fleet classification by egress shape (provisional, Hubble-refined)

Starting hypothesis from app architecture; Phase 0 survey confirms or moves apps.

### Tier P — platform-exempt (no CNP)

- [observation] kube-system: cilium, coredns, democratic-csi, intel-gpu-resource-driver, metrics-server, reloader, snapshot-controller
- [observation] cert-manager, flux-operator/instance/provider, external-secrets controller, volsync controller, tuppr, kube-prometheus-stack internals
- [observation] networking platform: envoy-gateway, external-dns, k8s-gateway, cloudflare-tunnel (already CNP'd)

### Tier II — no-world (in-cluster + DNS, world denied)

- [observation] paperless, grafana, actual, home-gallery, victoria-logs, pingvin-share-x, homepage (link-only); wallos pending survey
- [observation] Cheap, no churn — strong early targets

### Tier II — narrow-world (toFQDNs allowlist)

- [observation] [priority-1] external-secrets/onepassword-connect — crown jewel, zero CNP today: tight ingress (ESO + Prometheus) + egress to the 1Password endpoint only
- [observation] open-webui (LLM API FQDNs), paperless-gpt (LLM), backup plane kopia/backrest/resticprofile (S3 endpoint); pocket-id pending survey (SMTP?)

### Tier II — broad-world-lite (world wholesale, no in-cluster east-west)

- [observation] downloads/* per-app: qbittorrent, prowlarr, radarr, sonarr, bazarr, seerr, maintainerr, subsyncarr — each with named east-west to its real siblings (indexer → *arr → download client), confirmed by Hubble
- [observation] media/* : plex (LAN-only via its own LoadBalancer — no internet route, no gateway; lower entry probability → lower rollout priority, but broad world egress (plex.tv / metadata / relay) still fits the lite shape. Ingress is a LAN-client → LB rule (fromCIDR/fromEntities), like k8s-gateway — NOT the gateway component), plex-trakt-sync, isponsorblocktv
- [observation] selfhosted: searxng (search engines), mealie (recipe scraping)
- [observation] observability/speedtest-exporter (low value, clean lite example)

### Tier I — ingress-only via component (egress baseline accepted)

- [observation] echo and any low-value routed app not worth the opt-out discipline; existing hand-written ingress-only CNPs migrate onto the component unless promoted to Tier II

## Rollout phases (value × tractability)

1. [observation] **Phase 0** — cluster-wide Hubble baseline survey; finalize shape classification and east-west pairs
2. [observation] **Phase 1** — build Tier I ingress component; migrate existing ingress-only CNPs
3. [observation] **Phase 2** — narrow-world onepassword-connect (crown jewel, biggest single gap)
4. [observation] **Phase 3** — no-world class (paperless, grafana, …): cheap, high-value, no churn
5. [observation] **Phase 4** — broad-world-lite: downloads/* then media/*, per-app, Hubble-driven, one app at a time
6. [observation] **Phase 5** — narrow-world remainder (open-webui, backup plane)
7. [observation] **Deferred** — evaluate baseline world-deny tightening as a separate AD once the survey is mature

## Related

- implements [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[k8s-workloads]]

## Phase 0 — first capture findings (2026-06-20, 60s cluster-wide)

- [observation] [verified] hubble-live + hubble-analyze validated on a real 60s cluster-wide capture (6089 flows): FQDN / world:ip / direction / DROPPED-reason all render correctly
- [observation] [crown-jewel] onepassword-connect's ONLY world egress is a single 1Password cloud endpoint (world:13.226.244.60:443) — narrow-world allowlist = DNS + that endpoint; confirmed tractable, stays priority-1
- [observation] [confirmed] broad-world-lite holds: qbittorrent (many peers, TCP+UDP), plex (plex.tv), isponsorblocktv (google/youtube)
- [observation] [confirmed] no-world holds (quiet in-window): paperless, grafana, actual, home-gallery, wallos, victoria-logs, homepage — only DNS + inbound probe/scrape, no world egress
- [observation] [east-west-hub] prometheus scrapes every app's metrics port and kube-apiserver reaches every app port — every ingress CNP (Tier I component included) must allow both
- [observation] [finding] on this single control-plane node, kubelet health-probes + admission-webhooks carry the reserved:kube-apiserver identity (node IP = apiserver IP). Ingress probe-allow rules must use reserved:kube-apiserver (NOT reserved:host); the DROPPED verify step must confirm probes still pass on each strict ingress CNP
- [observation] [finding] DNS query names are the reliable FQDN source for narrow-world allowlists (Hubble destination_names enrichment is sparse on world flows due to connection reuse / out-of-window DNS). hubble-analyze now resolves .l7.dns.query before pod_name so per-app lookups render as DNS:<fqdn>
- [observation] [finding] a 60s window misses the downloads east-west mesh (*arr → qbittorrent, prowlarr → *arr were idle) — per-app downloads egress needs an activity-triggered or longer capture (trigger search/download during the window)

## Phase 0 — refinements from activity-triggered capture (2026-06-20)

- [observation] [verified] DNS-first ordering works in production: per-app DNS query names now render (DNS:t.ncore.sh, DNS:ghcr.io, DNS:api.github.com, DNS:sonarr...) — this is the narrow-world FQDN source, and toFQDNs rules should match the bare apex name (the .svc.cluster.local-suffixed variants are ndots:5 search-domain NXDOMAINs, ignore them)
- [observation] [priority-1-ready] onepassword-connect is fully specifiable from observed traffic: ingress = external-secrets (ESO) + prometheus + kube-apiserver (probes); egress = world:13.226.244.60:443 (1Password cloud) only. The narrow-world CNP can be written directly from data — no guessing
- [observation] [verify-item] *arr cross-links are misconfigured: bazarr/seerr query sonarr/radarr at *.media.svc.cluster.local, but all *arr run in the downloads namespace (kubectl-confirmed); the name is stale runtime config (not in repo), likely NXDOMAIN. Fix in each *arr app's own config (UI/DB, not a manifest): use the bare service name (e.g. sonarr) since caller and target share the downloads namespace — this resolves correctly via the first search domain AND eliminates the ndots:5 search-domain explosion. Do this before writing the downloads east-west mesh allowlist so it reflects real endpoints
