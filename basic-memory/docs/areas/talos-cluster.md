---
title: talos-cluster
type: area_reference
permalink: home-ops/docs/areas/talos-cluster
area: talos-cluster
status: current
confidence: high
verified_at: '2026-05-22'
summary: Single-node Talos Linux control plane (`k8s-cp0`, cluster
  name `main`) with control-plane scheduling enabled. Machine config is a minijinja
  template rendered per-node and patched on top of a shared base, with all sensitive
  fields delivered as `op://HomeOps/talos/*` references resolved at apply time via
  `op inject`. Talos schematic is built on `factory.talos.dev` with i915 + intel-ucode
  system extensions (no custom kernel args, no MEI). Kubernetes runs without kube-proxy
  (Cilium replacement) and without CoreDNS (Cilium DNS). All operational flows are
  wrapped by `just talos` recipes; the bootstrap chain is `just cluster-bootstrap cluster`.
verified_against:
- kubernetes/talos/machineconfig.yaml.j2
- kubernetes/talos/nodes/k8s-cp0.yaml.j2
- kubernetes/talos/schematic.yaml
- kubernetes/talos/mod.just
- kubernetes/talos/_resolve-controller.sh
- kubernetes/bootstrap/mod.just
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
- [verified_at] 2026-05-19

## Summary

The cluster is a single Talos Linux control-plane node, `k8s-cp0`, cluster name `main`. Control-plane scheduling is enabled (`allowSchedulingOnControlPlanes: true`) so workloads run on the same node. Kubernetes runs without kube-proxy (Cilium replaces it) and without CoreDNS (Cilium provides DNS). Cluster-wide substitution variables (`${LAN_SUBNET}`, `${POD_CIDR}`, `${SVC_CIDR}`, etc.) are defined in the `cluster-settings` ConfigMap and injected via Flux `postBuild.substituteFrom`; the Talos machineconfig template uses minijinja env vars rather than Flux substitution; Talos hostDNS is enabled with `forwardKubeDNSToHost` and `resolveMemberNames`. KubePrism listens on port 7445 for the kubelet/etcd loopback API.

The machine configuration lives in `kubernetes/talos/machineconfig.yaml.j2` as a single shared base (minijinja template), per-node patches in `kubernetes/talos/nodes/<name>.yaml.j2`, and a factory schematic in `kubernetes/talos/schematic.yaml`. Every sensitive value (CA crts/keys, cluster id/secret/token, etcd CA, machine token, secretbox key, service-account key) is encoded as `op://HomeOps/talos/<FIELD>` and resolved by `op inject` at apply time, never persisted as plaintext in the repo. The Talos secrets bundle itself is generated once via `just talos gen-secrets` and stored as a single 1Password API Credential item (`HomeOps/talos`).

Operational flows are `just talos` recipes grouped into `image` (schematic, ISO download/burn), `setup` (gen-secrets, gen-talosconfig, bootstrap, get-kubeconfig), `config` (render-config, apply-node, apply-cluster, machine-controller, machine-image), `lifecycle` (reboot-node, shutdown-node, upgrade-node, upgrade-k8s, status, diag), and `recovery` (reset-node, reset-cluster). The control-plane node name is resolved at every recipe call via `kubernetes/talos/_resolve-controller.sh`, which reads the active talosconfig endpoint and falls back to `k8s-cp0` when no talosconfig is set yet (fresh clone, pre-bootstrap).

The whole reassembly path on already-installed hardware is the `just cluster-bootstrap cluster` chain in `kubernetes/bootstrap/mod.just` — it sequences talosconfig regen, per-node `talos apply-config`, `talosctl bootstrap`, kubeconfig fetch, namespace creation, bootstrap resources (1Password Connect Secrets via `op inject`), CRD pre-apply, and the helmfile-driven apps phase.

## Components

