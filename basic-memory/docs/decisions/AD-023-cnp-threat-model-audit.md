---
title: AD-023-cnp-threat-model-audit
type: decision
permalink: home-ops/docs/decisions/ad-023-cnp-threat-model-audit
decision_id: AD-023
topic: CiliumNetworkPolicy threat model & egress-shape containment strategy
status: active
decided_at: '2026-06-20'
decision: Threat-model-driven CNP strategy on two axes. Policy amount = three tiers
  (P platform / I ingress-only / II contained-egress). Within Tier II the egress SHAPE
  is the primary axis, driven by the app's legitimate egress profile observed via
  Hubble - no-world (deny world), narrow-world (toFQDNs allowlist), broad-world-lite
  (world wholesale but no in-cluster east-west). Per-app granularity. Containment
  is the goal - if a pod is compromised the cluster must not be a thoroughfare.
rationale: Today only ingress CNPs exist; every non-cloudflared pod rides the broad
  baseline (toEndpoints + cluster + world open) — full lateral move and full internet
  egress. Egress containment is the missing layer and the primary value of CNP here
  (edge ingress is already handled by Gateway L7). Hubble (hubble-live) makes egress
  allowlists empirical, removing the guesswork that killed the earlier opt-out-label
  attempt (pingvin-share-x was reverted).
tradeoffs: Tier II needs the opt-out label paired with an egress section in the same
  commit (B-csapda) and re-audit on upgrades. broad-world-lite blocks in-cluster lateral
  but not internet exfil (impossible for those apps) nor LAN pivot (LAN is world).
  Tier P/I keep broad baseline egress until the deferred baseline-tightening north-star.
related_areas:
- networking
- k8s-workloads
---

# AD-023 — CiliumNetworkPolicy threat model & egress-shape containment strategy

## Metadata (observation-form, schema validation)

- [decision_id] AD-023
- [status] active
- [decided_at] 2026-06-20
- [topic] CiliumNetworkPolicy threat model & egress-shape containment strategy

## Context — threat model

Single-node Talos home-lab, single-tenant, internet-exposed via Cloudflare Tunnel +
envoy-external. The design question: **if a malicious actor lands in a pod, how do we
stop the cluster from being a thoroughfare ("átjáróház")?**

- [observation] [entry-vector] internet → CF Tunnel → cloudflared → envoy-external → public-routed app — the realistic RCE entry is a vuln in an internet-exposed self-hosted app (auth-gating via tinyauth/pocket-id/per-app login lowers but does not remove this)
- [observation] [entry-vector] LAN → envoy-internal / k8s-gateway LB; supply chain → a compromised container image
- [observation] [crown-jewel] onepassword-connect + external-secrets (all secrets), kube-apiserver (takeover), data PVCs (paperless/photos/actual), backup plane + S3 creds, NAS/OMV on LAN
- [observation] [adversary-goal] "átjáróház" is TWO distinct things: (a) east-west lateral move to other pods / apiserver / LAN, and (b) egress exfil / C2 to the internet
- [decision] CNP's primary value here is egress + east-west containment; edge ingress hardening is already done by the Gateway L7 layer (SecurityPolicy) and must not be duplicated

## Current gap (2026-06-20)

- [observation] Ingress CNPs exist (paperless, paperless-gpt, pingvin-share-x, tinyauth, pocket-id + envoy ext/int, cloudflare-tunnel) — all gateway allowlists
- [observation] [gap] Egress: only cloudflare-tunnel has a per-app egress. Every other pod rides `allow-cluster-egress` (toEndpoints {} + cluster + world) — full lateral + full internet, the core átjáróház hole
- [observation] The opt-out label is used nowhere; pingvin-share-x was reverted from egress-hardened to ingress-only — guess-driven egress did not hold

## Decision — axis 1: policy amount (three tiers)

- [decision] [tier-P] **Platform-exempt** — no per-app CNP (cilium, coredns, csi, metrics-server, flux, cert-manager, external-dns, kube-prometheus internals, reloader, snapshot-controller, intel-gpu, tuppr, controllers of external-secrets/volsync). Baseline only. Needs broad/dynamic access; not the realistic RCE entry; over-constraining causes regressions
- [decision] [tier-I] **Ingress-only (component-provided)** — routed, low-value apps get a standard gateway-ingress CNP from a reusable component; egress stays on the broad baseline, consciously accepted
- [decision] [tier-II] **Contained-egress** — selected apps get a tailored ingress CNP plus a contained egress section; they opt out of the baseline so their CNP is the sole egress source

## Decision — axis 2: egress shape (primary axis within Tier II)

The shape is chosen from the app's *legitimate* egress profile (Hubble-revealed), not pre-assigned:

