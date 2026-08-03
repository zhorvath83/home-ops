---
title: talos-cluster
type: area_reference
permalink: home-ops/docs/areas/talos-cluster
area: talos-cluster
status: current
confidence: high
verified_at: '2026-08-03'
summary: Single-node Talos Linux control plane (`k8s-cp0`, cluster
  name `main`) with control-plane scheduling enabled. Machine config is a minijinja
  template rendered per-node and patched on top of a shared base, with all sensitive
  fields delivered as `op://HomeOps/talos/*` references resolved at apply time via
  `op inject`. Talos schematic is built on `factory.talos.dev` with i915 + intel-ucode
  system extensions plus one custom kernel arg (`sysctl.kernel.kexec_load_disabled=1`), no MEI.
  Kubernetes runs without kube-proxy
  (Cilium replacement) and without CoreDNS (Cilium DNS). All operational flows are
  wrapped by `just talos` recipes; the bootstrap chain is `just cluster-bootstrap cluster`.
verified_against:
- kubernetes/talos/machineconfig.yaml.j2
- kubernetes/talos/nodes/k8s-cp0.yaml.j2
- kubernetes/talos/schematic.yaml
- kubernetes/talos/mod.just
- kubernetes/talos/_resolve-controller.sh
- kubernetes/bootstrap/mod.just
- kubernetes/apps/system-upgrade/tuppr/ks.yaml
- kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml
- kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml
- .mise.toml
- .renovate/groups.json5
- .renovate/talosFactory.json5
drift_risk: The control-plane node name `k8s-cp0` and its IP are duplicated
  across the machineconfig (`certSANs`, `controlPlane.endpoint`), the resolver script
  `FALLBACK`, the `nodes/k8s-cp0.yaml.j2` filename, and OpenWRT DHCP reservations
  — renaming requires synchronized edits and a documented rename precedent (commits
  `8de1fa5cc`/`19d5c9fe5`). Disk pinning by model string (`PC801 NVMe SK hynix 1TB`
  for system, `PC711 NVMe SK hynix 1TB` for the local-hostpath UserVolume) breaks
  silently on hardware replacement with a different model. The Talos installer image
  is rebuilt every plan from `schematic.yaml` (live POST to factory.talos.dev) plus
  the `TALOS_VERSION` env var — pinning relies on the env var, not a stored schematic
  ID.
tags:
- area-reference
- talos-cluster
- kubernetes
- platform
---

# talos-cluster — current state

## Metadata (observation-form, schema validation)

- [area] talos-cluster
- [status] current
- [confidence] high
- [verified_at] 2026-08-03

## Summary

The cluster is a single Talos Linux control-plane node, `k8s-cp0`, cluster name `main`. Control-plane scheduling is enabled (`allowSchedulingOnControlPlanes: true`, machineconfig.yaml.j2:113) so workloads run on the same node. Kubernetes runs without kube-proxy (Cilium replaces it, :148-149) and without CoreDNS (Cilium provides DNS, :136-137). Talos hostDNS is enabled with `forwardKubeDNSToHost` and `resolveMemberNames` (:26-29); KubePrism listens on port 7445 (:30-31).

**The machineconfig does NOT use Flux substitution and — since the 2026-07 refactor — no longer uses env vars for network values either.** `kubernetes/talos/machineconfig.yaml.j2` is a minijinja template whose only interpolations are `{{ ENV.TALOS_VERSION }}`, `{{ ENV.TALOS_SCHEMATIC_ID }}`, `{{ ENV.KUBERNETES_VERSION }}` plus `IS_CONTROLPLANE` used as a `{% if %}` conditional. Every subnet and IP is a hardcoded literal: `192.168.1.0/24` (kubelet nodeIP :84, etcd advertisedSubnets :140), `192.168.1.11` (certSAN :128, endpoint :169), `10.244.0.0/16` (podSubnets :184), `10.245.0.0/16` (serviceSubnets :186). The `cluster-settings` ConfigMap variables (`${LAN_SUBNET}`, `${POD_CIDR}`, `${SVC_CIDR}`) exist for Flux-reconciled Kubernetes manifests only and never reach this file — so those values are duplicated between the two worlds and must be changed in both.

