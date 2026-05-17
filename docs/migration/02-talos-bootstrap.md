# 02 — Talos bootstrap

## Cél

A HP ProDesk node-on Talos Linux telepítése és Kubernetes cluster bootstrap. A bjw-s machineconfig minta adaptált single-node, kettős NVMe szétosztás (P31 = OS, P41 = democratic-csi data disk).

## Inputs

- HP hardver felkészítve [01](./01-hardware-and-network.md) szerint (BIOS, NVMe-k beszerelve).
- 1Password vault `automation/talos` items létrehozva (lásd alább).
- Lokális gépen `mise` + `talosctl` + `op` + `minijinja-cli` telepítve.
- USB pendrive ≥ 4 GB Talos installer ISO-hoz.

## Tervezett fájl-layout

```
kubernetes/talos/
├── mod.just                      # talos task recipes (apply, upgrade, reset, render)
├── schematic.yaml                # factory.talos.dev schematic (extensions)
├── machineconfig.yaml.j2         # közös machine config template
└── nodes/
    └── main.yaml.j2              # node-specific patches (egyetlen node: "main")
```

A node neve `main` (egyezik az AD-014 cluster névvel).

## Talos schematic

A factory.talos.dev custom installer image-et generálunk az alábbi extensions-szel.

**Fájl:** `kubernetes/talos/schematic.yaml`

```yaml
---
customization:
  extraKernelArgs:
    - initcall_blacklist=algif_aead_init    # bjw-s minta, lassú boot debug fix
  systemExtensions:
    officialExtensions:
      - siderolabs/i915                     # Intel iGPU (Plex HW transcode)
      - siderolabs/intel-ucode              # Intel microcode (security/stability)
```

A schematic SHA-jét lekérdezzük:

```bash
just talos gen-schematic-id
# outputs: c2edd5fcd4be75408274a70ace8b576ce2538414d44a3b5b4f19aef971186d41 (példa)
```

Az `install.image` mező a `machineconfig.yaml.j2`-ben erre a hashre épül:

```
factory.talos.dev/metal-installer/<SCHEMATIC_ID>:<TALOS_VERSION>
```

