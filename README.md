# Home Infrastructure & Kubernetes Cluster

This is a mono repository for my home infrastructure and Kubernetes cluster. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like Talos Linux, Kubernetes, Flux, Helmfile, Just, mise, Renovate, and Terraform.

Agent note: this README remains human-facing. Tooling and AI assistants should use the repository guidance files as the operational guide, starting at [CLAUDE.md](CLAUDE.md) and then following any more specific `CLAUDE.md` files in subdirectories.

## 🏠 Hardware Infrastructure

The cluster runs on a single bare-metal Talos node. A second machine handles file-level storage (NAS) and still hosts the OpenMediaVault VM under Proxmox; the Phase 10 bare-metal OMV retirement of that hypervisor layer is a planned post-cutover follow-up.

| Device                              | Quantity | CPU                       | OS Disk            | Data Disk                    | RAM  | OS                | Function                                  |
|-------------------------------------|----------|---------------------------|--------------------|------------------------------|------|-------------------|-------------------------------------------|
| HP ProDesk 600 G6 Desktop Mini      | 1        | Intel i7-10700T @ 2.0 GHz | NVMe (PC801)       | NVMe (PC711)                 | 64GB | Talos Linux       | Single-node Kubernetes control plane + workloads |
| Lenovo M93p tiny USFF               | 1        | Intel i5-4570T @ 2.90GHz  | 512GB SSD          | USB3 DAS 16TB EXT4 (host)    | 16GB | Debian 13 + Proxmox | NAS host; OpenMediaVault VM (transitional) |

The Lenovo M93p will become a bare-metal OpenMediaVault host in Phase 10 (post-Talos-cutover follow-up); the current Proxmox + OMV VM model is intentionally temporary.

## 🔄 GitOps Workflow

### Flux

