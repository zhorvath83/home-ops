# Home Infrastructure & Kubernetes Cluster

This is a mono repository for my home infrastructure and Kubernetes cluster. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like Talos Linux, Kubernetes, Flux, Helmfile, Just, mise, Renovate, Ansible, and Terraform.

Agent note: this README remains human-facing. Tooling and AI assistants should use the repository guidance files as the operational guide, starting at [CLAUDE.md](CLAUDE.md) and then following any more specific `CLAUDE.md` files in subdirectories.

## 🏠 Hardware Infrastructure

The cluster runs on a single bare-metal Talos node. A second machine handles file-level storage (NAS) and, during the K3s → Talos migration, still hosts the OpenMediaVault VM under Proxmox until Phase 10 retires the hypervisor layer.

| Device                              | Quantity | CPU                       | OS Disk            | Data Disk                    | RAM  | OS                | Function                                  |
|-------------------------------------|----------|---------------------------|--------------------|------------------------------|------|-------------------|-------------------------------------------|
| HP ProDesk 600 G6 Desktop Mini      | 1        | Intel i7-10700T @ 2.0 GHz | NVMe (PC801)       | NVMe (PC711)                 | 64GB | Talos Linux       | Single-node Kubernetes control plane + workloads |
| Lenovo M93p tiny USFF               | 1        | Intel i5-4570T @ 2.90GHz  | 512GB SSD          | USB3 DAS 16TB EXT4 (host)    | 16GB | Debian 13 + Proxmox | NAS host; OpenMediaVault VM (transitional) |

The Lenovo M93p will become a bare-metal OpenMediaVault host after the Talos cutover; the Proxmox + OMV VM model is intentionally temporary.

## 🔄 GitOps Workflow

### Flux

The cluster runs Flux through the [Flux Operator](https://fluxcd.control-plane.io/) pattern: a single `FluxInstance` CR declares the controllers, GitRepository, and root Kustomization. There is no classic `flux bootstrap` step.

- The `FluxInstance` resource points at `kubernetes/flux/cluster/`, which holds two root Kustomizations: `cluster-vars` (applies `kubernetes/flux/vars/`) and `cluster-apps` (reconciles `kubernetes/apps/`).
- `cluster-apps` recursively walks `kubernetes/apps/` and applies every `ks.yaml`.
- Each app folder generally contains a `ks.yaml`, the actual manifests under `app/`, and optionally extra directories such as `config/`, `certificate/`, or `backup/`.

The full bootstrap procedure is described in [docs/migration/05-flux-operator.md](docs/migration/05-flux-operator.md) and triggered by `just k8s-bootstrap cluster`.

### Renovate

Renovate watches the entire repository for dependency updates. When updates are found, a PR is automatically created. When PRs are merged, Flux applies the changes to the cluster. The root config lives in `.renovaterc.json5`, with topic-scoped fragments under `.renovate/`.

## 📁 Repository Structure

```text
📁 kubernetes
├── 📁 apps         # applications grouped by namespace
├── 📁 bootstrap    # Talos + Kubernetes platform bootstrap chain (helmfile + resources.yaml.j2)
├── 📁 components   # reusable Kustomize components (e.g. volsync)
├── 📁 flux         # FluxInstance entry point + cluster-wide vars
├── 📁 talos        # Talos machine configs and node templates
└── 📁 volsync      # operational helpers for the backup plane
📁 provision
├── 📁 cloudflare       # Cloudflare Terraform
├── 📁 ovh              # OVH Cloud Project Storage Terraform
├── 📁 openmediavault   # OMV Ansible (Phase 10) + just recipes
├── 📁 sops             # SOPS helper recipes
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

- **[sops](https://github.com/getsops/sops)**: Git-committed secrets for Kubernetes and Terraform (Age-encrypted)
- **[mise](https://mise.jdx.dev/)**: Pinned versions for `talosctl`, `kubectl`, `helm`, `helmfile`, `flux2`, `just`, `sops`, and the rest of the CLI surface
- **[Just](https://github.com/casey/just)**: Recipe runner; the root `.justfile` imports per-area `mod.just` modules (`k8s`, `k8s-bootstrap`, `talos`, `volsync`, `omv`, `cloudflare`, `ovh`, `sops`, `openwrt`)
- **[minijinja-cli](https://github.com/mitsuhiko/minijinja)** + `op inject`: Templated bootstrap-time resources fed from 1Password

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

The cluster uses a hybrid approach for secrets management:

- **Cluster-wide and bootstrap secrets**: Encrypted with SOPS (Age) and stored in the Git repository
- **Application secrets**: Stored in 1Password and accessed via the External Secrets operator against the shared `onepassword` `ClusterSecretStore`

This setup ensures sensitive data is properly secured while maintaining the GitOps workflow.

## 🚀 Deployment Dependencies

Applications are deployed with proper dependency management:

- `HelmRelease` resources can depend on other `HelmRelease` resources
- `Kustomization` resources can depend on other `Kustomization` resources
- In rare cases, applications can depend on both `HelmRelease` and `Kustomization` resources

This ensures applications are deployed in the correct order with all dependencies satisfied.