- [component] Single control-plane node — `k8s-cp0`, type `controlplane`, scheduling allowed (kubernetes/talos/nodes/k8s-cp0.yaml.j2:5-6 + machineconfig.yaml.j2:98-99)
- [component] Cluster identity — name `main`, endpoint `https://${CONTROLPLANE_IP}:6443`, cert SANs include `127.0.0.1`, `${CONTROLPLANE_IP}`, `k8s.lan` (machineconfig.yaml.j2:110-114,149-151)
- [component] Talos factory schematic — `schematic.yaml` with i915 + intel-ucode system extensions (no custom kernel args, no MEI) (kubernetes/talos/schematic.yaml)
- [component] Schematic ID regen — `just talos gen-schematic-id` POSTs schematic.yaml to factory.talos.dev and returns the .id; called transitively by `render-config`, `download-image`, `upgrade-node` (kubernetes/talos/mod.just:26-31)
- [component] Machine config base — `machineconfig.yaml.j2` minijinja template, rendered with `TALOS_VERSION`, `TALOS_SCHEMATIC_ID`, `KUBERNETES_VERSION`, `IS_CONTROLPLANE` env vars (kubernetes/talos/machineconfig.yaml.j2)
- [component] Per-node patch — `nodes/k8s-cp0.yaml.j2` pins install disk (`PC801 NVMe SK hynix 1TB`), EPHEMERAL on system disk, UserVolume `local-hostpath` on PC711 NVMe at `/var/mnt/local-hostpath` (for democratic-csi local-hostpath driver), hostname `k8s-cp0`, LinkAlias `net0` matched by MAC prefix `50:81:40:80:`, BondConfig wrapping `net0` into `bond0` (active-backup, MTU 1500), DHCPv4Config on `bond0` (clientIdentifier=mac), WatchdogTimerConfig on `/dev/watchdog0` with 5m timeout (nodes/k8s-cp0.yaml.j2 + machineconfig.yaml.j2:171-191)
- [component] Sensitive value indirection — every secret-bearing field in the machineconfig references `op://HomeOps/talos/<FIELD>` and is resolved by `op inject` at apply time (machineconfig.yaml.j2:18-20,92,96-97,125-126,136,141-143,168-169)
- [component] Secrets-bundle 1Password item — `HomeOps/talos` (API Credential category, 14 fields: MACHINE_CA_CRT/KEY, MACHINE_TOKEN, CLUSTER_CA_CRT/KEY, CLUSTER_AGGREGATORCA_CRT/KEY, CLUSTER_SERVICEACCOUNT_KEY, CLUSTER_ETCD_CA_CRT/KEY, CLUSTER_ID, CLUSTER_SECRET, CLUSTER_TOKEN, CLUSTER_SECRETBOXENCRYPTIONSECRET) created by `just talos gen-secrets` (kubernetes/talos/mod.just:33-94)
- [component] talosconfig generator — `just talos gen-talosconfig` rebuilds the local talosconfig from the 1Password `HomeOps/talos` item via an inline secrets template + `op inject` + `talosctl gen config` (kubernetes/talos/mod.just:96-141)
- [component] Talos features — apidCheckExtKeyUsage, diskQuotaSupport, hostDNS with kube-DNS forwarding + member-name resolution, KubePrism on port 7445 (machineconfig.yaml.j2:22-31)
- [component] Kubelet config — `defaultRuntimeSeccompProfileEnabled: true`, `disableManifestsDirectory: true`, `maxPods: 150`, `serializeImagePulls: false`, image `ghcr.io/siderolabs/kubelet:<KUBERNETES_VERSION>`, nodeIP validSubnets `${LAN_SUBNET}` (machineconfig.yaml.j2:60-69)
- [component] containerd customization — `enable_unprivileged_ports=true`, `enable_unprivileged_icmp=true`, `discard_unpacked_layers=false`, `device_ownership_from_security_context=true` (machineconfig.yaml.j2:32-43)
- [component] NFS client tuning — `/etc/nfsmount.conf` overwritten with `nfsvers=4.2`, `hard=True`, `nconnect=8`, `noatime=True`, 1 MiB rsize/wsize (machineconfig.yaml.j2:44-54)
- [component] Network/IO sysctls — inotify high (8192 instances, ~1M watches), TCP BBR congestion control, `fq` qdisc, large rmem/wmem buffers (64 MiB), TCP fastopen=3, MTU probing=1, increased neighbor table thresholds, sunrpc.tcp_max_slot_table_entries=128, `net.ipv4.ping_group_range=0 2147483647` (machineconfig.yaml.j2:70-91)
- [component] etcd — `advertisedSubnets: [${LAN_SUBNET}]`, metrics URL `http://0.0.0.0:2381` (machineconfig.yaml.j2:121-128)
- [component] kube-proxy disabled — `proxy.disabled: true` (Cilium replacement) (machineconfig.yaml.j2:129-131)
- [component] CoreDNS disabled — `coreDNS.disabled: true` (Cilium DNS) (machineconfig.yaml.j2:119-120)
- [component] Audit policy — `audit.k8s.io/v1` `Policy` with single `level: Metadata` rule (no request/response body) (machineconfig.yaml.j2:104-109)
- [component] PodSecurityPolicy disabled — `disablePodSecurityPolicy: true` (machineconfig.yaml.j2:114)
- [component] Network discovery — `discovery.enabled: true`, kubernetes registry disabled, service registry enabled (machineconfig.yaml.j2:152-158)
- [component] Pod/Service CIDRs — pod subnet `${POD_CIDR}`, service subnet `${SVC_CIDR}`, DNS domain `cluster.local`, CNI `none` (Cilium installed out-of-band) (machineconfig.yaml.j2:160-167)
- [component] Controller-plane resolver — `kubernetes/talos/_resolve-controller.sh` reads the active talosconfig endpoint, falls back to `k8s-cp0` when missing (kubernetes/talos/_resolve-controller.sh)
- [component] Bootstrap chain — `just cluster-bootstrap cluster` (kubernetes/bootstrap/mod.just) sequences talosconfig → talos apply-config → talosctl bootstrap → kubeconfig (server temporarily rewritten to controller IP before Cilium L2 is up) → wait → namespaces → bootstrap resources (`op inject` on `resources.yaml.j2` for the 1Password Connect Secrets) → CRDs → apps (helmfile) → kubeconfig (final, Cilium L2 endpoint)