The machine configuration lives in `kubernetes/talos/machineconfig.yaml.j2` as a single shared base, per-node patches in `kubernetes/talos/nodes/<name>.yaml.j2`, and a factory schematic in `kubernetes/talos/schematic.yaml`. Every sensitive value (CA crts/keys, cluster id/secret/token, etcd CA, machine token, secretbox key, service-account key) is encoded as `op://HomeOps/talos/<FIELD>` and resolved by `op inject` at apply time, never persisted as plaintext in the repo. The Talos secrets bundle itself is generated once via `just talos gen-secrets` and stored as a single 1Password API Credential item (`HomeOps/talos`).

Operational flows are `just talos` recipes grouped into `image` (schematic, ISO download/burn), `setup` (gen-secrets, gen-talosconfig, bootstrap, get-kubeconfig), `config` (render-config, apply-node, apply-cluster, machine-controller, machine-image), `lifecycle` (reboot-node, shutdown-node, upgrade-node, upgrade-k8s, status, diag), and `recovery` (reset-node, reset-cluster). The control-plane node name is resolved at every recipe call via `kubernetes/talos/_resolve-controller.sh`, which reads the active talosconfig endpoint and falls back to `k8s-cp0` when no talosconfig is set yet (fresh clone, pre-bootstrap).

The whole reassembly path on already-installed hardware is the `just cluster-bootstrap cluster` chain in `kubernetes/bootstrap/mod.just` — it sequences talosconfig regen, per-node `talos apply-config`, `talosctl bootstrap`, kubeconfig fetch, namespace creation, bootstrap resources (1Password Connect Secrets via `op inject`), CRD pre-apply, and the helmfile-driven apps phase.

## Components

