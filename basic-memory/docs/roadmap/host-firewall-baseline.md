---
title: host-firewall-baseline
type: roadmap
permalink: home-ops/docs/roadmap/host-firewall-baseline
topic: Node-level firewall — a network floor for the control-plane host
status: proposed
priority: medium
scope: Add a Talos network.ingressFirewall (default-drop, allow LAN-scoped management)
  and/or enable the Cilium host firewall, so the nodes sensitive ports have a network-layer
  allow-list in addition to their existing authentication.
rationale: 'A host firewall adds defense-in-depth at the node boundary: management
  and control-plane ports become reachable only from intended sources, so authentication
  is no longer the only thing between the LAN and the Talos/kubelet/etcd APIs.'
related_areas:
- talos-cluster
- networking
options:
- Talos ingressFirewall — OS-level, simplest
- Cilium host firewall — policy-as-CCNP, unified with the existing model
- Both — layered
---

# Node-level firewall — a network floor for the control-plane host

## Metadata (observation-form, schema validation)

- [topic] Node-level firewall — a network floor for the control-plane host
- [status] proposed
- [priority] medium

## What we gain

- The nodes sensitive surfaces (Talos API, kubelet, etcd, metrics) get a network allow-list, not just credential gating.
- A compromised LAN device or a stray port-forward can no longer even reach these ports.
- An explicit, reviewable definition of who may talk to the control plane.

## What to do

1. Define Talos network.ingressFirewall: default-drop, allow the LAN CIDR to the ports actually needed (6443/50000/10250), drop off-LAN sources.
2. Or enable the Cilium host firewall with CCNPs selecting reserved:host.
3. Bind purely-internal endpoints (etcd metrics) to loopback/LAN — see etcd-metrics-endpoint-binding.
4. Verify: off-scope sources are filtered; cluster operation and upgrades still function.

## Options

1. Talos ingressFirewall — OS-level, simplest
2. Cilium host firewall — policy-as-CCNP, unified with the existing model
3. Both — layered

## Related

- relates_to [[talos-cluster]]
- relates_to [[networking]]
- relates_to [[etcd-metrics-endpoint-binding]]

## Execution plan (research-backed)

### Current state
- No Talos ingress firewall: `kubernetes/talos/machineconfig.yaml.j2` has no `network.ingressFirewall` and no `NetworkDefaultActionConfig`/`NetworkRuleConfig` documents (audit confirmed; the default action is therefore accept). No Cilium host firewall (`enable-host-firewall` absent from cilium-config). KubeSpan disabled.
- Node `192.168.1.11` exposes on the LAN: 6443 (API), 50000/50001 (Talos apid), 10250 (kubelet), 2379/2380/2381 (etcd), 9100 (node-exporter), 4240/4244 (Cilium). Auth gates them; there is no network allow-list.
- Apply path: `just talos render-config k8s-cp0` (dry-run merge) then `just talos apply-node k8s-cp0` (mod.just:276-277 → `talosctl apply-config`). This is a **user-approved cluster-mutating op** per .claude policy.

### Target state
- The node's management/data ports are reachable only from the LAN (and cluster), with off-LAN sources dropped at the OS — defense-in-depth beneath the existing authn.

### Implementation steps
1. **Confirm the Talos v1.13 firewall schema** for this node: `talosctl -n k8s-cp0 get networkdefaultactionconfig` and check the docs for the multi-document form (Talos uses separate machine-config documents `kind: NetworkDefaultActionConfig` + `kind: NetworkRuleConfig`, not a nested `machine.network.ingressFirewall` map, in current versions). Verify before authoring.
2. **Author the firewall documents** (append as extra YAML documents in the machineconfig template, or a node patch under `kubernetes/talos/nodes/`). Illustrative:
   ```yaml
   ---
   apiVersion: v1alpha1
   kind: NetworkDefaultActionConfig
   ingress: block
   ---
   apiVersion: v1alpha1
   kind: NetworkRuleConfig
   name: allow-lan-mgmt
   portSelector:
     ports: [50000, 50001, 6443, 10250, 2379, 2380, 2381]
     protocol: tcp
   ingress:
     - subnet: 192.168.1.0/24
   ---
   apiVersion: v1alpha1
   kind: NetworkRuleConfig
   name: allow-cluster-pod-svc
   portSelector: { ports: [6443, 2381], protocol: tcp }
   ingress:
     - subnet: 10.244.0.0/16   # POD_CIDR
     - subnet: 10.245.0.0/16   # SVC_CIDR
   ```
   Adjust to Hubble/observed needs; Talos always permits Cilium/VXLAN and health internally — validate.
3. **Dry-run** `just talos render-config k8s-cp0` and eyeball the merged firewall docs.
4. **Apply (user-approved):** `just talos apply-node k8s-cp0` — Talos applies ingress-firewall changes **without a reboot** (networking phase). Keep a console/physical path available.
5. Alternatively/additionally enable the **Cilium host firewall** (`enable-host-firewall: "true"` in cilium-config values + a CCNP selecting `reserved:host`) — unifies with the existing CCNP model but is more complex; the Talos-native firewall is the simpler first step.

### Verification
- From an off-LAN host: `nc -vz 192.168.1.11 50000` / `6443` → filtered/timeout.
- From the LAN admin box: `talosctl -n k8s-cp0 version` and `kubectl get nodes` still work.
- Cilium/etcd/kubelet stay healthy: `kubectl get nodes`, `kubectl -n kube-system get pods`.

### Rollback & safety
- Revert the config and `just talos apply-node`. Because it's networking-phase, no reboot.
- **CRITICAL single-node risk:** a wrong `ingress: block` default without the correct allow rules **locks out the Talos API and kube-apiserver** — recovery then needs console/maintenance access. Always: (a) include the LAN allow rule for 50000+6443 BEFORE setting default block, (b) dry-run render first, (c) have physical/IPMI access ready, (d) apply during a window.

### Gotchas & dependencies
- Verify the exact CRD/document schema for the running Talos version — the firewall API has evolved.
- Pairs with `etcd-metrics-endpoint-binding` (this firewall is the practical way to gate :2381 without breaking scrape).

### Effort
M (~3–4h incl. schema verification + careful staged apply).
