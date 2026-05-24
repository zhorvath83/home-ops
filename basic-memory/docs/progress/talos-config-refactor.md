---
title: talos-config-refactor
type: note
permalink: home-ops/docs/roadmap/talos-config-refactor
topic: Talos machine config — consensus-driven refactor from community comparison
status: implemented
priority: medium
scope: 'Adopt Talos machine config settings supported by community consensus (billimek,
  bjw-s, buroa, onedr0p, szinn). Settings are assessed on two axes: community consensus
  strength (how many of 5 use it) and single-node relevance (does it help us). Only
  settings that pass BOTH filters are adopted.'
related_areas:
- talos-cluster
---

# Talos machine config — consensus-driven refactor

## Metadata (observation-form, schema validation)

- [topic] Talos machine config — consensus-driven refactor from community comparison
- [status] proposed
- [priority] medium

## Sources

| Source | Cluster | Nodes | Tool |
|--------|---------|-------|------|
| billimek | home | 1 CP + 7 workers | talhelper |
| bjw-s | home-ops | 3 CP | minijinja + patch |
| buroa | k8s-gitops | 3 CP | minijinja + patch |
| onedr0p | home-ops | 3 CP | minijinja + patch |
| szinn | k8s-homelab | 3 CP + 3 workers | minijinja + patch |
| **us** | main | 1 CP | minijinja + patch |

All clusters: Talos v1.13.2, K8s v1.36.1, Cilium CNI, no kube-proxy, no CoreDNS.

## Consensus Matrix

### etcd

| Setting | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|---------|----------|-------|-------|---------|-------|-----|-----------|
| auto-compaction-mode=periodic | YES | no | no | no | no | no | 1/5 |
| auto-compaction-retention=1h | YES | no | no | no | no | no | 1/5 |
| listen-metrics-urls=0.0.0.0:2381 | YES | YES | YES | YES | YES | YES | 5/5 |
| advertisedSubnets | YES | YES | YES | YES | YES | YES | 5/5 |

**Verdict**: auto-compaction is only billimek (1/5), but the reasoning is sound. The others likely haven't hit disk pressure yet. Worth adopting for single-node with shared NVMe.

### Kubelet

| Setting | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|---------|----------|-------|-------|---------|-------|-----|-----------|
| imageGCHighThresholdPercent=70 | YES | no | no | no | YES | no | 2/5 |
| imageGCLowThresholdPercent | 50 | - | - | - | 65 | - | 2/5 |
| serializeImagePulls=false | YES | YES | YES | YES | YES | YES | 5/5 |
| defaultRuntimeSeccompProfileEnabled=true | no | YES | YES | YES | YES | YES | 4/5 |
| disableManifestsDirectory=true | no | YES | YES | YES | YES | YES | 4/5 |
| maxPods=150 | no | YES | no | no | no | YES | 1/5 (us+bjw-s) |

**Verdict**: imageGC 70/50 — emerging consensus (2/5 agree on 70 high). Worth adopting.

### Machine features

| Setting | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|---------|----------|-------|-------|---------|-------|-----|-----------|
| diskQuotaSupport=true | no | YES | YES | YES | YES | YES | 4/5 |
| apidCheckExtKeyUsage=true | no | YES | YES | YES | YES | YES | 4/5 |
| rbac=true | no | YES | no | YES | YES | no | 3/5 |
| hostDNS.enabled=true | YES | YES | YES | YES | YES | YES | 5/5 |
| hostDNS.resolveMemberNames=true | YES | YES | YES | YES | YES | YES | 5/5 |
| hostDNS.forwardKubeDNSToHost=true | no | no | YES | YES | YES | YES | 3/5 |
| kubePrism port=7445 | no | YES | YES | YES | YES | YES | 4/5 |
| kubernetesTalosAPIAccess.enabled | YES | YES | YES | YES | YES | YES | 5/5 |
| allowedRoles: os:etcd:backup | YES | no | no | no | no | no | 1/5 |

**Verdict**: We already match or exceed consensus. Only rbac=true needs explicit addition.

