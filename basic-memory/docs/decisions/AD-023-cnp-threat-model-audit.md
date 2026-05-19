---
title: AD-023-cnp-threat-model-audit
type: decision
permalink: home-ops/docs/decisions/ad-023-cnp-threat-model-audit
decision_id: AD-023
topic: Per-app CiliumNetworkPolicy threat-model audit, two-tier severity
status: active
decided_at: '2026-05-17'
decision: Targeted threat-model-based per-app CNP approach (5-8 high-value apps).
  Default Szint I (ingress-only, no opt-out label); promote to Szint II (ingress +
  strict egress + opt-out label) only when threat-model justifies. Cluster-wide baseline
  (allow-cluster-egress + allow-dns-egress L7 proxy) covers all unmarked pods.
rationale: Default-deny everywhere is overengineering for single-tenant home-lab;
  the 4f4b76eec migration caused real connectivity regressions; bjw-s 19% coverage
  confirms targeted approach; Gateway L7 SecurityPolicy handles ingress hardening;
  CNP focuses on egress + lateral-move prevention.
tradeoffs: Szint II has higher maintenance cost; "B-csapda" — opt-out label without
  paired CNP egress section breaks the pod; targeted scope means most apps remain
  baseline-only, requiring threat-model understanding from reviewers.
related_areas:
- networking
- k8s-workloads
---

# AD-023 — Per-app CiliumNetworkPolicy threat-model audit, two-tier severity

## Metadata (observation-form, schema validation)
- [decision_id] AD-023
- [status] active
- [decided_at] 2026-05-17
- [topic] Per-app CiliumNetworkPolicy threat-model audit, two-tier severity

## Decision
Use a targeted, threat-model-based approach to per-app CiliumNetworkPolicies (CNPs) — target 5-8 high-value apps with explicit CNPs, NOT cluster-wide default-deny.

Default to **Szint I** (ingress-only, no opt-out label) for routed apps. Promote to **Szint II** (ingress + strict egress + opt-out label `egress.home.arpa/custom-egress: ""`) only when the threat-model identifies concrete lateral-move, C2, or exfiltration vectors that the cluster-wide baseline does not cover.

The cluster-wide baseline (CCNPs `allow-cluster-egress` + `allow-dns-egress` L7 DNS proxy under `kubernetes/apps/kube-system/cilium/netpols/`) covers all pods that do NOT carry the opt-out label. Gateway-level L7 `SecurityPolicy` (`envoy-internal-rfc1918`) handles ingress restriction for LAN traffic.

## Rationale
- Default-deny everywhere is overengineering for a single-tenant single-node home-lab
- The earlier `4f4b76eec` CNP migration (per-app default-deny with everything) caused real connectivity regressions (UDP CT mismatch, stateful reply uncertainty)
- bjw-s reference: 86 apps / 16 CNP files = 19% per-app coverage, intentionally selective — confirms the targeted approach
- Gateway L7 SecurityPolicy provides ingress hardening at the right layer; CNP focuses on egress + east-west lateral-move prevention
- Two-tier model gives a low-cost default (Szint I) and a high-rigor escalation path (Szint II) with explicit threat-model justification

## Tradeoffs
- Szint II carries higher maintenance cost: every egress need (DB pod, Redis pod, NFS host-mount, upstream FQDN, image registry) must be enumerated; chart upgrades may require re-audit
- **B-csapda**: applying the `egress.home.arpa/custom-egress: ""` label without a paired CNP `egress:` section breaks the pod — only DNS works because `allow-dns-egress` still applies but `allow-cluster-egress` no longer covers it. Mitigation: label and egress section MUST land in the same commit
- Targeted scope means most apps stay on the baseline only — reviewers must understand the threat-model rationale per app, not assume CNP is default-deploy

## Lesson — `SecurityPolicy.principal.clientCIDRs` is unworkable on `envoy-external`

A Phase 9 hotfix initially deployed `SecurityPolicy/envoy-external-cloudflare` with 22 Cloudflare CIDRs in `principal.clientCIDRs` as defense-in-depth (mirroring the LAN `envoy-internal-rfc1918` pattern). It returned HTTP 403 "RBAC: access denied" on every request and was deleted.

Root cause: the Cloudflare Tunnel architecture means the CF edge POP IP NEVER appears as a hop visible to envoy. The flow is:

```
internet client (88.x.x.x)
  → Cloudflare edge POP
  → CF Tunnel (mTLS QUIC, persistent)
  → cloudflared pod (10.244.0.x, in-cluster)
  → envoy-external pod
```

The `cloudflared` agent overwrites `X-Forwarded-For` with the real client IP (88.x.x.x). Envoy's `ClientTrafficPolicy.numTrustedHops: 1` setting makes it look at the (1+1)=2nd entry from the right of XFF; only one entry exists, so it falls back to remote_address (cloudflared pod IP, 10.244.0.x), which matches no CF CIDR → `defaultAction: Deny` triggers.

**Architectural implication for `envoy-external`**: defense must come from the architecture, not from `clientCIDRs`:
1. ClusterIP-only Service (no LB IP / NodePort)
2. CNP ingress allowlist (only `cloudflare-tunnel` pod, plus Prometheus scrape and kubelet readiness probe)
3. CF Tunnel mTLS between edge and `cloudflared` agent

**Optional future defense-in-depth — Cloudflare Authenticated Origin Pull (AOP)**: cert-based mTLS between CF edge and the envoy origin. Immune to the XFF-translation problem because it authenticates with a client cert, not an IP. Configuration: AOP cert on the CF zone, `ClientTrafficPolicy.tls.verify.caCertificateRefs` + `requireClientCertificate: true` on envoy. Single-node home-lab benefit is marginal but the option is documented; the `clientCIDRs` workaround will never work.

## Current implementation state (2026-05-17)
- `kubernetes/apps/kube-system/cilium/netpols/` — 2 cluster-wide baseline CCNPs + dedicated Flux `Kustomization` `cilium-netpols` with `dependsOn: cilium`
- `kubernetes/apps/default/paperless/app/ciliumnetworkpolicy.yaml` — first per-app CNP at Szint I (ingress-only, allows TCP/8000 from both Gateways; egress baseline)
- `envoy-external` / `envoy-internal` CNPs — egress sections deleted, baseline takes over; ingress allowlists preserved
- `bpf.datapathMode: netkit` + `socketLB.hostNamespaceOnly: false` Cilium fix — resolves the netkit + tc-LB CT mismatch that caused SYN-ACK drops on strict ingress CNPs (CT is now recorded with pod IP, not Service IP)
- `SecurityPolicy/envoy-external-cloudflare` — deleted per the lesson above

The remaining 5-8 high-value per-app CNPs (paperless Szint II, high-value secret providers as ingress-only, optional qbittorrent/plex egress hardening) are an ongoing audit tracked separately (roadmap item).

## Related
- relates_to [[networking]]
- relates_to [[k8s-workloads]]