- [component] Single control-plane node — `k8s-cp0`, type `controlplane`, scheduling allowed (kubernetes/talos/nodes/k8s-cp0.yaml.j2 + machineconfig.yaml.j2:113)
- [component] Cluster identity — name `main`, endpoint literal `https://192.168.1.11:6443` (machineconfig.yaml.j2:169), cert SANs `127.0.0.1`, `192.168.1.11`, `k8s.lan` (:127-129). No substitution variable is involved.
- [component] Talos factory schematic — `schematic.yaml`: i915 (:16) + intel-ucode (:18) system extensions AND one custom kernel arg `sysctl.kernel.kexec_load_disabled=1` (:9-10); no MEI (kubernetes/talos/schematic.yaml)
- [component] Schematic ID regen — `just talos gen-schematic-id` POSTs schematic.yaml to factory.talos.dev and returns the .id; called transitively by `render-config`, `download-image`, `upgrade-node` (kubernetes/talos/mod.just:26-31)
- [component] Machine config base — `machineconfig.yaml.j2` minijinja template. Interpolations: `{{ ENV.TALOS_VERSION }}`, `{{ ENV.TALOS_SCHEMATIC_ID }}`, `{{ ENV.KUBERNETES_VERSION }}`; `IS_CONTROLPLANE` gates `{% if %}` blocks (:19-21, :109, :158, :161-163). Defaults set in kubernetes/talos/mod.just:259-261.
- [component] Per-node patch — `nodes/k8s-cp0.yaml.j2` contains ONLY: install-disk pin (`PC801 NVMe SK hynix 1TB`), EPHEMERAL VolumeConfig on the system disk, UserVolumeConfig `local-hostpath` on the PC711 NVMe at `/var/mnt/local-hostpath` (for democratic-csi), the hostname, and the `net0` LinkAliasConfig matched by MAC prefix `50:81:40:80:`
- [component] Shared network base (NOT per-node) — BondConfig wrapping `net0` into `bond0` (active-backup, MTU 1500, machineconfig.yaml.j2:190-200), DHCPv4Config on `bond0` with `clientIdentifier=mac` (:203-205), WatchdogTimerConfig on `/dev/watchdog0` with 5m timeout (:207-210)
- [component] Sensitive value indirection — every secret-bearing field references `op://HomeOps/talos/<FIELD>` and is resolved by `op inject` at apply time (machineconfig.yaml.j2:18,20,107,111-112,142-143,155,157,160,162,178,187,188)
- [component] Secrets-bundle 1Password item — `HomeOps/talos` (API Credential category, 14 fields: MACHINE_CA_CRT/KEY, MACHINE_TOKEN, CLUSTER_CA_CRT/KEY, CLUSTER_AGGREGATORCA_CRT/KEY, CLUSTER_SERVICEACCOUNT_KEY, CLUSTER_ETCD_CA_CRT/KEY, CLUSTER_ID, CLUSTER_SECRET, CLUSTER_TOKEN, CLUSTER_SECRETBOXENCRYPTIONSECRET) created by `just talos gen-secrets` (kubernetes/talos/mod.just:33-94)
- [component] talosconfig generator — `just talos gen-talosconfig` rebuilds the local talosconfig from the 1Password `HomeOps/talos` item via an inline secrets template + `op inject` + `talosctl gen config` (kubernetes/talos/mod.just:96-141)
- [component] Talos features — apidCheckExtKeyUsage (:23), diskQuotaSupport (:24), `rbac: true` (:25), hostDNS with kube-DNS forwarding + member-name resolution (:26-29), KubePrism on port 7445 (:30-31), and `kubernetesTalosAPIAccess` scoped to the `system-upgrade` namespace (:33-43) — the latter is what lets the Tuppr chart mount a Talos ServiceAccount
- [component] Kubelet config — `defaultRuntimeSeccompProfileEnabled: true`, `disableManifestsDirectory: true`, `maxPods: 150`, `serializeImagePulls: false`, image `ghcr.io/siderolabs/kubelet:{{ ENV.KUBERNETES_VERSION }}`, extraConfig `imageGCHighThresholdPercent: 70` / `imageGCLowThresholdPercent: 50` (:76-78), nodeIP validSubnets literal `192.168.1.0/24` (:84)
- [component] containerd customization — `enable_unprivileged_ports=true`, `enable_unprivileged_icmp=true`, `discard_unpacked_layers=false`, `device_ownership_from_security_context=true` (machineconfig.yaml.j2:49-54)
- [component] NFS client tuning — `/etc/nfsmount.conf` overwritten with `nfsvers=4.2`, `hard=True`, `nconnect=16`, `noatime=True`, 1 MiB rsize/wsize (machineconfig.yaml.j2:57-66)
- [component] Network/IO sysctls (:85-106) — inotify high (8192 instances, ~1M watches), TCP BBR congestion control, `fq` qdisc, large rmem/wmem buffers (64 MiB), TCP fastopen=3, MTU probing=1, increased neighbor table thresholds, `net.ipv4.ping_group_range=0 2147483647`, plus `tcp_notsent_lowat`, `tcp_slow_start_after_idle=0`, `tcp_window_scaling=1`, `tcp_rmem`, `tcp_wmem`, `sunrpc.tcp_max_slot_table_entries=128`, `sunrpc.tcp_slot_table_entries=128`, `user.max_user_namespaces=11255`, `vm.nr_hugepages=1024`
- [component] etcd — `advertisedSubnets: [192.168.1.0/24]` literal (:139-140), `auto-compaction-mode: periodic` + `auto-compaction-retention: "1h"` extraArgs (:145-146), metrics URL `http://0.0.0.0:2381` (:147)
- [component] Control-plane extraArgs — apiServer `enable-aggregator-routing: "true"` + `feature-gates: HPAScaleToZero=true` (:117-118); controllerManager and scheduler `bind-address: 0.0.0.0` + `feature-gates: HPAScaleToZero=true` (:134-135, :153)
- [component] kube-proxy disabled — `proxy.disabled: true` (Cilium replacement) (machineconfig.yaml.j2:148-149)
- [component] CoreDNS disabled — `coreDNS.disabled: true` (Cilium DNS) (machineconfig.yaml.j2:136-137)
- [component] Audit policy — `audit.k8s.io/v1` `Policy` with single `level: Metadata` rule (no request/response body) (machineconfig.yaml.j2:121-129)
- [component] PodSecurityPolicy disabled — `disablePodSecurityPolicy: true` (machineconfig.yaml.j2:130)
- [component] Network discovery — `discovery.enabled: true`, kubernetes registry disabled, service registry enabled (machineconfig.yaml.j2:171-177)
- [component] Pod/Service CIDRs — pod subnet literal `10.244.0.0/16` (:184), service subnet literal `10.245.0.0/16` (:186), DNS domain `cluster.local` (:182), CNI `none` (:181, Cilium installed out-of-band)
- [component] Controller-plane resolver — `kubernetes/talos/_resolve-controller.sh` reads the active talosconfig endpoint, falls back to `k8s-cp0` when missing
- [component] Version pins — `.mise.toml` holds `TALOS_VERSION = "v1.13.7"` (:9) and `KUBERNETES_VERSION = "v1.36.3"` (:11), both with inline `# renovate:` annotations (:8, :10). These are the env vars the machineconfig template and the Just recipes consume.
- [component] Bootstrap chain — `just cluster-bootstrap cluster` (kubernetes/bootstrap/mod.just) sequences talosconfig -> talos apply-config -> talosctl bootstrap -> kubeconfig (server temporarily rewritten to controller IP before Cilium L2 is up) -> wait -> namespaces -> bootstrap resources (`op inject` on `resources.yaml.j2` for the 1Password Connect Secrets) -> CRDs -> apps (helmfile) -> kubeconfig (final, Cilium L2 endpoint)