## Claims (verified against repo)

- [claim] "The cluster is a single control-plane node `k8s-cp0` with cluster name `main` and Kubernetes API endpoint `https://${CONTROLPLANE_IP}:6443`" (evidence: repo, ref: machineconfig.yaml.j2:110-114,149-151 + nodes/k8s-cp0.yaml.j2:5-6, verified: 2026-05-19)
- [claim] "Control-plane scheduling is enabled (`allowSchedulingOnControlPlanes: true`) — workloads run on the same node as etcd/api-server" (evidence: repo, ref: machineconfig.yaml.j2:98, verified: 2026-05-19)
- [claim] "kube-proxy and CoreDNS are both disabled in Talos (`proxy.disabled: true`, `coreDNS.disabled: true`); the cluster uses Cilium for both" (evidence: repo, ref: machineconfig.yaml.j2:119-120,129-131, verified: 2026-05-19)
- [claim] "Talos hostDNS is enabled with both `forwardKubeDNSToHost` and `resolveMemberNames`, and KubePrism listens on port 7445" (evidence: repo, ref: machineconfig.yaml.j2:24-31, verified: 2026-05-19)
- [claim] "API server cert SANs include `127.0.0.1`, `${CONTROLPLANE_IP}`, and `k8s.lan` — the `k8s.lan` name is kept as a forward-compatibility hook for a future LAN DNS record" (evidence: repo, ref: machineconfig.yaml.j2:110-114, verified: 2026-05-19)
- [claim] "The Talos installer image is rebuilt from `schematic.yaml` (POSTed live to factory.talos.dev) and the `TALOS_VERSION` env var; the schematic includes i915 + intel-ucode system extensions with no custom kernel args and no MEI (Comet Lake does not have GSC/HDCP hardware)" (evidence: repo, ref: kubernetes/talos/schematic.yaml + mod.just:26-31, verified: 2026-05-23)
- [claim] "All 14 Talos secrets (machine + cluster CAs and keys, machine + cluster + bootstrap tokens, cluster id, cluster secret, etcd CA, service-account key, secretbox encryption key) live in a single 1Password item `HomeOps/talos` (API Credential category) and are referenced from `machineconfig.yaml.j2` as `op://HomeOps/talos/<FIELD>`" (evidence: repo, ref: kubernetes/talos/mod.just:77-94 + machineconfig.yaml.j2:18-20,92,96-97,125-126,136,141-143,168-169, verified: 2026-05-19)
- [claim] "`just talos gen-secrets` refuses to overwrite an existing 1Password item — explicit `op item delete` is required first, with a destructive-action warning printed" (evidence: repo, ref: kubernetes/talos/mod.just:37-42, verified: 2026-05-19)
- [claim] "`just talos gen-talosconfig` reconstructs the Talos secrets bundle from 1Password using an inline jinja template and `op inject`, then runs `talosctl gen config` with `--force` against the rebuilt secrets file" (evidence: repo, ref: kubernetes/talos/mod.just:99-141, verified: 2026-05-19)
- [claim] "`just talos render-config` runs `op inject` on the base machineconfig template BEFORE `talosctl machineconfig patch` is applied — otherwise the `op://` placeholders would be rejected as malformed base64 in cert/key fields" (evidence: repo, ref: kubernetes/talos/mod.just:264-270, verified: 2026-05-19)
- [claim] "The single control-plane node uses two NVMe disks pinned by model string: `PC801 NVMe SK hynix 1TB` for Talos OS + EPHEMERAL, `PC711 NVMe SK hynix 1TB` for the `local-hostpath` UserVolume mounted at `/var/mnt/local-hostpath`" (evidence: repo, ref: nodes/k8s-cp0.yaml.j2:7-32, verified: 2026-05-19)
- [claim] "Networking: on-board Intel I219-LM NIC (MAC prefix `50:81:40:80:`) is given the alias `net0` and wrapped in a single-member active-backup bond `bond0` (MTU 1500); DHCPv4 runs on `bond0` with `clientIdentifier=mac`. Cilium and the L2 announcement policy target `bond0`, not the underlying NIC name" (evidence: repo, ref: nodes/k8s-cp0.yaml.j2:38-49 + machineconfig.yaml.j2:171-186, verified: 2026-05-19)
- [claim] "Pod CIDR is `${POD_CIDR}`, service CIDR is `${SVC_CIDR}`, DNS domain `cluster.local`, CNI is set to `none` (Cilium installed out-of-band during the bootstrap chain)" (evidence: repo, ref: machineconfig.yaml.j2:160-167, verified: 2026-05-19)
- [claim] "Audit logging is enabled at `Metadata` level only — request/response bodies are NOT recorded; the intent is forensic context with minimal overhead" (evidence: repo, ref: machineconfig.yaml.j2:104-109, verified: 2026-05-19)
- [claim] "The controller-plane node name is resolved at every recipe call by `kubernetes/talos/_resolve-controller.sh`, which reads the active `talosctl config info` endpoint and falls back to `k8s-cp0` when no talosconfig is set yet; the same script is shared with `kubernetes/bootstrap/mod.just`" (evidence: repo, ref: kubernetes/talos/_resolve-controller.sh, verified: 2026-05-19)
- [claim] "`just talos apply-node <node>` is interactive (`[confirm]` prompt) by default; bypass with `just --yes talos apply-node ...`. The reassembly chain in `kubernetes/bootstrap/mod.just` uses the `--yes` form to apply Talos config non-interactively to every node, treating a `certificate required` error as 'already configured' and continuing" (evidence: repo, ref: kubernetes/talos/mod.just:272-285 + kubernetes/bootstrap/mod.just:36-50, verified: 2026-05-19)
- [claim] "Lifecycle recipes (`reset-node`, `shutdown-node`, `upgrade-node`, `upgrade-k8s`) carry `[confirm]` prompts; `reset-node` wipes STATE + EPHEMERAL + u-local-hostpath labels and reboots to the installer" (evidence: repo, ref: kubernetes/talos/mod.just:299-309,322-330,344-362, verified: 2026-05-19)

