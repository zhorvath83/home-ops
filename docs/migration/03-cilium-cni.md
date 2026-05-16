# 03 — Cilium CNI install + L2 announcement

## Status — 2026-05-16

| Részfeladat | Állapot |
|---|---|
| `kubernetes/apps/kube-system/cilium/` subtree (ks.yaml + app/ + config/) | ✅ kész — 7 fájl committed (HelmRelease + OCIRepository + L2 pool + L2 announcement policy) |
| `kubernetes/apps/kube-system/kustomization.yaml` regisztráció | ✅ kész — `./cilium/ks.yaml` felvéve |
| Manifestek validáció (`kustomize build`) | ✅ kész — `kube-system` namespace build zöld |
| Cilium **runtime install** a clusterre | ⏸ Phase 4 — a bootstrap helmfile chain első release-e fogja telepíteni (CRD apply hook a `config/`-ra) |
| Node `Ready=True` | ⏸ Phase 4 közben éleződik |

A Cilium HelmRelease konfigurációja már a `helmrelease.yaml`-ben kész — Phase 4 bootstrap helmfile a `templates/values.yaml.gotmpl`-en keresztül onnan olvas. Drift nincs bootstrap és runtime között.

## Cél

Calico (`tigera-operator`) lecserélése Cilium-ra, kube-proxy replacement módban. MetalLB lecserélése Cilium L2 announcement-tel. Hubble UI engedélyezve.

## Inputs

- Talos node `Ready=False` állapotban van (CNI hiányzik, lásd [02-talos-bootstrap.md](./02-talos-bootstrap.md) Stage 3 vége).
- Talos `cluster.network.cni.name: none` és `cluster.proxy.disabled: true`.
- Helmfile bootstrap chain a Cilium-ot elsőnek install-álja (lásd [04-bootstrap-helmfile.md](./04-bootstrap-helmfile.md)).

## Tervezett fájl-layout

```
kubernetes/apps/kube-system/cilium/
├── ks.yaml                       # 2 Flux Kustomization: cilium + cilium-config
└── app/
│   ├── kustomization.yaml
│   ├── helmrelease.yaml          # Cilium HelmRelease (release-default csak — lásd 04)
│   ├── ocirepository.yaml        # OCIRepository Cilium chartra
│   └── prometheusrules.yaml      # opcionális PrometheusRule alerts
└── config/
    ├── kustomization.yaml
    ├── pool.yaml                 # CiliumLoadBalancerIPPool (.15-.25)
    └── l2-announcement-policy.yaml  # CiliumL2AnnouncementPolicy
```

A `config/` szubdir egy második Flux Kustomization-ben (`cilium-config`) jön — a HelmRelease után, hogy a Cilium CRD-k léte garantált legyen.

## Bootstrap minta (helmfile install)

Cilium-ot a `kubernetes/bootstrap/helmfile.d/01-apps.yaml` install-álja **lánc elsőnek**, mert nélküle a node nem Ready és semmi pod nem indul (CNI nélkül).

```yaml
# kubernetes/bootstrap/helmfile.d/01-apps.yaml részlet
releases:
  - name: cilium
    namespace: kube-system
    chart: oci://quay.io/cilium/charts/cilium
    version: 1.19.4
    values:
      - templates/cilium-values.yaml.gotmpl    # ugyanazok az értékek, mint a HelmRelease-ben
    hooks:
      - command: bash
        args:
          - -c
          - until kubectl get crd ciliumloadbalancerippools.cilium.io ciliuml2announcementpolicies.cilium.io &>/dev/null; do sleep 5; done
        events: [postsync]
      - command: kubectl
        args:
          - apply
          - --namespace=kube-system
          - --server-side
          - --field-manager=kustomize-controller
          - --kustomize
          - ../../apps/kube-system/cilium/config/
        events: [postsync]
```

Magyarázat: Cilium install **után** a hook megvárja a CRD-ket, majd kubectl apply-elja a `config/` szubdir tartalmát (IPPool + L2 policy). Ez kiváltja a Flux dependsOn láncot bootstrap időben.

## HelmRelease (Flux runtime)

A bootstrap után Flux átveszi a Cilium kezelést — a `helmrelease.yaml` ugyanazt a chart-ot ugyanazon verzióval menedzseli. A Renovate-en keresztül frissül.