### kubernetesTalosAPIAccess namespaces

| Namespace | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|-----------|----------|-------|-------|---------|-------|-----|-----------|
| system-upgrade | YES | YES | YES | YES | YES | YES | 5/5 |
| actions-runner-system | no | YES | YES | YES | YES | no | 4/5 |
| kube-system | YES | no | no | no | no | no | 1/5 |

**Verdict**: actions-runner-system is 4/5 but we don't run GHA self-hosted runners. Not needed now.

### API server / controller-manager feature gates

| Setting | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|---------|----------|-------|-------|---------|-------|-----|-----------|
| HPAScaleToZero=true (api-server) | YES | YES | YES | YES | YES | no | 5/5 |
| HPAScaleToZero=true (controller-mgr) | YES | YES | YES | YES | no | no | 4/5 |
| enable-aggregator-routing=true | YES | YES | YES | YES | YES | YES | 5/5 |

**Verdict**: HPAScaleToZero is universal (5/5). On single-node resources are scarcer — workloads that can scale to zero free CPU/RAM for others. Worth adopting.

### Scheduler

| Setting | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|---------|----------|-------|-------|---------|-------|-----|-----------|
| ImageLocality disabled | YES | no | YES | YES | YES | no | 4/5 |
| PodTopologySpread custom | YES | no | YES | YES | YES | no | 4/5 |
| bind-address=0.0.0.0 | YES | YES | YES | YES | YES | YES | 5/5 |

**Verdict**: 4/5 disable ImageLocality + tune PodTopologySpread. Single-node: irrelevant. Skip.

### Sysctls

| Sysctl | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|--------|----------|-------|-------|---------|-------|-----|-----------|
| fs.inotify.max_user_instances=8192 | YES | YES | YES | YES | YES | YES | 5/5 |
| fs.inotify.max_user_watches=1048576 | YES | YES | YES | YES | YES | YES | 5/5 |
| net.core.default_qdisc=fq | no | YES | YES | YES | YES | YES | 4/5 |
| net.core.rmem_max=67108864 | YES | YES | 268M | YES | YES | YES | 4/5 (64M) |
| net.core.wmem_max=67108864 | YES | YES | 268M | YES | YES | YES | 4/5 (64M) |
| net.ipv4.tcp_congestion_control=bbr | no | YES | YES | YES | YES | YES | 4/5 |
| net.ipv4.tcp_fastopen=3 | YES | YES | YES | YES | YES | YES | 5/5 |
| net.ipv4.tcp_mtu_probing=1 | no | YES | YES | YES | YES | YES | 4/5 |
| net.ipv4.tcp_slow_start_after_idle=0 | no | YES | no | YES | no | YES | 2/5 |
| net.ipv4.tcp_window_scaling=1 | no | YES | YES | YES | YES | YES | 4/5 |
| net.ipv4.tcp_notsent_lowat=131072 | no | YES | YES | YES | no | YES | 3/5 |
| net.ipv4.neigh.default.gc_thresh* | no | YES | no | YES | YES | YES | 3/5 |
| net.ipv4.ping_group_range | no | YES | YES | YES | no | YES | 3/5 |
| sunrpc.tcp_*_slot_table_entries=128 | no | YES | YES | YES | YES | YES | 4/5 |
| user.max_user_namespaces=11255 | YES | YES | no | YES | YES | YES | 4/5 |
| vm.nr_hugepages=1024 | YES | YES | no | YES | YES | YES | 4/5 |
| buroa 10GbE extras (somaxconn etc.) | no | no | YES | no | no | no | 1/5 |

**Verdict**: Our sysctls already match or exceed 4/5 consensus. buroa 10GbE extras (1/5) not relevant for 1GbE.

### containerd

| Setting | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|---------|----------|-------|-------|---------|-------|-----|-----------|
| discard_unpacked_layers=false | YES | YES | YES | YES | YES | YES | 5/5 |
| device_ownership_from_security_context=true | YES | YES | YES | YES | YES | YES | 5/5 |
| enable_unprivileged_ports=true | no | YES | no | no | YES | YES | 2/5 |
| enable_unprivileged_icmp=true | no | YES | no | no | YES | YES | 2/5 |

