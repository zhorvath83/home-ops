---
title: AD-003-cilium-kube-proxy-replacement
type: decision
permalink: home-ops/docs/decisions/ad-003-cilium-kube-proxy-replacement
decision_id: AD-003
topic: Cilium CNI in kube-proxy replacement mode
status: active
decided_at: '2025-10-01'
decision: Calico → Cilium, with kube-proxy disabled at the Talos level and Cilium
  taking over the service routing data path.
rationale: All three reference repositories use Cilium Performance gain from eBPF
  datapath, netkit, and BBR is measurable even on a single node Cilium L2 announcement
  replaces MetalLB — one fewer component Hubble UI provides observability that has
  debug value even on a single node Native Gateway API support future-proofs the ingress
  layer
tradeoffs: Fresh install (no in-place Calico→Cilium migration) — but the big-bang
  cutover model absorbs this More complex config than Calico — BPF masq, DSR, hostfirewall
  each require understanding
related_areas:
- networking
- talos-cluster
---

# AD-003 — Cilium CNI in kube-proxy replacement mode

## Metadata (observation-form, schema validation)
- [decision_id] AD-003
- [status] active
- [decided_at] 2025-10-01
- [topic] Cilium CNI in kube-proxy replacement mode

## Decision
Calico → Cilium, with kube-proxy disabled at the Talos level and Cilium taking over the service routing data path.

## Rationale
- All three reference repositories use Cilium
- Performance gain from eBPF datapath, netkit, and BBR is measurable even on a single node
- Cilium L2 announcement replaces MetalLB — one fewer component
- Hubble UI provides observability that has debug value even on a single node
- Native Gateway API support future-proofs the ingress layer

## Tradeoffs
- Fresh install (no in-place Calico→Cilium migration) — but the big-bang cutover model absorbs this
- More complex config than Calico — BPF masq, DSR, hostfirewall each require understanding

## Related
- relates_to [[networking]]
- relates_to [[talos-cluster]]
