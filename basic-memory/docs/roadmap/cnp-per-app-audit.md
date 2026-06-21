---
title: cnp-per-app-audit
type: roadmap
permalink: home-ops/docs/roadmap/cnp-per-app-audit
topic: Per-app CNP rollout — ingress everywhere, egress constrained off-world
status: proposed
priority: medium
scope: 'Execution path for AD-023 (2026-06-21 revision). Hand-write a per-app CNP
  for every non-platform app: ingress always (east-west containment), egress only
  for apps that do not need open world (no-world or narrow-world full-domain). No
  shared component. Build a reference CNP first, then clone the convention; roll out
  value × tractability — crown jewel, then no-world data-holders, then narrow-world
  remainder, then ingress-only off-world apps last.'
rationale: AD-023 defines the model; this roadmap is the how and order. Ingress is
  universal and hand-written per app; egress is constrained only where it pays off
  (off-world apps), driven by hubble-live captures, not guessed. A single reference
  app fixes the skeleton everything else is cloned from.
options:
- 'Phase 0: cluster-wide Hubble baseline survey (DONE)'
- 'Phase 1: reference CNP + documented skeleton/convention; migrate existing ingress-only
  CNPs'
- 'Phase 2: crown-jewel narrow-world — onepassword-connect first'
- 'Phase 3: no-world class — cheap, high-value, no churn'
- 'Phase 4: narrow-world remainder — open-webui, paperless-gpt, backup plane'
- 'Phase 5: Class A ingress-only — off-world + low-value apps, after high-value B
  apps'
- 'Deferred: baseline world-deny tightening (separate AD, survey-gated)'
related_areas:
- networking
- k8s-workloads
decision_link: AD-023-cnp-threat-model-audit
---

# Per-app CNP rollout — ingress everywhere, egress constrained only off-world

## Metadata (observation-form, schema validation)

- [topic] Per-app CNP rollout — ingress everywhere, egress constrained off-world
- [status] proposed
- [priority] medium

## Goal

- [observation] Implement AD-023 so a compromised pod cannot freely move east-west or (where constrainable) exfiltrate, with maintenance proportional to risk
- [observation] Every per-app CNP is hand-written — no shared component; ingress is always present, egress only for apps that do not need open world
- [observation] Drive ingress consumer sets AND egress allowlists from observed traffic (`just k8s hubble-live`), not guesswork

## Current state

- [observation] Ingress-only CNPs today: paperless, paperless-gpt, tinyauth, pocket-id (+ envoy ext/int, cloudflare-tunnel)
- [observation] [correction] pingvin-share-x ingress CNP was removed during reorganization (not an egress failure) — to be re-added
- [observation] [gap] No per-app egress except cloudflare-tunnel; onepassword-connect (crown jewel) has NO CNP at all
- [observation] No reusable component — and per AD-023 we are deliberately NOT building one; every CNP is per-app and hand-written

## Approach — two egress classes (from AD-023)

- [observation] [class-A ingress-only] off-world apps (qbittorrent, *arr stack, plex, searxng, mealie, isponsorblocktv, speedtest-exporter) + low-value routed apps — ingress allowlist only, ride baseline egress, no opt-out label; east-west contained target-side
- [observation] [class-B no-world] paperless, actual, grafana, home-gallery, victoria-logs, pingvin-share-x, homepage — ingress + in-cluster/DNS egress, world denied, opt-out label
- [observation] [class-B narrow-world] onepassword-connect, open-webui, paperless-gpt, backup plane — ingress + DNS + full-domain `toFQDNs`, opt-out label

## CNP skeleton (refine at Phase 1 via the reference app)