## Drift Risk

- [drift] The control-plane node name `k8s-cp0` and its IP are duplicated across the machineconfig (`certSANs`, `controlPlane.endpoint`), the resolver script's `FALLBACK` value, the `nodes/k8s-cp0.yaml.j2` filename, and OpenWRT DHCP reservations. The resolver script's header explicitly references rename precedents (commits `8de1fa5cc`, `19d5c9fe5`) — any future rename must keep all five locations in sync.
- [drift] Disk pinning by exact model string (`PC801 NVMe SK hynix 1TB`, `PC711 NVMe SK hynix 1TB`) breaks silently on hardware replacement with a different model. The local-hostpath UserVolume in particular is the storage that backs democratic-csi and therefore most app PVCs.
- [drift] The Talos installer image is rebuilt every time from a live POST to `factory.talos.dev` plus `TALOS_VERSION` — there is no stored schematic ID in the repo. If the factory's schematic-ID derivation ever changes for the same input, image URLs would drift. `just talos download-image` writes the resolved ISO out to `talos-<version>-<sid_prefix>.iso` for the burn flow only.
- [drift] LinkAlias matching depends on a 4-byte MAC prefix (`50:81:40:80:`) — HP OUI plus one product-family byte. If the on-board NIC is replaced with a different family, the alias does not match and `bond0` never comes up. There is no fallback selector.
- [drift] The i915 + intel-ucode extensions in the schematic are consumed by the Intel GPU Resource Driver (DRA/CDI). Plex accesses the iGPU via ResourceClaimTemplate (`components/gpu/`) — no hostPath mount or supplementalGroups needed. The DRA driver deploys as a privileged DaemonSet in kube-system. MEI was removed (Comet Lake lacks GSC/HDCP hardware — unlike Meteor Lake).
- [drift] The talosconfig the operator's shell points at is rebuilt from 1Password via `gen-talosconfig` — if the operator runs `talosctl config ...` commands that mutate the config locally (e.g. add an extra endpoint) those edits are lost on the next regen.

