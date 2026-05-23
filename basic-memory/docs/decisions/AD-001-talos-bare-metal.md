---
title: AD-001-talos-bare-metal
type: decision
permalink: home-ops/docs/decisions/ad-001-talos-bare-metal
decision_id: AD-001
topic: Talos Linux on bare metal HP, not as a VM on Proxmox
status: active
decided_at: '2025-10-01'
decision: Run Talos directly on bare-metal HP ProDesk 600 G6 DM, not as a VM under
  Proxmox.
rationale: Single-node simplicity; no co-tenant VMs planned; 64GB RAM plenty without
  Proxmox pooling; i7-10700T overkill for a Talos VM workload; Talos immutable model
  fits existing Flux GitOps pattern.
tradeoffs: No VM snapshot rollback (recovery via etcd snapshot + VolSync restore);
  manual USB recovery (no IPMI/iLO); future OPNsense/HAOS VM would require KubeVirt
  or Proxmox migration.
related_areas:
- talos-cluster
---

# AD-001 — Talos Linux on bare metal HP, not as a VM on Proxmox

## Metadata (observation-form, schema validation)

- [decision_id] AD-001
- [status] active
- [decided_at] 2025-10-01
- [topic] Talos Linux on bare metal HP, not as a VM on Proxmox

## Decision

Run Talos directly on bare-metal HP ProDesk 600 G6 DM, not as a VM under Proxmox.

## Rationale

- Single-node setup is simpler without the Proxmox layer (one less patch cycle)
- No other VM is planned alongside (router / HAOS / NAS — the NAS stays separate on the M93p)
- 64 GB RAM is plenty for K8s alone; no Proxmox-pooling advantage
- The i7-10700T (8c/16t) is more CPU than a Talos VM workload could realistically use — wasted on an extra layer
- Talos's immutable model fits the existing Flux GitOps pattern naturally

## Tradeoffs

- No VM snapshot rollback — recovery path is etcd snapshot + VolSync restore
- Recovery requires a manual USB stick (no IPMI/iLO on this hardware)
- If a future workload needs an OPNsense / HAOS VM, this becomes a refactor: either KubeVirt or migrate back to Proxmox

## Related

- relates_to [[talos-cluster]]