The cluster runs Flux through the [Flux Operator](https://fluxcd.control-plane.io/) pattern: a single `FluxInstance` CR declares the controllers, GitRepository, and root Kustomization. There is no classic `flux bootstrap` step.

- The `FluxInstance` resource points at `kubernetes/flux/cluster/`, which holds a single root `cluster-apps` Kustomization (the earlier `cluster-vars` split with `kubernetes/flux/vars/` substitution was retired in Phase 6.7 for bjw-s parity).
- `cluster-apps` recursively walks `kubernetes/apps/` and applies every `ks.yaml`, with a kustomize patch that injects the shared HelmRelease defaults (`install`, `rollback`, `timeout`, `upgrade`) into every HR.
- Each app folder generally contains a `ks.yaml`, the actual manifests under `app/`, and optionally extra directories such as `config/`, `certificate/`, or `netpols/`.

The full bootstrap procedure is described in [docs/migration/05-flux-operator.md](docs/migration/05-flux-operator.md) and triggered by `just cluster-bootstrap cluster`.

### Renovate

Renovate watches the entire repository for dependency updates. When updates are found, a PR is automatically created. When PRs are merged, Flux applies the changes to the cluster. The root config lives in `.renovaterc.json5`, with topic-scoped fragments under `.renovate/`.

## 📁 Repository Structure

```text
📁 kubernetes
├── 📁 apps         # applications grouped by namespace
├── 📁 bootstrap    # Talos + Kubernetes platform bootstrap chain (helmfile + resources.yaml.j2)
├── 📁 components   # reusable Kustomize components (volsync, flux-alerts)
├── 📁 flux         # FluxInstance root Kustomization (`flux/cluster/`) reconciled by Flux Operator
├── 📁 talos        # Talos machine configs, schematic, node value templates
└── 📁 volsync      # operational helpers for the backup plane
📁 provision
├── 📁 cloudflare       # Cloudflare Terraform
├── 📁 ovh              # OVH Cloud Project Storage Terraform
├── 📁 openmediavault   # OMV recipes (Phase 10 Ansible reserved, post-cutover)
└── 📁 openwrt          # OpenWrt maintenance recipes
```

## 🔧 Application Deployment Strategy

I use official Helm charts whenever possible for applications. When official charts are not available, I use the **[bjw-s Helm Chart ecosystem](https://bjw-s-labs.github.io/helm-charts/docs)** to ensure consistent deployment patterns.

**[bjw-s Common Library](https://bjw-s-labs.github.io/helm-charts/docs/common-library/)**: Helm 3 library chart providing reusable templates for common Kubernetes resources.

**[bjw-s App Template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)**: Companion chart that enables deployment of any application using the Common Library.

## 🛠️ Core Components

### Operating System & Cluster

- **[Talos Linux](https://www.talos.dev/)**: Immutable, API-driven Linux distribution for Kubernetes; the cluster control plane and kubelet run on the HP node directly, with no general-purpose SSH access.
- **[Cilium](https://github.com/cilium/cilium)**: CNI, kube-proxy replacement, eBPF datapath, L2 announcement, and LB-IPAM (single source of truth for LoadBalancer IPs)
- **[Flux Operator + FluxInstance](https://fluxcd.control-plane.io/)**: Declarative install and lifecycle for the Flux controllers

### Networking & Security

- **[cert-manager](https://github.com/cert-manager/cert-manager)**: SSL certificates for services
- **[cloudflared](https://github.com/cloudflare/cloudflared)**: Cloudflare Tunnel for public ingress
- **[Envoy Gateway](https://github.com/envoyproxy/gateway)**: Gateway API ingress (external + internal)
- **[k8s-gateway](https://github.com/k8s-gateway/k8s_gateway)**: Split-DNS bridge from the LAN into Gateway API routes

### Ingress Model

The cluster uses a dual-Gateway Envoy model:

- `envoy-external`: public-facing Gateway API entrypoint behind Cloudflare Tunnel (ClusterIP-only Service inside the cluster)
- `envoy-internal`: internal Gateway API entrypoint exposed on a Cilium L2-announced VIP for direct LAN access

Public DNS and public traffic stay on the external path:

- Cloudflare Tunnel forwards `${PUBLIC_DOMAIN}` and `*.${PUBLIC_DOMAIN}` to `envoy-external`
- ExternalDNS manages public DNS records for externally published routes

Internal clients use split DNS instead of the tunnel path:

- `k8s-gateway` listens on its own Cilium L2-announced LAN VIP and watches HTTPRoutes attached to `envoy-internal`
- the home router DNS conditionally forwards `${PUBLIC_DOMAIN}` lookups to `k8s-gateway`
- internal clients therefore resolve app hostnames to the `envoy-internal` VIP and reach services directly on the LAN

Most user-facing HTTPRoutes attach to both `envoy-external` and `envoy-internal`.

See [docs/networking-readme.md](docs/networking-readme.md) for the current routing and split-DNS model.

### DNS & External Integration

- **[external-dns](https://github.com/kubernetes-sigs/external-dns)**: Automatic DNS record synchronization
- **[external-secrets](https://github.com/external-secrets/external-secrets)**: Secrets management using [1Password Connect](https://github.com/1Password/connect)

### Storage & Backup

- **[democratic-csi](https://github.com/democratic-csi/democratic-csi)**: CSI driver supporting local-hostpath, NFS, iSCSI and ZFS storage backends
- **[volsync](https://github.com/perfectra1n/volsync)**: PVC backup and recovery using Kopia to OVH Cloud Project Storage (S3-compatible). Always-on `ReplicationDestination` + `dataSourceRef` populates every PVC from its bootstrap snapshot on first apply.
- **[resticprofile](https://github.com/creativeprojects/resticprofile)** + **[Backrest](https://github.com/garethgeorge/backrest)**: File-level backup of the shared NAS tree to the same OVH bucket; Backrest is the snapshot browser

### Configuration Management

- **[mise](https://mise.jdx.dev/)**: Pinned versions for `talosctl`, `kubectl`, `helm`, `helmfile`, `flux2`, `just`, `minijinja`, `1password-cli`, `yq`, `jq`, `gum`, `pre-commit`, and the rest of the CLI surface
- **[Just](https://github.com/casey/just)**: Recipe runner; the root `.justfile` imports per-area `mod.just` modules (`k8s`, `cluster-bootstrap`, `talos`, `volsync`, `omv`, `cloudflare`, `ovh`, `openwrt`)
- **[minijinja-cli](https://github.com/mitsuhiko/minijinja)** + `op inject`: Templated bootstrap-time resources fed from 1Password (Talos `machineconfig`, the 1Password Connect bootstrap Secrets)

## ☁️ Cloud Provider: Cloudflare

All Cloudflare resources are managed using Terraform with the Cloudflare provider. Configuration files are located in the `provision/cloudflare` directory.

### Cloudflare Resources

- **DNS records**: For both cluster resources and custom domain email settings
- **Cloudflare Access**: Zero-trust network access
- **Cloudflare Firewall**: Security rules and protection
- **R2 Bucket**: Storage for homepage downloadable files
- **Cloudflare Tunnel**: Publishes cluster resources securely
- **Cloudflare Workers**
  - Email MTA-STS policy
- **Zone Settings**: Domain configuration and optimization

## 🔐 Secrets Management

The cluster uses a 1Password-centric model for secrets management; the earlier SOPS layer was fully retired in Phase 6.7 for bjw-s parity:

- **Bootstrap-time secrets**: Two 1Password Connect Secrets (`onepassword-connect-credentials-secret` and `onepassword-connect-vault-secret`) are rendered by `minijinja-cli` + `op inject` during `just cluster-bootstrap cluster`. The Talos `machineconfig` is templated through the same `op inject` flow.
- **Application secrets**: Every runtime secret is delivered through External Secrets against the shared `onepassword-connect` `ClusterSecretStore`. Multi-line config-as-secret content (for example the Homepage dashboard config) is stored as multi-line 1Password text fields and rendered via ESO `template.data`.

No SOPS-encrypted secret files exist in the repository: there is no `.sops.yaml`, no `cluster-secrets.sops.yaml`, no per-app `secret.sops.yaml`, and `sops` is not pinned in `.mise.toml`. This keeps the chicken-and-egg surface narrow to the two 1Password Connect bootstrap Secrets.

## 🚀 Deployment Dependencies

Applications are deployed with proper dependency management:

- `HelmRelease` resources can depend on other `HelmRelease` resources
- `Kustomization` resources can depend on other `Kustomization` resources
- In rare cases, applications can depend on both `HelmRelease` and `Kustomization` resources

This ensures applications are deployed in the correct order with all dependencies satisfied.