## Claims (verified against repo)

- [claim] "The cluster is a single control-plane node `k8s-cp0` with cluster name `main` and Kubernetes API endpoint `https://192.168.1.11:6443` (hardcoded literal, not a substitution variable)" (evidence: repo, ref: machineconfig.yaml.j2:169 + nodes/k8s-cp0.yaml.j2, verified: 2026-08-03)
- [claim] "Control-plane scheduling is enabled (`allowSchedulingOnControlPlanes: true`) — workloads run on the same node as etcd/api-server" (evidence: repo, ref: machineconfig.yaml.j2:113, verified: 2026-08-03)
- [claim] "kube-proxy and CoreDNS are both disabled in Talos (`proxy.disabled: true`, `coreDNS.disabled: true`); the cluster uses Cilium for both" (evidence: repo, ref: machineconfig.yaml.j2:136-137,148-149, verified: 2026-08-03)
- [claim] "Talos hostDNS is enabled with both `forwardKubeDNSToHost` and `resolveMemberNames`, and KubePrism listens on port 7445" (evidence: repo, ref: machineconfig.yaml.j2:26-31, verified: 2026-08-03)
- [claim] "The features block also enables `rbac: true` and `kubernetesTalosAPIAccess` restricted to the `system-upgrade` namespace — the latter exists because the Tuppr Helm chart needs a Talos ServiceAccount to drive upgrades" (evidence: repo, ref: machineconfig.yaml.j2:25,33-43, verified: 2026-08-03)
- [claim] "API server cert SANs include `127.0.0.1`, `192.168.1.11`, and `k8s.lan` — the `k8s.lan` name is kept as a forward-compatibility hook for a future LAN DNS record" (evidence: repo, ref: machineconfig.yaml.j2:127-129, verified: 2026-08-03)
- [claim] "The machineconfig template interpolates ONLY three env vars (`{{ ENV.TALOS_VERSION }}`, `{{ ENV.TALOS_SCHEMATIC_ID }}`, `{{ ENV.KUBERNETES_VERSION }}`) plus `IS_CONTROLPLANE` as a `{% if %}` conditional. Every subnet and IP value is a hardcoded literal — there is NO `${LAN_SUBNET}` / `${POD_CIDR}` / `${SVC_CIDR}` / `${CONTROLPLANE_IP}` anywhere in the Talos subtree" (evidence: repo, ref: machineconfig.yaml.j2:84,128,140,169,184,186 + mod.just:259-261, verified: 2026-08-03)
- [claim] "The Talos installer image is rebuilt from `schematic.yaml` (POSTed live to factory.talos.dev) and the `TALOS_VERSION` env var; the schematic declares i915 + intel-ucode system extensions, one custom kernel arg `sysctl.kernel.kexec_load_disabled=1`, and no MEI" (evidence: repo, ref: kubernetes/talos/schematic.yaml:9-10,16,18 + mod.just:26-31, verified: 2026-08-03)
- [claim] "All 14 Talos secrets (machine + cluster CAs and keys, machine + cluster + bootstrap tokens, cluster id, cluster secret, etcd CA, service-account key, secretbox encryption key) live in a single 1Password item `HomeOps/talos` (API Credential category) and are referenced from `machineconfig.yaml.j2` as `op://HomeOps/talos/<FIELD>`" (evidence: repo, ref: kubernetes/talos/mod.just:77-94 + machineconfig.yaml.j2:18,20,107,111-112,142-143,155,157,160,162,178,187,188, verified: 2026-08-03)
- [claim] "`just talos gen-secrets` refuses to overwrite an existing 1Password item — explicit `op item delete` is required first, with a destructive-action warning printed" (evidence: repo, ref: kubernetes/talos/mod.just:37-42, verified: 2026-08-03)
- [claim] "`just talos gen-talosconfig` reconstructs the Talos secrets bundle from 1Password using an inline jinja template and `op inject`, then runs `talosctl gen config` with `--force` against the rebuilt secrets file" (evidence: repo, ref: kubernetes/talos/mod.just:99-141, verified: 2026-08-03)
- [claim] "`just talos render-config` runs `op inject` on the base machineconfig template BEFORE `talosctl machineconfig patch` is applied — otherwise the `op://` placeholders would be rejected as malformed base64 in cert/key fields" (evidence: repo, ref: kubernetes/talos/mod.just:264-270, verified: 2026-08-03)
- [claim] "The single control-plane node uses two NVMe disks pinned by model string: `PC801 NVMe SK hynix 1TB` for Talos OS + EPHEMERAL, `PC711 NVMe SK hynix 1TB` for the `local-hostpath` UserVolume mounted at `/var/mnt/local-hostpath`" (evidence: repo, ref: nodes/k8s-cp0.yaml.j2, verified: 2026-08-03)
- [claim] "Networking: the on-board Intel I219-LM NIC (MAC prefix `50:81:40:80:`) is aliased to `net0` IN THE PER-NODE PATCH, but the bond, DHCP and watchdog config live in the SHARED BASE, not per-node: `bond0` single-member active-backup MTU 1500 (machineconfig.yaml.j2:190-200), DHCPv4Config on `bond0` with `clientIdentifier=mac` (:203-205), WatchdogTimerConfig `/dev/watchdog0` 5m (:207-210). Cilium and the L2 announcement policy target `bond0`, not the underlying NIC name" (evidence: repo, ref: nodes/k8s-cp0.yaml.j2 + machineconfig.yaml.j2:190-210, verified: 2026-08-03)
- [claim] "Pod CIDR is the literal `10.244.0.0/16`, service CIDR the literal `10.245.0.0/16`, DNS domain `cluster.local`, CNI is set to `none` (Cilium installed out-of-band during the bootstrap chain)" (evidence: repo, ref: machineconfig.yaml.j2:181-186, verified: 2026-08-03)
- [claim] "Audit logging is enabled at `Metadata` level only — request/response bodies are NOT recorded; the intent is forensic context with minimal overhead" (evidence: repo, ref: machineconfig.yaml.j2:121-129, verified: 2026-08-03)
- [claim] "Control-plane components carry extraArgs beyond the audit policy: apiServer `enable-aggregator-routing: \"true\"` and `feature-gates: HPAScaleToZero=true`; controllerManager and scheduler `bind-address: 0.0.0.0` plus the same feature gate — HPAScaleToZero is what makes the NFS-dependency zeroscaler HPA possible" (evidence: repo, ref: machineconfig.yaml.j2:117-118,134-135,153, verified: 2026-08-03)
- [claim] "The controller-plane node name is resolved at every recipe call by `kubernetes/talos/_resolve-controller.sh`, which reads the active `talosctl config info` endpoint and falls back to `k8s-cp0` when no talosconfig is set yet; the same script is shared with `kubernetes/bootstrap/mod.just`" (evidence: repo, ref: kubernetes/talos/_resolve-controller.sh, verified: 2026-08-03)
- [claim] "`just talos apply-node <node>` is interactive (`[confirm]` prompt) by default; bypass with `just --yes talos apply-node ...`. The reassembly chain in `kubernetes/bootstrap/mod.just` uses the `--yes` form to apply Talos config non-interactively to every node, treating a `certificate required` error as 'already configured' and continuing" (evidence: repo, ref: kubernetes/talos/mod.just:272-285 + kubernetes/bootstrap/mod.just:36-50, verified: 2026-08-03)
- [claim] "Lifecycle recipes (`reset-node`, `shutdown-node`, `upgrade-node`, `upgrade-k8s`) carry `[confirm]` prompts; `reset-node` wipes STATE + EPHEMERAL + u-local-hostpath labels and reboots to the installer" (evidence: repo, ref: kubernetes/talos/mod.just:299-309,322-330,344-362, verified: 2026-08-03)