**Talos verzió**: **a legfrissebb stable** ([releases](https://github.com/siderolabs/talos/releases)) — soha NE rc/beta-t. A `gen-schematic-id` + `download-image` recipe-ek a fenti `curl ... releases/latest` lookup-pal dolgoznak. A schematic `release-<minor>` schema URL-jét a Talos verzió alapján kell frissíteni a `machineconfig.yaml.j2`-ben.

## 1Password vault items

A `op://automation/talos/` alá az alábbi mezők kellenek (a `talosctl gen secrets` parancs adja meg az értékeket első cluster generálásnál — egyszer kell elkészíteni):

| Field | Mit ad |
|---|---|
| `MACHINE_CA_CRT` / `MACHINE_CA_KEY` | Talos API CA |
| `MACHINE_TOKEN` | machine.token |
| `CLUSTER_CA_CRT` / `CLUSTER_CA_KEY` | K8s API CA |
| `CLUSTER_AGGREGATORCA_CRT` / `CLUSTER_AGGREGATORCA_KEY` | aggregation layer CA |
| `CLUSTER_ETCD_CA_CRT` / `CLUSTER_ETCD_CA_KEY` | etcd CA |
| `CLUSTER_ID` | cluster.id |
| `CLUSTER_SECRET` | cluster.secret |
| `CLUSTER_TOKEN` | cluster.token |
| `CLUSTER_SERVICEACCOUNT_KEY` | service account signing key |
| `CLUSTER_SECRETBOXENCRYPTIONSECRET` | etcd encryption at rest |

**Egyszeri generálás**:

```bash
talosctl gen secrets -o /tmp/talos-secrets.yaml
# Manuálisan átemeled 1Password-ba az "automation/talos" item-be field-enkén.
# /tmp/talos-secrets.yaml-t TÖRÖLD utána.
```

## Machine config template

**Fájl:** `kubernetes/talos/machineconfig.yaml.j2`

Az alábbi a bjw-s minta egyszerűsítve single-node-ra és HP hardverre. Eltérések indoklással kommentezve.

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/siderolabs/talos/refs/heads/release-1.10/website/content/v1.10/schemas/config.schema.json
version: v1alpha1
machine:
  ca:
    crt: op://automation/talos/MACHINE_CA_CRT
    {% if ENV.IS_CONTROLPLANE %}
    key: op://automation/talos/MACHINE_CA_KEY
    {% endif %}
  features:
    apidCheckExtKeyUsage: true
    diskQuotaSupport: true
    hostDNS:
      enabled: true
      forwardKubeDNSToHost: true
      resolveMemberNames: true
    kubePrism:
      enabled: true
      port: 7445
    {% if ENV.IS_CONTROLPLANE %}
    kubernetesTalosAPIAccess:
      enabled: true
      allowedRoles:
        - os:admin
      allowedKubernetesNamespaces:
        - system-upgrade           # Tuppr-nek
    {% endif %}
    rbac: true
  files:
    - op: create
      path: /etc/cri/conf.d/20-customization.part
      content: |-
        [plugins]
          [plugins."io.containerd.grpc.v1.cri"]
            enable_unprivileged_ports = true
            enable_unprivileged_icmp = true
        [plugins."io.containerd.cri.v1.images"]
          discard_unpacked_layers = false
        [plugins."io.containerd.cri.v1.runtime"]
          device_ownership_from_security_context = true
    - op: overwrite
      path: /etc/nfsmount.conf
      permissions: 0o644
      content: |
        [ NFSMount_Global_Options ]
        nfsvers=4.2
        hard=True
        nconnect=8
        noatime=True
        rsize=1048576
        wsize=1048576
  install:
    image: factory.talos.dev/metal-installer/{{ ENV.TALOS_SCHEMATIC_ID }}:{{ ENV.TALOS_VERSION }}
    # install.disk értéke a node-specific yaml-ben patch-elődik
  kernel:
    modules: []                    # bjw-s nbd/thunderbolt drop-pelve, HP-n nem kell
  kubelet:
    defaultRuntimeSeccompProfileEnabled: true
    disableManifestsDirectory: true
    extraConfig:
      maxPods: 150
      serializeImagePulls: false
    image: ghcr.io/siderolabs/kubelet:{{ ENV.KUBERNETES_VERSION }}    # legfrissebb stable, env-ből
    nodeIP:
      validSubnets:
        - 192.168.1.0/24
  sysctls:
    fs.inotify.max_user_instances: "8192"
    fs.inotify.max_user_watches: "1048576"
    net.core.default_qdisc: fq
    net.core.rmem_max: "67108864"
    net.core.wmem_max: "67108864"
    net.ipv4.neigh.default.gc_thresh1: "4096"
    net.ipv4.neigh.default.gc_thresh2: "8192"
    net.ipv4.neigh.default.gc_thresh3: "16384"
    net.ipv4.ping_group_range: 0 2147483647
    net.ipv4.tcp_congestion_control: bbr
    net.ipv4.tcp_fastopen: "3"
    net.ipv4.tcp_mtu_probing: "1"
    net.ipv4.tcp_notsent_lowat: "131072"
    net.ipv4.tcp_rmem: 4096 87380 33554432
    net.ipv4.tcp_slow_start_after_idle: "0"
    net.ipv4.tcp_window_scaling: "1"
    net.ipv4.tcp_wmem: 4096 65536 33554432
    sunrpc.tcp_max_slot_table_entries: "128"
    sunrpc.tcp_slot_table_entries: "128"
    user.max_user_namespaces: "11255"
    vm.nr_hugepages: "1024"
  token: op://automation/talos/MACHINE_TOKEN

cluster:
  {% if ENV.IS_CONTROLPLANE %}
  aggregatorCA:
    crt: op://automation/talos/CLUSTER_AGGREGATORCA_CRT
    key: op://automation/talos/CLUSTER_AGGREGATORCA_KEY
  allowSchedulingOnControlPlanes: true   # single node, kötelező
  apiServer:
    image: registry.k8s.io/kube-apiserver:{{ ENV.KUBERNETES_VERSION }}
    extraArgs:
      enable-aggregator-routing: "true"
    certSANs:
      - 127.0.0.1                        # KubePrism
      - 192.168.1.11                     # node IP
      - k8s.<INTERNAL_DOMAIN>            # belső DNS név
    disablePodSecurityPolicy: true
  controllerManager:
    image: registry.k8s.io/kube-controller-manager:{{ ENV.KUBERNETES_VERSION }}
    extraArgs:
      bind-address: 0.0.0.0
  coreDNS:
    disabled: true                       # CoreDNS-t Helm-en keresztül telepítjük
  etcd:
    advertisedSubnets:
      - 192.168.1.0/24
    ca:
      crt: op://automation/talos/CLUSTER_ETCD_CA_CRT
      key: op://automation/talos/CLUSTER_ETCD_CA_KEY
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
  proxy:
    disabled: true                       # kube-proxy disabled, Cilium veszi át
    image: registry.k8s.io/kube-proxy:{{ ENV.KUBERNETES_VERSION }}
  scheduler:
    extraArgs:
      bind-address: 0.0.0.0
    image: registry.k8s.io/kube-scheduler:{{ ENV.KUBERNETES_VERSION }}
  secretboxEncryptionSecret: op://automation/talos/CLUSTER_SECRETBOXENCRYPTIONSECRET
  serviceAccount:
    key: op://automation/talos/CLUSTER_SERVICEACCOUNT_KEY
  {% endif %}
  ca:
    crt: op://automation/talos/CLUSTER_CA_CRT
    {% if ENV.IS_CONTROLPLANE %}
    key: op://automation/talos/CLUSTER_CA_KEY
    {% endif %}
  controlPlane:
    endpoint: https://192.168.1.11:6443
  clusterName: main
  discovery:
    enabled: true
    registries:
      kubernetes: { disabled: true }
      service: { disabled: false }
  id: op://automation/talos/CLUSTER_ID
  network:
    cni:
      name: none                         # Cilium veszi át, lásd 03-cilium-cni.md
    dnsDomain: cluster.local
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.245.0.0/16
  secret: op://automation/talos/CLUSTER_SECRET
  token: op://automation/talos/CLUSTER_TOKEN

---
# Single NIC config — bjw-s bond+VLAN dropped, HP-n nincs rá szükség
apiVersion: v1alpha1
kind: DHCPv4Config
name: enp0s31f6                          # I219 NIC alapján — első boot után ellenőrizni
clientIdentifier: mac
---
apiVersion: v1alpha1
kind: WatchdogTimerConfig
device: /dev/watchdog0
timeout: 5m
---
# EPHEMERAL volume a Talos OS disk-en (P31 / install.disk)
apiVersion: v1alpha1
kind: VolumeConfig
name: EPHEMERAL
provisioning:
  diskSelector:
    match: system_disk
  maxSize: 256GiB
---
# UserVolume a P41 NVMe-n (democratic-csi data)
# A democratic-csi local-hostpath driver ezt mountolja /var/mnt/extra-disk-re
apiVersion: v1alpha1
kind: UserVolumeConfig
name: local-hostpath
provisioning:
  diskSelector:
    # P41 NVMe — by-id alapján egyértelmű, hogy NEM az install disk
    match: '!system_disk && disk.transport == "nvme"'
  maxSize: 1000GiB
  filesystem:
    type: xfs
```

## Node patch

**Fájl:** `kubernetes/talos/nodes/main.yaml.j2`

Egyetlen node, controlplane szerep:

```yaml
machine:
  type: controlplane
  network:
    hostname: main
  install:
    # Konkrét install disk by-id — első boot Talos installer után:
    #   talosctl -n 192.168.1.11 get disks
    # Az nvme0n1 vagy nvme1n1 közül a P31 (P711, kisebb) modell stringet keressük
    disk: /dev/disk/by-id/nvme-SK_hynix_Gold_P31_1TB_<SERIAL>
```

**SERIAL** értékét az első Talos installer boot után `talosctl get disks` adja vissza.

## Talos install workflow

### Stage 0: Schematic ID + installer ISO

```bash
# Lokálisan, a legfrissebb stable Talos:
TALOS_VERSION=$(curl -s https://api.github.com/repos/siderolabs/talos/releases/latest | jq -r .tag_name)
echo "Latest stable: $TALOS_VERSION"

just talos gen-schematic-id
# kimenet pl.: c2edd5fcd4be75408274a70ace8b576ce2538414d44a3b5b4f19aef971186d41

just talos download-image "$TALOS_VERSION" <schematic-id>
# letöltött ISO: kubernetes/talos/talos-<version>-<schematic-prefix>.iso
```

USB-re írás (`dd` vagy [balenaEtcher](https://www.balena.io/etcher/)):

```bash
sudo dd if=kubernetes/talos/talos-*.iso of=/dev/disk/<USB> bs=4M status=progress
sync
```

### Stage 1: HP boot USB-ről

1. HP bekapcsolás, F9 = boot menu.
2. USB pendrive kiválasztás.
3. Talos installer "Maintenance Mode"-ban indul (nincs még apply-elt config).
4. A node IP-t DHCP-ből kapja → ellenőrzés OpenWRT-ben, hogy `.11`-et kapja.

### Stage 2: Apply config (insecure mode)

```bash
# Egy lokális shell session-ben:
export TALOSCONFIG=./talosconfig
op signin                                         # 1Password CLI

# Verziók environment-be (legfrissebb stable lookup):
export TALOS_SCHEMATIC_ID="$(just talos gen-schematic-id)"
export TALOS_VERSION="$(curl -s https://api.github.com/repos/siderolabs/talos/releases/latest | jq -r .tag_name)"
export KUBERNETES_VERSION="$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r .tag_name)"

# Apply (insecure mode — első apply esetén)
just talos apply-node 192.168.1.11 --insecure
```

A `just talos apply-node` recipe (lásd bjw-s `kubernetes/talos/mod.just`):

1. minijinja-cli rendereli a `machineconfig.yaml.j2`-t a `nodes/main.yaml.j2` patch-csel.
2. `op inject`-tel kicseréli a `op://automation/talos/*` referenciákat valós értékekre.
3. `talosctl apply-config -f /dev/stdin --insecure` betölti a node-ra.

A node ezután reboot, és **felinstall-álja magát** az `install.disk`-re a Talos OS-t.

### Stage 3: Bootstrap

```bash
# Wait for node to come back up after install
until talosctl -n 192.168.1.11 version 2>/dev/null; do
  echo "Waiting for node..."; sleep 5
done

# Bootstrap etcd (single control plane)
talosctl -n 192.168.1.11 bootstrap

# Wait for k8s API
until talosctl -n 192.168.1.11 health 2>/dev/null; do
  echo "Waiting for k8s API..."; sleep 5
done

# Fetch kubeconfig
talosctl -n 192.168.1.11 kubeconfig -f --force-context-name main ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig

# Node Ready=False várható (nincs CNI még)
kubectl get nodes
# NAME   STATUS     ROLES           AGE   VERSION
# main   NotReady   control-plane   2m    v1.36.1
```

### Stage 4: Cilium install — átadás a [03-cilium-cni.md](./03-cilium-cni.md) docnak

A `just k8s-bootstrap cluster` recipe ezt a teljes lánc-ot egy parancsban lefutta — lásd [04-bootstrap-helmfile.md](./04-bootstrap-helmfile.md).

## Talos kernel modulok és extensions

| Modul/Extension | Miért kell |
|---|---|
| `siderolabs/intel-ucode` | Intel CPU mikrokód, biztonsági javítások |
| `siderolabs/i915` | Intel iGPU (`/dev/dri/renderD128`), Plex HW transcode |
| **Nem kell**: `nbd` | network block device — bjw-s-nek igen, nekünk nem |
| **Nem kell**: `thunderbolt` | HP-n nincs thunderbolt |

A QuickSync passthrough Plex pod-ba külön device mount-tal történik (részletek a Plex `helmrelease.yaml`-ben, lásd [06-repo-restructure.md](./06-repo-restructure.md)).

## Validation

Minden Stage után:

**Stage 1 után**:

```bash
ping 192.168.1.11                       # DHCP-ből kapott IP működik
talosctl -n 192.168.1.11 get disks --insecure
# kimenetnek mutatnia kell mindkét NVMe-t
```

**Stage 2 után**:

```bash
talosctl -n 192.168.1.11 get machineconfig
# konfig betöltve, nincs error
```

**Stage 3 után**:

```bash
kubectl get nodes
# main NotReady (CNI hiányzik még) — ez normális
talosctl -n 192.168.1.11 service
# etcd, kubelet, apid running
```

**Stage 4 (Cilium) után** — lásd [03-cilium-cni.md](./03-cilium-cni.md):

```bash
kubectl get nodes
# main Ready
```

## Rollback

### Apply config hiba

Ha rosszul apply-eltél, két opció:

1. **Online patch**: `talosctl -n 192.168.1.11 apply-config -f new-config.yaml` (újra, javított yaml-lel).
2. **Reset**: `just talos reset-node 192.168.1.11` → wipe STATE + EPHEMERAL → újra Stage 1-től.

### Hibás install disk

Ha rossz NVMe-re install-elt:

1. Power off HP.
2. Cseréld meg a két NVMe-t fizikailag.
3. Vagy: a `nodes/main.yaml.j2`-ben javítsd a `disk:` mezőt, `just talos reset-node` + újra apply.

### Bootstrap hiba

Ha `talosctl bootstrap` hibázik:

1. `talosctl -n 192.168.1.11 logs etcd` — etcd hiba?
2. `talosctl -n 192.168.1.11 reset --system-labels-to-wipe EPHEMERAL` — etcd state wipe, újra bootstrap.

### Teljes újrakezdés

```bash
just talos reset-cluster reboot
# minden disk wipe-elve, node újraindul installer módba
```

## Open issues

- **NIC interface név**: A bjw-s `enp0s31f6` (intel chipset standard) **valószínűleg** a HP I219-nek is ez lesz, de **első boot után ellenőrizni** `talosctl get links`-szel. Ha más (pl. `enp1s0`), patchelni a `DHCPv4Config name:` mezőjén.
- **i915 device node létrehozás**: Talos 1.10.x-en megbízható, 1.12.0-rc1-ben regresszió volt — stable release-t használunk.
- **UserVolumeConfig (local-hostpath) első indítás**: ha a P41 üres, Talos formázza XFS-re. Ha valami már van rajta (régi adat), előbb `talosctl reset --user-disks-to-wipe`.
- **NFS NFSv4 mount sysctls**: a `sunrpc.tcp_*` és `nfsmount.conf` minta bjw-s-től örökölt. NFS performance optimalizáció — ha kell, finomítható.
- **kubePrism (7445 port)** — Talos beépített K8s API proxy a node-on. ESO és cert-manager hasznosíthatja, hogy ne menjen az API forgalom külön round-tripben.