- [observation] [ingress] envoy-external/internal (routed) · prometheus (metrics port) · `reserved:kube-apiserver` (kubelet probes + webhooks, NOT reserved:host) · named east-west consumers · LAN CIDR for LB apps (plex, k8s-gateway)
- [observation] [egress class-B only] named in-cluster peers + `allow-dns-egress` + (narrow-world) `toFQDNs` `matchName` apex + `matchPattern "*.apex"`; opt-out label `egress.home.arpa/custom-egress: ""` in the SAME commit (B-csapda)
- [observation] [verify] `just k8s hubble-live k8s:app.kubernetes.io/name=<app> 120 DROPPED` after deploy; iterate until clean

## Hubble survey methodology (`hubble-live`)

`just k8s hubble-live [label] [secs] [verdict]` (kubernetes/mod.just) captures live Hubble flows and prints a deduped `COUNT VERDICT SRC DEST PORT PROTO DIR REASON` table.

- [observation] [step] **Per-app ingress capture**: `just k8s hubble-live k8s:app.kubernetes.io/name=<app>` → real in-cluster sources (consumers, prometheus, apiserver-probe) → ingress allowlist
- [observation] [step] **Per-app egress capture (class-B only)**: same capture → real destinations (FQDNs via L7 DNS, in-cluster peers); question every destination, pick no-world vs narrow-world
- [observation] [step] **Deploy** ingress (+ class-B egress + opt-out label) in one commit → reconcile
- [observation] [step] **Verify**: `just k8s hubble-live k8s:app.kubernetes.io/name=<app> 120 DROPPED` under real usage; iterate until clean

## Fleet classification (provisional, Hubble-refined)

### Class P — platform-exempt (no CNP)