## Drift Risk

- [drift] The control-plane node name `k8s-cp0` and its IP are duplicated across the machineconfig (`certSANs` :128, `controlPlane.endpoint` :169), the resolver script's `FALLBACK` value, the `nodes/k8s-cp0.yaml.j2` filename, and OpenWRT DHCP reservations. The resolver script header references rename precedents (commits `8de1fa5cc`, `19d5c9fe5`) — any future rename must keep all five locations in sync.
- [drift] **Network values are duplicated between two worlds with no shared source.** The Talos machineconfig hardcodes `192.168.1.0/24`, `10.244.0.0/16`, `10.245.0.0/16`, `192.168.1.11` as literals, while the same values live in the `cluster-settings` ConfigMap for Flux-reconciled manifests. Changing a subnet requires editing both, and nothing detects a mismatch. This replaced an earlier (mistakenly documented) belief that the template consumed those variables.
- [drift] Disk pinning by exact model string (`PC801 NVMe SK hynix 1TB`, `PC711 NVMe SK hynix 1TB`) breaks silently on hardware replacement with a different model. The local-hostpath UserVolume in particular is the storage that backs democratic-csi and therefore most app PVCs.
- [drift] The Talos installer image is rebuilt every time from a live POST to `factory.talos.dev` plus `TALOS_VERSION` — there is no stored schematic ID in the repo. If the factory's schematic-ID derivation ever changes for the same input, image URLs would drift. `just talos download-image` writes the resolved ISO out to `talos-<version>-<sid_prefix>.iso` for the burn flow only.
- [drift] LinkAlias matching depends on a 4-byte MAC prefix (`50:81:40:80:`) — HP OUI plus one product-family byte. If the on-board NIC is replaced with a different family, the alias does not match and `bond0` never comes up. There is no fallback selector.
- [drift] The i915 + intel-ucode extensions in the schematic are consumed by the Intel GPU Resource Driver (DRA/CDI). Plex accesses the iGPU via ResourceClaimTemplate (`components/gpu/`) — no hostPath mount or supplementalGroups needed. The DRA driver deploys as a privileged DaemonSet in kube-system (chart tag 0.11.0). MEI was removed (Comet Lake lacks GSC/HDCP hardware — unlike Meteor Lake).
- [drift] The talosconfig the operator's shell points at is rebuilt from 1Password via `gen-talosconfig` — if the operator runs `talosctl config ...` commands that mutate the config locally (e.g. add an extra endpoint) those edits are lost on the next regen.
- [drift] The `kubernetesTalosAPIAccess` feature grants the `system-upgrade` namespace Talos API access. It is a real privilege boundary: any workload that can create a ServiceAccount token in that namespace reaches the Talos API. It exists solely for Tuppr.