**Verdict**: We already have all four. No change needed.

### NFS mount config

| Setting | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|---------|----------|-------|-------|---------|-------|-----|-----------|
| nconnect=16 | YES | no | YES | no | YES | no | 3/5 |
| nconnect=8 | no | YES | no | YES | no | YES | 2/5 |
| rsize/wsize=1048576 | no | YES | no | YES | no | YES | 2/5 |
| rsize/wsize=4194304 | no | no | YES | no | no | no | 1/5 |

**Verdict**: nconnect 16 leads 3/5. Concurrent NFS I/O benefits from more connections even on 1GbE — less head-of-line blocking. Worth adopting.

### Kernel args / security

| Setting | billimek | bjw-s | buroa | onedr0p | szinn | us | Consensus |
|---------|----------|-------|-------|---------|-------|-----|-----------|
| sysctl.kernel.kexec_load_disabled=1 | no | no | no | YES | YES | no | 2/5 |
| install.wipe=false | no | no | no | YES | YES | no | 2/5 |

**Verdict**: Both are low-risk defensive settings. Worth adopting.

### Watchdog

3/5 use 5m timeout. We match. No change.

## Adopt — 7 items

### 1. etcd auto-compaction (HIGH value)

**Only billimek (1/5), but strong reasoning.**

Default: etcd never compacts. On our PC801 NVMe (1 TB, shared OS + etcd + EPHEMERAL), unbounded growth is a real disk-pressure risk. Others likely haven't hit this yet.

- `auto-compaction-mode: periodic`
- `auto-compaction-retention: "1h"`

1h retention is safe. K8s watchers re-list if they request a compacted revision. etcd project recommends periodic compaction for production.

### 2. Kubelet imageGC thresholds (MEDIUM value)

**billimek + szinn (2/5), both agree on 70 for high.**

- `imageGCHighThresholdPercent: 70`
- `imageGCLowThresholdPercent: 50`

More aggressive GC on shared NVMe reduces disk-pressure eviction risk. Negligible re-pull overhead on fast NVMe.

### 3. HPAScaleToZero feature gate (MEDIUM value)

**5/5 universal consensus.**

Enables HPA to scale workloads to zero replicas. On single-node this is *more* valuable, not less — resources are scarcer when everything shares one machine. Workloads that don't need to run 24/7 (dev tools, batch jobs, occasional UIs) can consume zero CPU/RAM when idle. The feature gate is a prerequisite: without it, minReplicas=0 in HPA is simply ignored.

- api-server: `feature-gates: HPAScaleToZero=true`
- controller-manager: `feature-gates: HPAScaleToZero=true`

### 4. NFS nconnect=16 (LOW value)

**3/5 consensus (billimek, buroa, szinn).**

nconnect is about concurrent TCP connections for parallel NFSv4 ops, not raw bandwidth ceiling. Even on 1GbE, multiple pods doing NFS I/O simultaneously benefit from more connections — less head-of-line blocking. Our media workloads (downloads, Plex, etc.) generate concurrent NFS traffic.

- Change `nconnect=8` to `nconnect=16` in `/etc/nfsmount.conf`

### 5. install.wipe=false (LOW value)

**onedr0p + szinn (2/5).**

Prevents Talos from wiping the install disk on re-apply. Defensive, zero operational cost.

### 6. sysctl.kernel.kexec_load_disabled=1 (LOW value)

**onedr0p + szinn (2/5).**

Security hardening — prevents kexec syscall after boot. Zero operational impact. Added to schematic.yaml extraKernelArgs.

### 7. rbac=true (LOW value)

**3/5 (bjw-s, onedr0p, szinn).**

Talos v1.5+ default is true — already active in practice. But explicit declaration of a security-critical feature is better than relying on defaults. One line, zero cost.

## Skip — consensus but no single-node value