- [observation] kube-system: cilium, coredns, democratic-csi, intel-gpu-resource-driver, metrics-server, reloader, snapshot-controller
- [observation] cert-manager, flux-operator/instance/provider, external-secrets controller, volsync controller, tuppr, kube-prometheus-stack internals
- [observation] networking platform: envoy-gateway, external-dns, k8s-gateway, cloudflare-tunnel (already CNP'd)

### Class A — ingress-only (off-world + low-value)

- [observation] downloads/*: qbittorrent, prowlarr, radarr, sonarr, bazarr, seerr, maintainerr, subsyncarr — each with named east-west INGRESS to its real siblings (indexer → *arr → download client), confirmed by Hubble
- [observation] media/*: plex (LAN-only via its own LoadBalancer — ingress is a LAN-client → LB rule, fromCIDR/fromEntities), plex-trakt-sync, isponsorblocktv
- [observation] selfhosted: searxng, mealie; observability/speedtest-exporter; echo and any low-value routed app
- [observation] No egress section, no opt-out label — east-west lateral is blocked by the TARGET pods ingress, not their own egress

### Class B — no-world

- [observation] paperless, actual, grafana, home-gallery, victoria-logs, pingvin-share-x, homepage (link-only); wallos pending survey
- [observation] Cheap, no churn — strong early targets after the crown jewel

### Class B — narrow-world

- [observation] [priority-1] external-secrets/onepassword-connect — crown jewel, zero CNP today: ingress = ESO + prometheus + apiserver-probe; egress = the 1Password cloud domain only
- [observation] open-webui (LLM API), paperless-gpt (LLM), backup plane kopia/backrest/resticprofile (S3); pocket-id pending survey (SMTP?)

## Rollout phases (value × tractability)

1. [observation] **Phase 0** — cluster-wide Hubble baseline (DONE — findings below)
2. [observation] **Phase 1** — build the **reference CNP** + documented skeleton/convention (NOT a component); migrate existing ingress-only CNPs onto the convention
3. [observation] **Phase 2** — narrow-world onepassword-connect (crown jewel, biggest single gap)
4. [observation] **Phase 3** — no-world class (paperless, actual, grafana, …): cheap, high-value, no churn
5. [observation] **Phase 4** — narrow-world remainder (open-webui, paperless-gpt, backup plane)
6. [observation] **Phase 5** — Class A ingress-only (off-world + low-value), AFTER the high-value Class B apps are done — value is east-west ingress coverage
7. [observation] **Deferred** — evaluate baseline world-deny tightening as a separate AD once the survey is mature

## Related

- implements [[AD-023-cnp-threat-model-audit]]
- relates_to [[networking]]
- relates_to [[k8s-workloads]]

## Phase 0 — first capture findings (2026-06-20, 60s cluster-wide)

- [observation] [verified] hubble-live + hubble-analyze validated on a real 60s cluster-wide capture (6089 flows): FQDN / world:ip / direction / DROPPED-reason all render correctly
- [observation] [crown-jewel] onepassword-connect ONLY world egress is a single 1Password cloud endpoint (world:13.226.244.60:443) — narrow-world allowlist = DNS + that endpoint domain; confirmed tractable, stays priority-1
- [observation] [confirmed] off-world apps hold: qbittorrent (many peers, TCP+UDP), plex (plex.tv), isponsorblocktv (google/youtube) — these are Class A (ingress-only) under the revised model
- [observation] [confirmed] no-world holds (quiet in-window): paperless, grafana, actual, home-gallery, wallos, victoria-logs, homepage — only DNS + inbound probe/scrape, no world egress
- [observation] [east-west-hub] prometheus scrapes every app metrics port and kube-apiserver reaches every app port — every ingress CNP must allow both
- [observation] [finding] on this single control-plane node, kubelet health-probes + admission-webhooks carry the reserved:kube-apiserver identity (node IP = apiserver IP). Ingress probe-allow rules must use reserved:kube-apiserver (NOT reserved:host); the DROPPED verify step must confirm probes still pass on each strict ingress CNP
- [observation] [finding] DNS query names are the reliable FQDN source for narrow-world allowlists (Hubble destination_names enrichment is sparse on world flows due to connection reuse / out-of-window DNS). hubble-analyze resolves .l7.dns.query before pod_name so per-app lookups render as DNS:<fqdn>
- [observation] [finding] a 60s window misses the downloads east-west mesh (*arr → qbittorrent, prowlarr → *arr were idle) — per-app downloads INGRESS needs an activity-triggered or longer capture (trigger search/download during the window)

## Phase 0 — refinements from activity-triggered capture (2026-06-20)

- [observation] [verified] DNS-first ordering works in production: per-app DNS query names render (DNS:t.ncore.sh, DNS:ghcr.io, DNS:api.github.com, DNS:sonarr...) — narrow-world FQDN source; toFQDNs should match the bare apex (the .svc.cluster.local-suffixed variants are ndots:5 search-domain NXDOMAINs, ignore them)
- [observation] [priority-1-ready] onepassword-connect is fully specifiable from observed traffic: ingress = external-secrets (ESO) + prometheus + kube-apiserver (probes); egress = the 1Password cloud domain only. The narrow-world CNP can be written directly from data — no guessing
- [observation] [verify-item] *arr cross-links are misconfigured: bazarr/seerr query sonarr/radarr at *.media.svc.cluster.local, but all *arr run in the downloads namespace (kubectl-confirmed); the name is stale runtime config (not in repo), likely NXDOMAIN. Fix in each *arr app config (UI/DB, not a manifest): use the bare service name since caller and target share the downloads namespace. Do this before enumerating the downloads east-west INGRESS pairs so they reflect real endpoints

## Phase 0 — re-interpretation under the revised model (2026-06-21)

- [observation] the qbittorrent / plex / isponsorblocktv world-egress data is no longer used to build egress allowlists — those apps are now Class A (ingress-only); their observed east-west PAIRS instead feed the per-app INGRESS rules
- [observation] onepassword-connect single-endpoint world egress maps directly to a narrow-world full-domain `toFQDNs`; still priority-1, fully data-specified
- [observation] the *arr cross-link fix (bare service names) remains a prerequisite — but now for the downloads east-west INGRESS rules (Class A), not an egress mesh