## Open Questions / Gaps

- [gap] No verification was run against the live Talos node or factory.talos.dev in this pass — claims are repo-evidence only. `just talos status` from a credentialed shell is the live-state validation path; `just talos diag` produces a node-side diagnostics dump.
- [gap] (Resolved 2026-08-03) Talos and Kubernetes versions ARE pinned in the repo: `.mise.toml:9` `TALOS_VERSION = "v1.13.7"` and `.mise.toml:11` `KUBERNETES_VERSION = "v1.36.3"`, both Renovate-tracked via inline annotations. They land in TWO different Renovate groups, not one: Talos (custom.talos-factory, `siderolabs/talos`, .renovate/groups.json5:42-48) and Kubernetes (docker, `/kubelet/`, groups.json5:33-40).
- [gap] The single-node-cluster assumption is hardcoded throughout (one `nodes/*.yaml.j2`, fixed CP IP literal, fixed endpoint, single bond on `net0`). Multi-node / BGP migration is no longer tracked as a roadmap item (L2 announcement is sufficient for single-node).
- [gap] No documented disaster-recovery procedure for the case where the 1Password `HomeOps/talos` item is lost — regenerating secrets effectively requires re-installing the cluster.
- [gap] Tuppr controller runtime behavior (how it derives the schematic ID at upgrade time) cannot be verified from this repo — the CRD and controller logic are chart-supplied. Treated as vendor behavior, not a repo fact.

