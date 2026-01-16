# Home Infrastructure & Kubernetes Cluster

This is a mono repository for my home infrastructure and Kubernetes cluster. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like Ansible, Terraform, Kubernetes, Flux, Renovate, and GitHub Actions.

## 🏠 Hardware Infrastructure

The infrastructure is built on a Debian 13 Proxmox server with the following specifications:

| Device                | Quantity | CPU                      | OS Disk Size | RAM  | OS        | Function           |
|-----------------------|----------|--------------------------|--------------|------|-----------|--------------------|
| Lenovo M93p tiny USFF | 1        | Intel i5-4570T @ 2.90GHz | 512GB SSD    | 16GB | Debian 13 | Proxmox hypervisor |

**Virtual Machines:**

| Device | Quantity | OS Disk Size | Data Disk Size             | RAM  | OS        | Function                              |
|--------|----------|--------------|----------------------------|------|-----------|---------------------------------------|
| NAS VM | 1        | 16 GB        | USB3 DAS 16TB EXT4 (host)  | 2GB  | Debian 13 | SMB + NFS NAS, OpenMediaVault 8       |
| K3s VM | 1        | 200GB        | -                          | 12GB | Debian 13 | K3s master node - single node cluster |

## 🔄 GitOps Workflow

### Flux

Flux watches the clusters in my kubernetes folder and makes changes to my clusters based on the state of this Git repository. The workflow operates as follows:

- Flux recursively searches the `kubernetes/apps` folder until it finds the most top level `kustomization.yaml` per directory
- Each `kustomization.yaml` generally contains:
  - A namespace resource
  - One or many Flux kustomizations (`ks.yaml`)
- Under the control of those Flux kustomizations, there will be a `HelmRelease` or other resources related to the application

### Renovate

Renovate watches the entire repository for dependency updates. When updates are found, a PR is automatically created. When PRs are merged, Flux applies the changes to the cluster.

## 📁 Repository Structure

```text
📁 kubernetes
├── 📁 apps       # applications
├── 📁 bootstrap  # initial cluster setup and configuration
└── 📁 flux       # flux system configuration
```

## 🔧 Application Deployment Strategy

I use official Helm charts whenever possible for applications. When official charts are not available, I use the **[bjw-s Helm Chart ecosystem](https://bjw-s-labs.github.io/helm-charts/docs)** to ensure consistent deployment patterns.

**[bjw-s Common Library](https://bjw-s-labs.github.io/helm-charts/docs/common-library/)**: Helm 3 library chart providing reusable templates for common Kubernetes resources.

**[bjw-s App Template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)**: Companion chart that enables deployment of any application using the Common Library.

## 🛠️ Core Components

### Networking & Security

- **[cert-manager](https://github.com/cert-manager/cert-manager)**: SSL certificates for services
- **[Calico](https://github.com/projectcalico/calico)**: Container networking and network security
- **[MetalLB](https://github.com/metallb/metallb)**: Load balancer for bare metal clusters
- **[cloudflared](https://github.com/cloudflare/cloudflared)**: Cloudflare secure tunnel access
- **[Ingress NGINX](https://github.com/kubernetes/ingress-nginx)**: NGINX-based ingress controller

### DNS & External Integration

- **[external-dns](https://github.com/kubernetes-sigs/external-dns)**: Automatic DNS record synchronization
- **[external-secrets](https://github.com/external-secrets/external-secrets)**: Secrets management using [1Password Connect](https://github.com/1Password/connect)

### Storage & Backup

- **[democratic-csi](https://github.com/democratic-csi/democratic-csi)**: CSI driver supporting local hostpath, NFS, iSCSI and ZFS storage backends
- **[volsync](https://github.com/backube/volsync)**: PVC backup and recovery using Restic to Backblaze B2

### Configuration Management

- **[sops](https://github.com/getsops/sops)**: Git-committed secrets for Kubernetes and Terraform

## ☁️ Cloud Provider: Cloudflare

All Cloudflare resources are managed using Terraform with the Cloudflare provider. Configuration files are located in the `provision/cloudflare` directory.

### Cloudflare Resources

- **DNS records**: For both cluster resources and custom domain email settings
- **Cloudflare Access**: Zero-trust network access
- **Cloudflare Pages**: Hosts private homepage (separate repository)
- **Cloudflare Firewall**: Security rules and protection
- **R2 Bucket**: Storage for homepage downloadable files
- **Redirect Rules**: HTTP to HTTPS redirects
- **Cloudflare Tunnel**: Publishes cluster resources securely
- **Cloudflare Workers**
  - Email MTA-STS policy
  - Custom pension fund exchange rate query service
- **Zone Settings**: Domain configuration and optimization

## 🔐 Secrets Management

The cluster uses a hybrid approach for secrets management:

- **Basic cluster secrets**: Encrypted with SOPS and stored in the Git repository
- **Application secrets**: Stored in 1Password and accessed via External Secrets operator

This setup ensures sensitive data is properly secured while maintaining the GitOps workflow.

## 🚀 Deployment Dependencies

Applications are deployed with proper dependency management:

- `HelmRelease` resources can depend on other `HelmRelease` resources
- `Kustomization` resources can depend on other `Kustomization` resources
- In rare cases, applications can depend on both `HelmRelease` and `Kustomization` resources

This ensures applications are deployed in the correct order with all dependencies satisfied.