| Setting | Consensus | Why skip |
|---------|-----------|---------|
| ImageLocality disabled | 4/5 | One node — always same node, scheduling is trivial |
| PodTopologySpread custom | 4/5 | One node — no topology to spread across |
| actions-runner-system namespace | 4/5 | No GHA self-hosted runners |

## Skip — low consensus or already covered

| Setting | Consensus | Why skip |
|---------|-----------|---------|
| os:etcd:backup role | 1/5 | Nice-to-have, not needed now |
| PodSecurity admission delete | 1/5 | Security downgrade |
| buroa 10GbE sysctls | 1/5 | 1GbE NIC |
| OOM killer disable | 1/5 | Risky |
| szinn security disabling | 1/5 | Too aggressive |
| node topology labels | 3/5 | Low value on single-node now, consider if multi-node |
| forwardKubeDNSToHost=false | 2/5 | We need LAN DNS |
| intel_iommu=on + iommu=pt | 3/5 | No PCI passthrough need, DMA protection marginal for home server |
| i915.enable_guc=3 | 2/5 | Comet Lake differs from Meteor Lake, risk of instability |
| MTU 9000 jumbo frames | 3/5 | Infrastructure-level change (switch, NAS), separate project |

## Implementation

1. Add etcd auto-compaction to `machineconfig.yaml.j2` under `cluster.etcd.extraArgs`:

   ```yaml
   auto-compaction-mode: periodic
   auto-compaction-retention: "1h"
   ```

2. Add kubelet imageGC thresholds to `machineconfig.yaml.j2` under `machine.kubelet.extraConfig`:

   ```yaml
   imageGCHighThresholdPercent: 70
   imageGCLowThresholdPercent: 50
   ```

3. Add HPAScaleToZero feature gate to api-server and controller-manager `extraArgs` in `machineconfig.yaml.j2`:

   ```yaml
   feature-gates: HPAScaleToZero=true
   ```

4. Bump NFS nconnect from 8 to 16 in the `/etc/nfsmount.conf` file injection.
5. Add `install.wipe: false` to `machineconfig.yaml.j2` under `machine.install`.
6. Add `sysctl.kernel.kexec_load_disabled=1` to `schematic.yaml` under `customization.extraKernelArgs`.
7. Add `rbac: true` to `machineconfig.yaml.j2` under `machine.features`.

## Verification

- `just talos render-config k8s-cp0` — verify rendered config includes all new settings
- `just talos apply-node k8s-cp0` — apply config (etcd compaction requires reboot)
- After reboot: `talosctl etcd alarm list` — confirm no compaction alarms
- Monitor etcd disk: `etcd_mvcc_db_total_size_in_bytes` metric over days
- Verify install.wipe: re-running `apply-config` should NOT trigger disk wipe
- Verify kexec: `cat /proc/sys/kernel/kexec_load_disabled` should return 1

## Related

- relates_to [[talos-cluster]]
- relates_to [[drop-minijinja-templating]]

## Implementation — 2025-05-24

All 7 consensus-driven settings adopted and verified live on k8s-cp0.

### Changes committed

- `kubernetes/talos/machineconfig.yaml.j2`: etcd auto-compaction, kubelet imageGC, HPAScaleToZero (api-server + controller-manager), nconnect=16, install.wipe=false, rbac=true
- `kubernetes/talos/schematic.yaml`: extraKernelArgs sysctl.kernel.kexec_load_disabled=1

### Verification results

| # | Setting | Live status |
|---|---------|-------------|
| 1 | etcd auto-compaction (periodic / 1h) | ✅ active |
| 2 | kubelet imageGC 70/50 | ✅ active |
| 3 | HPAScaleToZero (api-server + controller-manager) | ✅ active |
| 4 | NFS nconnect=16 | ✅ active |
| 5 | install.wipe=false | ✅ in config (takes effect on next upgrade/install) |
| 6 | kexec_load_disabled=1 | ✅ /proc/sys/kernel/kexec_load_disabled = 1 |
| 7 | rbac=true | ✅ talosctl version shows RBAC: Enabled |

Applied via `just talos apply-node k8s-cp0` — node rebooted and came back healthy.