- [decision] [shape-no-world] in-cluster (named peers) + DNS, **world denied** — for apps with no internet need (paperless, grafana, actual, home-gallery, homepage, victoria-logs, pingvin). Cheap, no churn, blocks both exfil and lateral
- [decision] [shape-narrow-world] enumerated `toFQDNs` + named east-west + DNS — for apps with a narrow, stable internet need (onepassword-connect → 1password.com, open-webui → LLM APIs, backup plane → S3, paperless-gpt → LLM). Tightest world control; FQDN maintenance cost
- [decision] [shape-broad-world-lite] `toEntities: world` wholesale + named east-west + DNS, **no blanket cluster east-west** — for apps needing free/unpredictable internet but initiating little in-cluster (qbittorrent, the *arr stack, plex, searxng, mealie, speedtest-exporter). One coarse `world` line, zero FQDN churn; blocks in-cluster lateral move while accepting internet egress

## Egress mechanism & discipline

- [decision] All three Tier II shapes require the opt-out label `egress.home.arpa/custom-egress: ""` — otherwise the broad baseline is additive (policies OR together) and the restriction has no effect
- [observation] [B-csapda] label WITHOUT a paired egress section breaks the pod — only DNS survives. **Label and egress section MUST land in the same commit**
- [observation] DNS always works: `allow-dns-egress` (L7 proxy, matchPattern "*") applies to every pod including opted-out ones, and is the prerequisite for any `toFQDNs` allowlist
- [observation] Reply traffic is automatic: Cilium is stateful (conntrack), so replies to inbound connections (gateway→pod, sibling→pod) need no egress rule — removing cluster egress does not break replies

## Risk rubric

- [observation] [rubric] **Tier II selection** — exposure (internet > LAN > internal) × asset/blast-radius (reaches crown jewels? holds data?) × code/supply-chain risk
- [observation] [rubric] **Shape selection** — legitimate egress breadth: none → no-world; narrow+stable → narrow-world; broad/unpredictable → broad-world-lite
- [observation] The Hubble survey both informs the rubric (surprising egress = red flag) and supplies the allowlist content, then verifies via DROPPED capture

## Granularity — per-app

- [decision] Per-app CNPs, even within coherent namespaces (downloads, media). Namespace-scoped lite (one policy per ns: world + same-namespace + DNS) was considered — lower maintenance — but rejected in favor of per-app precision: per-app lite restricts even intra-namespace lateral to named pairs (a popped qbittorrent reaches only its declared siblings, not the whole ns)
- [observation] Cost: the intra-ns mesh (e.g. indexer → *arr → download client) must be enumerated per app; Hubble makes this observable rather than guessed

## Honest limits

- [observation] broad-world-lite does NOT stop internet exfil/C2 (unavoidable for apps that need free world) — for those, containment lives on the TARGET side: tight ingress allowlists on the crown jewels (a popped broad-world app still bounces off onepassword-connect)
- [observation] `world` includes the LAN (NAS/router are outside cluster identity) — lite blocks in-cluster pivot but not LAN pivot; closing that needs a CIDRGroup carve-out (deferred, higher complexity)

## Load-bearing infra facts (still true; the model depends on them)

- [observation] [datapath] Strict ingress CNPs work only because of `bpf.datapathMode: netkit` + `socketLB.hostNamespaceOnly: false` — CT is recorded with the pod IP, resolving the netkit + tc-LB mismatch that dropped SYN-ACKs. Do not revert without re-validating every ingress CNP
- [observation] [envoy-external] Edge ingress defense is architectural: ClusterIP-only + CNP allowlist (cloudflared + Prometheus + kubelet probe) + CF Tunnel mTLS. `SecurityPolicy.principal.clientCIDRs` is unworkable (cloudflared rewrites XFF, the CF POP IP is never a hop → 403); cert-based Cloudflare AOP is the only viable edge-mTLS if ever needed

## Deferred — north-star

- [decision] [deferred] Tightening the cluster-wide baseline to drop `toEntities: world` (making internet egress opt-in fleet-wide) is the strongest single lever but high blast-radius; gated behind a mature cluster-wide Hubble survey and decided separately. Current committed path is per-app, incremental

## Tradeoffs

- [observation] Tier II maintenance: opt-out discipline + FQDN re-audit (narrow-world) on upgrades; Hubble lowers but does not remove the cost
- [observation] Tier P/I keep broad baseline egress until the deferred north-star; reviewers must read the per-app shape rationale, CNP is not default-deploy

## Related

- relates_to [[networking]]
- relates_to [[k8s-workloads]]
- elaborated_in [[cnp-per-app-audit]]
