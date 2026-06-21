---
title: AD-023-cnp-threat-model-audit
type: decision
permalink: home-ops/docs/decisions/ad-023-cnp-threat-model-audit
decision_id: AD-023
topic: CiliumNetworkPolicy threat model & containment strategy
status: active
decided_at: '2026-06-20'
decision: 'Threat-model-driven, hand-written per-app CiliumNetworkPolicies (no shared
  component, no postBuild templating). Class P (platform) gets no CNP. Every other
  app gets a per-app CNP whose INGRESS is always defined (east-west containment: which
  in-cluster source may reach the pod) and whose EGRESS is a binary choice: apps that
  legitimately need open/unpredictable world stay ingress-only on the broad baseline
  (egress containment is futile for them); apps that do NOT need open world get a
  constrained egress section — no-world (in-cluster + DNS, world denied) or narrow-world
  (DNS + full-domain toFQDNs). Containment goal unchanged: a compromised pod must
  not turn the cluster into a thoroughfare.'
rationale: The átjáróház risk is two things — east-west lateral and internet exfil/C2.
  East-west is contained by per-app ingress on every app (target-side); this is NOT
  edge duplication (the Gateway L7 layer guards the envoy→app hop, the CNP restricts
  every OTHER in-cluster source). Egress containment only pays off where the app does
  not need open world — there it blocks exfil/C2 and LAN-pivot at a single source-side
  choke point. For apps that need open world (torrent/*arr/plex/search), egress restriction
  buys nothing against exfil, so it is skipped and target-side ingress carries the
  east-west job. Hubble (hubble-live) supplies both the ingress consumer set and the
  egress allowlist empirically.
tradeoffs: Per-app ingress everywhere means N policies to keep correct forever, including
  new apps (a new app with no CNP rides the open baseline). Platform-exempt pods (apiserver,
  coredns, csi) keep loose/no ingress by necessity, so a popped open-world app can
  still reach them — residual gap, accepted; crown jewels mitigate it with tight ingress.
  Class B needs the opt-out label paired with the egress section in the SAME commit
  (B-csapda) and a re-audit on upgrades. Open-world apps get no exfil/LAN-pivot protection
  (unavoidable). Baseline world-deny stays deferred.
related_areas:
- networking
- k8s-workloads
---

# AD-023 — CiliumNetworkPolicy threat model & containment strategy

## Metadata (observation-form, schema validation)

- [decision_id] AD-023
- [status] active
- [decided_at] 2026-06-20
- [revised] 2026-06-21 — egress narrowed to a binary (constrain only apps that do not need open world); shared ingress component dropped, every CNP is hand-written per app; narrow-world relaxed to full-domain allowlists; pingvin-share-x record corrected
- [topic] CiliumNetworkPolicy threat model & containment strategy

## Context — threat model

Single-node Talos home-lab, single-tenant, internet-exposed via Cloudflare Tunnel + envoy-external. The design question: **if a malicious actor lands in a pod, how do we stop the cluster from being a thoroughfare ("átjáróház")?**

- [observation] [entry-vector] internet → CF Tunnel → cloudflared → envoy-external → public-routed app — the realistic RCE entry is a vuln in an internet-exposed self-hosted app (auth-gating via tinyauth/pocket-id/per-app login lowers but does not remove this)
- [observation] [entry-vector] LAN → envoy-internal / k8s-gateway LB; supply chain → a compromised container image
- [observation] [crown-jewel] onepassword-connect + external-secrets (all secrets), kube-apiserver (takeover), data PVCs (paperless/photos/actual), backup plane + S3 creds, NAS/OMV on LAN
- [observation] [adversary-goal] "átjáróház" is TWO distinct things: (a) east-west lateral move to other pods / apiserver / LAN, and (b) egress exfil / C2 to the internet
- [decision] CNP carries two containment jobs here: per-app **ingress** contains east-west (which in-cluster source may reach the pod) on EVERY non-platform app; **egress** contains exfil/C2 + LAN-pivot, but only where the app does not need open world. Edge L7 ingress hardening stays with the Gateway SecurityPolicy layer and is not duplicated — the CNP ingress governs east-west sources, not the edge hop

## Current gap (2026-06-20)

- [observation] Ingress CNPs exist (paperless, paperless-gpt, tinyauth, pocket-id + envoy ext/int, cloudflare-tunnel) — gateway / east-west allowlists
- [observation] [gap] Egress: only cloudflare-tunnel has a per-app egress. Every other pod rides `allow-cluster-egress` (toEndpoints {} + cluster + world) — full lateral + full internet
- [observation] [correction] pingvin-share-x ingress CNP was removed during a reorganization, NOT because egress hardening failed — the earlier "guess-driven egress did not hold / pingvin reverted" framing was inaccurate; its ingress CNP will be re-added during rollout
- [observation] onepassword-connect (crown jewel) still has NO CNP at all — the single biggest gap

## Decision — policy classes

- [decision] [class-P] **Platform-exempt** — no per-app CNP (cilium, coredns, democratic-csi, metrics-server, flux, cert-manager, external-dns, kube-prometheus internals, reloader, snapshot-controller, intel-gpu, tuppr, external-secrets/volsync controllers, kube-apiserver/kubelet). Baseline only — needs broad/dynamic access, is not the realistic RCE entry, and over-constraining regresses the platform
- [decision] [all-other-apps] one **hand-written, per-app** CNP — **no shared component, no postBuild templating**. Ingress always defined; egress per the binary below
- [decision] [granularity] per-app even within coherent namespaces (downloads, media) — a popped pod reaches only its declared ingress sources / egress peers, not the whole namespace; the intra-ns mesh is enumerated from Hubble, not guessed

## Decision — ingress (every non-platform app)

- [decision] Ingress is always specified: gateway sources (envoy-external/internal) for routed apps; prometheus (metrics port); `reserved:kube-apiserver` for kubelet probes + admission webhooks; named east-west consumers (sibling/consumer rules, like pocket-id today); LAN CIDR (`fromCIDR`/`fromEntities`) for LoadBalancer-exposed apps (plex, k8s-gateway)
- [observation] Value = **east-west containment** (which in-cluster source may reach the pod), not edge duplication — this is the layer the Gateway L7 does not provide

## Decision — egress (binary)

The egress decision is a single question: does the app legitimately need open / unpredictable world egress?

- [decision] [open-world → ingress-only] apps that need open world (qbittorrent, the *arr stack, plex, searxng, mealie, isponsorblocktv, speedtest-exporter) get **no egress section and no opt-out label** — they ride the broad baseline egress. Egress containment is futile for exfil here; their east-west lateral is contained on the TARGET side by those pods ingress
- [decision] [no-world] apps with no internet need (paperless, actual, grafana, home-gallery, victoria-logs, pingvin-share-x, homepage) get egress = named in-cluster peers + DNS, **world denied**
- [decision] [narrow-world] apps with a narrow, stable internet need (onepassword-connect → 1Password cloud, open-webui → LLM API, paperless-gpt → LLM, backup plane → S3) get egress = named east-west + DNS + `toFQDNs` at **full-domain granularity** (`matchName` apex + `matchPattern "*.apex"`). No subdomain-level fiddling — allow the whole domain

## Egress mechanism & discipline

- [decision] no-world and narrow-world require the opt-out label `egress.home.arpa/custom-egress: ""` — otherwise the broad baseline ORs back in (policies are additive) and the restriction is moot. Open-world (ingress-only) apps do NOT take the label
- [observation] [B-csapda] the label WITHOUT a paired egress section breaks the pod (only DNS survives) — **label and egress section MUST land in the same commit**
- [observation] DNS always works: `allow-dns-egress` (L7 proxy, matchPattern "*") applies to every pod including opted-out ones, and is the prerequisite for any `toFQDNs` allowlist
- [observation] Reply traffic is automatic: Cilium is stateful (conntrack), so replies to inbound connections need no egress rule — removing cluster egress does not break replies

## Risk rubric

- [observation] [rubric] ingress is universal; the egress class is chosen by legitimate egress breadth — open/unpredictable → ingress-only; narrow + stable → narrow-world; none → no-world
- [observation] Hubble both informs the rubric (surprising egress = red flag) and supplies the allowlist content, then verifies via a DROPPED capture

## Honest limits

- [observation] open-world apps get NO exfil/C2 protection (unavoidable for apps that need free world) — containment for them lives on the TARGET side: tight ingress on the crown jewels (a popped open-world app bounces off onepassword-connect ingress)
- [observation] `world` includes the LAN (NAS/router are outside cluster identity) — only no-world/narrow-world apps are barred from LAN pivot; open-world apps are not (closing that needs a CIDRGroup carve-out, deferred)
- [observation] [residual] platform-exempt pods keep loose/no ingress by necessity — a popped pod can reach them east-west; accepted, mitigated by crown-jewel ingress

## Load-bearing infra facts (still true; the model depends on them)

- [observation] [datapath] Strict ingress CNPs work only because of `bpf.datapathMode: netkit` + `socketLB.hostNamespaceOnly: false` — CT is recorded with the pod IP, resolving the netkit + tc-LB mismatch that dropped SYN-ACKs. Do not revert without re-validating every ingress CNP
- [observation] [probe-identity] on this single control-plane node kubelet health-probes + admission-webhooks carry the `reserved:kube-apiserver` identity (node IP = apiserver IP). Empirically (verified 2026-06-22) strict ingress CNPs do NOT need an explicit probe-allow rule — kubelet probes reach local pods via Cilium local-host fast-path even when the CNP omits them (onepassword-connect, pocket-id, paperless are all healthy with no apiserver/host ingress rule; Hubble shows kube-apiserver→pod FORWARDED without a matching rule). If an explicit rule ever proves necessary, use `reserved:kube-apiserver` (NOT `reserved:host`)
- [observation] [east-west-hub] prometheus scrapes every app metrics port and kube-apiserver reaches every app port — every ingress CNP must allow both
- [observation] [envoy-external] Edge ingress defense is architectural: ClusterIP-only + CNP allowlist (cloudflared + Prometheus + kubelet probe) + CF Tunnel mTLS. `SecurityPolicy.principal.clientCIDRs` is unworkable (cloudflared rewrites XFF, the CF POP IP is never a hop → 403); cert-based Cloudflare AOP is the only viable edge-mTLS if ever needed

## Deferred — north-star

- [decision] [deferred] Tightening the cluster-wide baseline to drop `toEntities: world` (making internet egress opt-in fleet-wide) is the strongest single lever but high blast-radius; gated behind a mature cluster-wide Hubble survey and decided separately. Current committed path is per-app, incremental

## Validation — onepassword-connect reference (2026-06-22)

- [observation] [verified] the repo's first per-app narrow-world CNP (onepassword-connect) is live and proven: ingress (ESO + prometheus + kubelet probes) and egress (toFQDNs) all FORWARDED, zero legitimate DROPPED flows, ClusterSecretStore Valid, connect-sync `### sync complete ###`
- [observation] [autopath-prerequisite] per-app `toFQDNs` egress REQUIRES CoreDNS `autopath` to be OFF — autopath rewrites external query names into a CNAME chain that Cilium does not correlate to toFQDNs selectors, so the allowlist silently fails (connection timeout, not a visible DROPPED). Disabled in the coredns HelmRelease (`pods verified` kept for security). This is now a load-bearing prerequisite for EVERY narrow-world app
- [observation] [multi-domain] a narrow-world app may legitimately need SEVERAL external domains — onepassword-connect needs both `1password.com` (API + B5 backend) AND `1passwordusercontent.com` (file-attachment CDN). The file CDN was absent from the initial Hubble window and only surfaced via connect-sync error logs on a forced resync. Lesson: drive narrow-world allowlists from BOTH Hubble AND the app's own logs, and allow the whole domain

## Related

- relates_to [[networking]]
- relates_to [[k8s-workloads]]
- elaborated_in [[cnp-per-app-audit]]