## Open Questions / Gaps

- [gap] No verification was run against the live Talos node or factory.talos.dev in this pass — claims are repo-evidence only. `just talos status` from a credentialed shell is the live-state validation path; `just talos diag` produces a node-side diagnostics dump.
- [gap] The exact Talos and Kubernetes versions in use are not pinned in the repo — they come from `TALOS_VERSION` and `KUBERNETES_VERSION` env vars (likely set by `.mise.toml`, not inspected here). Cross-checking that those vars are Renovate-tracked is left to the versions-renovate area.
- [gap] The single-node-cluster assumption is hardcoded throughout (one `nodes/*.yaml.j2`, fixed CP IP, fixed endpoint, single bond on `net0`). Multi-node / BGP migration is no longer tracked as a roadmap item (L2 announcement is sufficient for single-node).
- [gap] No documented disaster-recovery procedure for the case where the 1Password `HomeOps/talos` item is lost — regenerating secrets effectively requires re-installing the cluster.

## Relations

- relates_to [[external-secrets]]
- relates_to [[networking]]
- relates_to [[flux-gitops]]
- relates_to [[k8s-workloads]]
- part_of [[home-ops-platform]]

## Tuppr upgrade automation

- [component] Tuppr controller — GitOps-managed Talos OS and Kubernetes upgrade controller in `system-upgrade` namespace (kubernetes/apps/system-upgrade/tuppr/). Replaces manual `just talos upgrade-node` / `just talos upgrade-k8s` for steady-state upgrades. Just recipes remain as documented manual fallback.
- [component] TalosUpgrade CR — `talos` resource in `system-upgrade` namespace; single-node config with `placement: soft`, `rebootMode: powercycle`, `parallelism: 1`, drain settings, and health checks gating on Flux Kustomization + HelmRelease readiness + cilium + cloudflare-tunnel (kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml)
- [component] KubernetesUpgrade CR — `kubernetes` resource in `system-upgrade` namespace; pins talosctl image tag to TALOS_VERSION, health checks identical to TalosUpgrade (kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml)
- [claim] "Steady-state Talos and Kubernetes upgrades are GitOps-driven via Tuppr TalosUpgrade and KubernetesUpgrade CRs; manual Just recipes (`upgrade-node`, `upgrade-k8s`) are documented as fallback only" (evidence: repo, ref: kubernetes/apps/system-upgrade/tuppr/ + kubernetes/talos/mod.just:346-362, verified: 2026-05-23)
- [claim] "Tuppr uses `placement: soft` because `hard` would make the upgrade job unschedulable on a single-node cluster (only node cannot avoid itself)" (evidence: tuppr CRD enum semantics, ref: kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml, verified: 2026-05-23)
- [claim] "Tuppr preserves the factory schematic automatically — the controller reads the node's running `machine.install.image` to determine the schematic ID, so i915 + intel-ucode + mei extensions are retained across upgrades" (evidence: tuppr docs, verified: 2026-05-23)

- [claim] "Talos and Kubernetes version pins are tracked by Renovate via custom datasources: TALOS_VERSION uses custom.talos-factory (factory.talos.dev/versions API, only lists versions with available installer images); KUBERNETES_VERSION uses docker depName=ghcr.io/siderolabs/kubelet (Sidero Labs kubelet image tags, aligned with Talos compatibility); both are grouped in the Talos Renovate group with the TalosUpgrade and KubernetesUpgrade CR annotations" (evidence: repo, ref: .mise.toml + .renovate/groups.json5 + kubernetes/apps/system-upgrade/tuppr/upgrades/*.yaml, verified: 2026-05-23)