**Fájl:** `kubernetes/apps/kube-system/cilium/app/helmrelease.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cilium
spec:
  chartRef:
    kind: OCIRepository
    name: cilium
  interval: 1h
  values:
    # === IPAM & Network ===
    ipam:
      mode: kubernetes
    ipv4NativeRoutingCIDR: 10.244.0.0/16        # pod CIDR
    routingMode: native
    autoDirectNodeRoutes: true                   # single-node hatás: nincs különösebb, de kötelező native modhoz
    endpointRoutes:
      enabled: true

    # === kube-proxy replacement ===
    kubeProxyReplacement: true
    kubeProxyReplacementHealthzBindAddr: 0.0.0.0:10256
    k8sServiceHost: 127.0.0.1                    # KubePrism a Talos node-on
    k8sServicePort: 7445

    # === Datapath ===
    bpf:
      datapathMode: netkit                       # netkit > veth
      masquerade: true
      preallocateMaps: true
    bandwidthManager:
      enabled: true
      bbr: true                                  # BBR congestion control
    enableIPv4BIGTCP: true
    pmtuDiscovery:
      enabled: true

    # === Load balancing ===
    loadBalancer:
      algorithm: maglev
      mode: dsr                                  # Direct Server Return — alacsonyabb latency
    socketLB:
      enabled: true
      hostNamespaceOnly: true                    # iptables fallback host pod-okhoz
    localRedirectPolicies:
      enabled: true

    # === L2 announcement (NEM BGP) ===
    l2announcements:
      enabled: true
    bgpControlPlane:
      enabled: false                             # single-node, nem kell

    # === Hubble observability ===
    hubble:
      enabled: true
      relay:
        enabled: true
        rollOutPods: true
      ui:
        enabled: true
        rollOutPods: true
      metrics:
        enabled:
          - dns
          - drop
          - tcp
          - flow
          - port-distribution
          - icmp
          - httpV2

    # === Observability ===
    dashboards:
      enabled: true
      annotations:
        grafana_folder: Cilium
    operator:
      dashboards:
        enabled: true
        annotations:
          grafana_folder: Cilium
      prometheus:
        enabled: true
        serviceMonitor:
          enabled: true
      replicas: 1                                # single-node → 1 replica
      rollOutPods: true
    prometheus:
      enabled: true
      serviceMonitor:
        enabled: true
        trustCRDsExist: true
    rollOutCiliumPods: true

    # === Envoy (Cilium beépített Envoy proxy) ===
    envoy:
      enabled: false                             # külön Envoy Gateway lesz, nem Cilium L7

    # === CNI ===
    cni:
      exclusive: false                           # más CNI plugin-ek (loopback, host-local) maradhatnak

    # === cgroup ===
    cgroup:
      automount:
        enabled: false
      hostRoot: /sys/fs/cgroup

    # === Security capabilities (Cilium 1.19+) ===
    securityContext:
      capabilities:
        ciliumAgent:
          - CHOWN
          - KILL
          - NET_ADMIN
          - NET_RAW
          - IPC_LOCK
          - SYS_ADMIN
          - SYS_RESOURCE
          - PERFMON
          - BPF
          - DAC_OVERRIDE
          - FOWNER
          - SETGID
          - SETUID
        cleanCiliumState:
          - NET_ADMIN
          - SYS_ADMIN
          - SYS_RESOURCE
          - PERFMON
          - BPF
```

## CiliumLoadBalancerIPPool

**Fájl:** `kubernetes/apps/kube-system/cilium/config/pool.yaml`

```yaml
---
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: default
spec:
  blocks:
    - start: "192.168.1.15"
      stop: "192.168.1.25"
```

Tartomány: a [01-hardware-and-network.md](./01-hardware-and-network.md) IP plan szerint, `.15-.25` (11 db IP). A jelenlegi MetalLB allokáció (`.18`, `.19`, `.20`) ebbe a tartományba esik, így a meglévő service-ek IP-i változatlanok maradnak. Bővítési lehetőség 8 további LB IP-re.

**FONTOS:** A régi K3s VM-et **le kell kapcsolni** az új cluster boot-ja ELŐTT, különben IP-konfliktus alakul ki (MetalLB és Cilium L2 egyaránt ARP-pal jelentkezik be ugyanazokra az IP-kre).

## CiliumL2AnnouncementPolicy

**Fájl:** `kubernetes/apps/kube-system/cilium/config/l2-announcement-policy.yaml`

```yaml
---
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: default
spec:
  loadBalancerIPs: true                          # csak LB típusú service-eket
  interfaces:
    - ^net0$                                     # Talos LinkAliasConfig stabil NIC alias
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  serviceSelector:
    matchExpressions:
      - { key: "policy.cilium.io/exclude", operator: NotIn, values: ["true"] }
```

A `interfaces` regex a Talos `LinkAliasConfig` által beállított `net0` stabil aliasra illeszkedik. Az ARP/GARP-ot ezen az interfészen küldi ki. (A kernel által adott név — `enp0s31f6` / `enp1s0` — irreleváns, mert a LinkAlias átnevezi kernel-szinten is.)

A `serviceSelector` minden LB service-t bejelentés-ben hagy, kivéve ha a service-en `policy.cilium.io/exclude: "true"` label van (opt-out minta).

## config/ kustomization

**Fájl:** `kubernetes/apps/kube-system/cilium/config/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1
kind: Kustomization
resources:
  - ./pool.yaml
  - ./l2-announcement-policy.yaml
```

## Flux Kustomization-ok (ks.yaml)

**Fájl:** `kubernetes/apps/kube-system/cilium/ks.yaml`