## Relations

- relates_to [[external-secrets]]
- relates_to [[networking]]
- relates_to [[flux-gitops]]
- relates_to [[k8s-workloads]]
- part_of [[home-ops-platform]]

## Tuppr upgrade automation

- [component] Tuppr controller — GitOps-managed Talos OS and Kubernetes upgrade controller in `system-upgrade` namespace (kubernetes/apps/system-upgrade/tuppr/). Replaces manual `just talos upgrade-node` / `just talos upgrade-k8s` for steady-state upgrades. Just recipes remain as documented manual fallback. Deployed by two Kustomizations, `tuppr` then `tuppr-upgrades` (`dependsOn: tuppr`, `wait: false`), targetNamespace `system-upgrade` (tuppr/ks.yaml).
- [component] TalosUpgrade CR — `talos` resource; `spec.talos.version: "v1.13.7"` (Renovate `custom.talos-factory depName=siderolabs/talos`), `drain.enabled: false`, `policy.rebootMode: powercycle`, and ONE health check gating on VolSync `ReplicationSource` idleness. It has NO `placement` and NO `parallelism` field (kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml:1-21)
- [component] KubernetesUpgrade CR — `kubernetes` resource; `spec.kubernetes.version: "v1.36.3"` (Renovate `docker depName=ghcr.io/siderolabs/kubelet`) and the same VolSync ReplicationSource health check. It contains no talosctl image reference (kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml:1-16)
- [claim] "Steady-state Talos and Kubernetes upgrades are GitOps-driven via Tuppr TalosUpgrade and KubernetesUpgrade CRs; manual Just recipes (`upgrade-node`, `upgrade-k8s`) are documented as fallback only" (evidence: repo, ref: kubernetes/apps/system-upgrade/tuppr/ + kubernetes/talos/mod.just:346-362, verified: 2026-08-03)
- [claim] "Both upgrade CRs gate on exactly one health check — all VolSync `ReplicationSource` objects must have their `Synchronizing` condition False, i.e. no backup in flight — expressed as a CEL `expr` over `volsync.backube/v1alpha1` ReplicationSources. This is what prevents a reboot mid-backup; it is NOT a Flux Kustomization/HelmRelease readiness or cilium/cloudflare-tunnel gate" (evidence: repo, ref: talosupgrade.yaml:16-21 + kubernetesupgrade.yaml:11-16, verified: 2026-08-03)
- [claim] "The single-node accommodation in the TalosUpgrade CR is `drain.enabled: false` — on a one-node cluster there is nowhere to drain to. There is no `placement` field at all" (evidence: repo, ref: talosupgrade.yaml:12-13, verified: 2026-08-03)
- [claim] "Tuppr preserves the factory schematic automatically — the controller reads the node's running `machine.install.image` to determine the schematic ID, so the i915 + intel-ucode extensions are retained across upgrades" (evidence: tuppr docs — vendor behavior, NOT repo-verifiable, verified: 2026-05-23)
- [claim] "Talos and Kubernetes version pins are Renovate-tracked from `.mise.toml` via two different datasources and land in TWO SEPARATE Renovate groups: TALOS_VERSION uses `custom.talos-factory` (factory.talos.dev/versions, installer-image-filtered, .renovate/talosFactory.json5) and matches the Talos group (.renovate/groups.json5:42-48); KUBERNETES_VERSION uses `docker depName=ghcr.io/siderolabs/kubelet` and matches the Kubernetes group (groups.json5:33-40). The upgrade CRs carry the same annotations" (evidence: repo, ref: .mise.toml:8-11 + .renovate/talosFactory.json5 + .renovate/groups.json5:33-48 + upgrades/*.yaml, verified: 2026-08-03)

## Update 2026-08-03 — staleness re-verification

Full re-verification against the live repo as part of the `area-reference-staleness-audit`
roadmap item. Previous `verified_at` was 2026-05-22. Verdict on arrival: MAJOR-DRIFT
(12 wrong claims, 3 incomplete, 1 obsolete, 10 uncovered live facts).

The root cause is a single event: **the machineconfig template was refactored after 2026-05-22**
and the note was never re-read against it. Almost every wrong claim follows from that.

- [correction] The biggest one: the note described network values as substitution variables
  (`${LAN_SUBNET}`, `${POD_CIDR}`, `${SVC_CIDR}`, `${CONTROLPLANE_IP}`). None of those exist in the
  Talos subtree. All are hardcoded literals. Anyone trusting the note would have changed a
  ConfigMap and expected the node config to follow.
- [correction] The schematic HAS a custom kernel arg (`sysctl.kernel.kexec_load_disabled=1`); the
  note asserted the opposite in both summary and body.
- [correction] The Tuppr section was substantially fictional: the TalosUpgrade CR has no
  `placement: soft` and no `parallelism: 1`, and the health gate is a single VolSync
  `ReplicationSource` idleness check (do not reboot mid-backup), not Flux/cilium/cloudflare-tunnel
  readiness. The KubernetesUpgrade CR pins the Kubernetes version, not a talosctl image tag.
  A whole claim justifying `placement: soft` was reasoning about a field that is not there.
- [correction] `nconnect=16`, not 8. Kubelet gained imageGC thresholds. etcd gained periodic
  auto-compaction. The features block gained `rbac: true` and `kubernetesTalosAPIAccess`
  (system-upgrade namespace, required by Tuppr — and a real privilege boundary, now a drift entry).
  Nine new sysctls were added. apiServer/controllerManager/scheduler extraArgs
  (`HPAScaleToZero`, `enable-aggregator-routing`, `bind-address`) were entirely unmentioned.
- [correction] BondConfig / DHCPv4Config / WatchdogTimerConfig were attributed to the per-node
  patch; they live in the shared base. The per-node patch holds only disk pins, volumes, hostname
  and the `net0` LinkAlias.
- [correction] Every line reference in the note had drifted; all were re-derived from the current
  files.
- [resolved] The gap "versions are not pinned in the repo, likely .mise.toml, not inspected" is
  settled: they are pinned in `.mise.toml` and Renovate-tracked — but in TWO separate groups
  (Talos and Kubernetes), not one as the note claimed.
- [observation] All six `verified_against` paths still existed; six load-bearing paths were added
  (.mise.toml, the two Renovate fragments, the tuppr ks + both upgrade CRs).