Két Kustomization (két stage), a bjw-s konvenció szerint:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: cilium
  interval: 1h
  path: ./kubernetes/apps/kube-system/cilium/app
  prune: false                                   # CNI: SOHA prune
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: kube-system
  timeout: 5m
  wait: false
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium-config
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: cilium
      app.kubernetes.io/component: config
  dependsOn:
    - name: cilium
  interval: 1h
  path: ./kubernetes/apps/kube-system/cilium/config
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: kube-system
  timeout: 5m
  wait: false
```

`prune: false` a Cilium HelmRelease Kustomization-en: ha valaha véletlen törlődne a `ks.yaml`, a Cilium **ne kerüljön törlésre** — különben a node azonnal NotReady. A `config/` Kustomization prune-olható (IPPool/L2 policy nem életveszélyes). Figyeld a `app.kubernetes.io/component: config` extra label-t a második stage-en.

## Validation

### Cilium pod-ok

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
# 1× cilium-XXX (DaemonSet, single node)
# 1× cilium-operator-XXX
# 1× hubble-relay-XXX
# 1× hubble-ui-XXX (Deployment)
```

### Node Ready

```bash
kubectl get nodes
# NAME   STATUS   ROLES           AGE   VERSION
# main   Ready    control-plane   10m   v1.36.1
```

### Cilium status

```bash
# A cilium pod-ban:
kubectl -n kube-system exec ds/cilium -- cilium status
# minden zöld:
#   KubeProxyReplacement:  True
#   Host firewall:         Disabled
#   Routing:               Native
#   Datapath:              veth/netkit
#   Hubble:                Ok
```

### kube-proxy lecserélés ellenőrzés

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose | grep -A1 "KubeProxyReplacement"
# KubeProxyReplacement: True (Strict)
```

### L2 announcement

LoadBalancer service létrehozása teszt:

```bash
kubectl -n kube-system create -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
spec:
  type: LoadBalancer
  ports:
    - port: 80
  selector:
    app: nginx-test
EOF

kubectl -n kube-system get svc nginx-test
# EXTERNAL-IP: 192.168.1.18 (vagy a pool-ból egy IP — .18-.20 tartomány)

# ARP-ben látszik másik LAN gépről:
arping 192.168.1.18
# valid response from <HP MAC>
```

### Hubble UI

```bash
# Port-forward (Envoy Gateway HTTPRoute előtt):
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
open http://localhost:12000
# UI látható, flow-k mennek
```

Később Envoy Gateway HTTPRoute-ot kap (`hubble.<INTERNAL_DOMAIN>`), `envoy-internal`-en keresztül.

## Rollback

### Cilium nem indul

Bootstrap helmfile hibázik:
```bash
kubectl -n kube-system get pods
# crashloop? logs:
kubectl -n kube-system logs ds/cilium
```

Tipikus hibák:
- **`devices: bond+` nem illeszkedik** → változtass explicit NIC-re vagy hagyd ki a devices mezőt.
- **KubePrism port hibás** → ellenőrizd `machineconfig.yaml.j2` `kubePrism.port: 7445`.

### L2 announcement nem működik

```bash
kubectl -n kube-system get ciliuml2announcementpolicy
kubectl -n kube-system describe ciliuml2announcementpolicy default
# Events show binding to interfaces
```

Tipikus hibák:
- **`interfaces` regex nem illeszkedik** → ellenőrizd `talosctl get links` névvel, javítsd a `^enp.*` mintát.
- **NodeSelector nem talál node-ot** → `kubernetes.io/os: linux` standard label, mindig van.

### Cilium teljes wipe + reinstall

```bash
helm -n kube-system uninstall cilium
kubectl -n kube-system delete crd $(kubectl get crd -o name | grep cilium.io)
# Most a node NotReady — gyors reinstall:
just cluster-bootstrap apps         # helmfile sync
```

A pod-ok újraindulnak, de a service IP-k újragenerálódnak L2-n.

## Open issues

- **NIC interface név** L2 policy `interfaces` regex-ben: első Talos boot után `talosctl -n main get links`-szel ellenőrizni. Ha pl. `enp1s0` is van mellette (WiFi vagy más), érdemes szigorítani.
- **Hubble UI authentikáció**: alapból nincs auth. HTTPRoute-ban érdemes Anubis vagy basic-auth filter elé tenni — `envoy-internal`-en LAN-on belül kevésbé kritikus, de javasolt.
- **BGP migráció lehetőség**: ha jövőben több node lesz, L2 → BGP refaktor. OpenWRT-n FRR + BGP peer beállítása + Cilium `bgpControlPlane.enabled: true` + `CiliumBGPPeeringPolicy`. Külön doc lesz akkor.
- **iGPU (i915) Cilium-mal**: Cilium nem érinti a `/dev/dri` device-okat. Most NEM konfiguráljuk a Plex HW transcode-ot — phase 2 feladat, lásd [14-post-cutover.md](./14-post-cutover.md).
- **Cilium chart verzió**: `1.19.4` a bjw-s reference. Renovate frissíteni fogja, de ne automerge-eld CNI release-eket — manuálisan review-zd.
