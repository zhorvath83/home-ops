# 05 — Flux Operator + FluxInstance

## Cél

A klasszikus `flux bootstrap` parancsot lecseréljük Flux Operator-ra (controlplane.io). A Flux controllerek életciklusát a `FluxInstance` CRD deklaratív módon vezérli — beleértve a performance tuning patch-eket.

## Inputs

- A bootstrap helmfile install-álja a `flux-operator` és `flux-instance` Helm release-eket (lásd [04-bootstrap-helmfile.md](./04-bootstrap-helmfile.md), 7-8. release).
- A `flux-instance` HelmRelease egy `FluxInstance` CR-t hoz létre, ami a Flux controllerek deployment-jét vezérli.
- A `FluxInstance` egy `GitRepository`-t hoz létre, ami a `kubernetes/flux/cluster/` path-ot olvassa → onnan minden más Flux Kustomization elindul.

## Tervezett fájl-layout

```
kubernetes/apps/flux-system/
├── kustomization.yaml                          # ns alá: flux-operator/, flux-instance/, addons/
├── namespace.yaml
├── flux-operator/
│   ├── ks.yaml                                 # Kustomization → app/
│   └── app/
│       ├── kustomization.yaml
│       ├── helmrelease.yaml                    # flux-operator chart
│       └── ocirepository.yaml                  # OCIRepo
├── flux-instance/
│   ├── ks.yaml                                 # Kustomization → app/, dependsOn: flux-operator
│   └── app/
│       ├── kustomization.yaml
│       ├── helmrelease.yaml                    # flux-instance chart (FluxInstance config)
│       └── ocirepository.yaml
└── addons/
    ├── alerts/                                 # Pushover alerts (megőrzött)
    └── webhooks/                               # GitHub webhook receiver (megőrzött)

kubernetes/flux/
├── cluster/
│   └── ks.yaml                                 # root Kustomization → ./kubernetes/apps
└── vars/
    ├── kustomization.yaml
    ├── cluster-settings.yaml                   # MEGŐRZÖTT (onedr0p-stílus)
    └── cluster-secrets.sops.yaml               # MEGŐRZÖTT (PUBLIC_DOMAIN, SECRET_QBITTORRENT_PW)
```

**Megjegyzés**: a bjw-s **nem** használja a `vars/` mappát — minden Helm value az app `helmrelease.yaml`-ben közvetlenül él. A te jelenlegi setup-od (és onedr0p / buroa) `cluster-settings` ConfigMap-ot és `cluster-secrets` Secret-et használ `substituteFrom`-mal. **Megőrizzük ezt a mintát** — a bjw-s-szintű minimalizmus külön major refaktor lenne, és nem cél a cutover részeként.

## Flux Operator HelmRelease

A Flux Operator a Flux controllerek install-jának deklaratív felülete.

**Fájl:** `kubernetes/apps/flux-system/flux-operator/app/helmrelease.yaml`

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: flux-operator
spec:
  chartRef:
    kind: OCIRepository
    name: flux-operator
  interval: 30m
  values:
    serviceMonitor:
      create: true
```

**OCIRepository** ehhez:

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: flux-operator
spec:
  interval: 5m
  url: oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator
  ref:
    tag: 0.49.0
```

**ks.yaml**:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-operator
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: flux-operator
  interval: 1h
  path: ./kubernetes/apps/flux-system/flux-operator/app
  prune: false                                  # SOHA prune (Flux saját maga)
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: flux-system
  timeout: 5m
  wait: false
```

## Flux Instance HelmRelease

A `FluxInstance` CR vezérli, hogy melyik Flux controller-ek fussanak, milyen verzió, milyen sync forrás.

**Fájl:** `kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml`

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: flux-instance
spec:
  chartRef:
    kind: OCIRepository
    name: flux-instance
  interval: 30m
  values:
    instance:
      distribution:
        artifact: oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests:v0.49.0
        version: 2.x
      cluster:
        networkPolicy: false
      components:
        - source-controller
        - kustomize-controller
        - helm-controller
        - notification-controller
      sync:
        kind: GitRepository
        url: https://github.com/zhorvath83/home-ops.git
        ref: refs/heads/main                  # TALOS branch fejlesztés alatt: refs/heads/talos
        path: kubernetes/flux/cluster
        interval: 1h
      commonMetadata:
        labels:
          app.kubernetes.io/name: flux
      kustomize:
        patches:
          # 1. Concurrent workers + requeue
          - patch: |
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --concurrent=10
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --requeue-dependency=5s
            target:
              kind: Deployment
              name: (kustomize-controller|helm-controller|source-controller)
          # 2. Memory limit emelés (single node — 2 Gi nem sok)
          - patch: |
              apiVersion: apps/v1
              kind: Deployment
              metadata:
                name: all
              spec:
                template:
                  spec:
                    containers:
                      - name: manager
                        resources:
                          limits:
                            memory: 2Gi
            target:
              kind: Deployment
              name: (kustomize-controller|helm-controller|source-controller)
          # 3. In-memory kustomize builds (gyorsabb)
          - patch: |
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --concurrent=20
              - op: replace
                path: /spec/template/spec/volumes/0
                value:
                  name: temp
                  emptyDir:
                    medium: Memory
            target:
              kind: Deployment
              name: kustomize-controller
          # 4. Helm repo caching
          - patch: |
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --helm-cache-max-size=10
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --helm-cache-ttl=60m
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --helm-cache-purge-interval=5m
            target:
              kind: Deployment
              name: source-controller
          # 5. OOM detection for Helm
          - patch: |
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --feature-gates=OOMWatch=true
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --oom-watch-memory-threshold=95
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --oom-watch-interval=500ms
            target:
              kind: Deployment
              name: helm-controller
          # 6. Disable chart digest tracking (faster)
          - patch: |
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --feature-gates=DisableChartDigestTracking=true
            target:
              kind: Deployment
              name: helm-controller
          # 7. Cancel health checks on new revisions
          - patch: |-
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --feature-gates=CancelHealthCheckOnNewRevision=true
            target:
              kind: Deployment
              name: kustomize-controller
```

**FONTOS — a `sync.ref`-ről**:
- A `talos` branch fejlesztése alatt: `ref: refs/heads/talos`.
- Cutover után (talos branch merge main-be): `ref: refs/heads/main`.
- A FluxInstance HelmRelease ezt változtatja meg cutover idején — egyetlen érték.

## Cluster root Kustomization-ök — kétszintű flow

A `FluxInstance` `sync.path: kubernetes/flux/cluster`-re mutat. Ott **két Kustomization** él egy fájlban: `cluster-vars` (cluster-settings + cluster-secrets a `flux/vars/` mappából) és `cluster-apps` (a `./kubernetes/apps`-t reconcile-álja). A `cluster-apps` `dependsOn` a `cluster-vars`-ra, hogy a substituteFrom forrásai garantáltan léteznek a reconcile előtt.

**Fájl:** `kubernetes/flux/cluster/ks.yaml`

```yaml
---
# Stage 1: cluster-vars — cluster-settings ConfigMap + cluster-secrets Secret (SOPS)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-vars
  namespace: flux-system
spec:
  interval: 1h
  path: ./kubernetes/flux/vars
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  wait: true
  timeout: 5m
---
# Stage 2: cluster-apps — a teljes ./kubernetes/apps tree, dependsOn cluster-vars
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-apps
  namespace: flux-system
spec:
  dependsOn:
    - name: cluster-vars
  interval: 1h
  path: ./kubernetes/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-settings
      - kind: Secret
        name: cluster-secrets
  patches:
    - # Inject SOPS decryption + substituteFrom defaults into every child Kustomization
      patch: |-
        apiVersion: kustomize.toolkit.fluxcd.io/v1
        kind: Kustomization
        metadata:
          name: _
        spec:
          decryption:
            provider: sops
            secretRef:
              name: sops-age
          postBuild:
            substituteFrom:
              - kind: ConfigMap
                name: cluster-settings
              - kind: Secret
                name: cluster-secrets
      target:
        group: kustomize.toolkit.fluxcd.io
        kind: Kustomization
        labelSelector: substitution.flux.home.arpa/disabled notin (true)
    - # Inject HelmRelease defaults into every HelmRelease (via child Kustomization patch)
      patch: |-
        apiVersion: kustomize.toolkit.fluxcd.io/v1
        kind: Kustomization
        metadata:
          name: _
        spec:
          patches:
            - patch: |-
                apiVersion: helm.toolkit.fluxcd.io/v2
                kind: HelmRelease
                metadata:
                  name: _
                spec:
                  install:
                    crds: CreateReplace
                    strategy:
                      name: RetryOnFailure
                  rollback:
                    cleanupOnFail: true
                  timeout: 10m
                  upgrade:
                    cleanupOnFail: true
                    crds: CreateReplace
                    strategy:
                      name: RemediateOnFailure
                    remediation:
                      remediateLastFailure: true
                      retries: 2
              target:
                group: helm.toolkit.fluxcd.io
                kind: HelmRelease
      target:
        group: kustomize.toolkit.fluxcd.io
        kind: Kustomization
```

**Bootstrap flow ezzel a struktúrával**:

1. A bootstrap helmfile végén a `flux-instance` release fut → a Flux Instance létrejön és reconcile-ol.
2. A `FluxInstance.spec.sync.path: kubernetes/flux/cluster` egy implicit Kustomization-t hoz létre `flux-system` névvel, amely apply-olja a `ks.yaml` tartalmát → két új Kustomization létrejön: `cluster-vars` és `cluster-apps`.
3. **`cluster-vars`** reconcile-ol elsőként:
   - Olvassa a `kubernetes/flux/vars/`-t (kustomization.yaml → cluster-settings.yaml + cluster-secrets.sops.yaml).
   - A `cluster-secrets.sops.yaml`-t a `sops-age` Secret-tel dekódolja.
   - Létrehozza a `cluster-settings` ConfigMap-et és a `cluster-secrets` Secret-et a `flux-system` namespace-ben.
   - `wait: true` → várja, hogy mindkét resource Ready.
4. **`cluster-apps`** elindul (mert `dependsOn: cluster-vars` Ready):
   - Reconcile-ol a `./kubernetes/apps`-on.
   - A `substituteFrom: cluster-settings + cluster-secrets` mostantól működik (mindkettő létezik).
   - A két patch beépíti a SOPS dekripciót és a substituteFrom-ot minden child Kustomization-be is, és a HelmRelease default-okat minden HelmRelease-be.

**Kulcs**: a `cluster-vars` Kustomization MIATT nem kell a bootstrap-ben kézzel apply-olni a `flux/vars/`-t. Flux kezeli, GitOps-natívan.

**Magyarázat a patches-hez**:
1. **Első patch** (SOPS + substituteFrom): minden gyermek Kustomization automatikusan örökli ezeket. Opt-out a `substitution.flux.home.arpa/disabled: "true"` label-lal.
2. **Második patch** (HelmRelease defaults): minden HelmRelease automatikusan kap install/rollback/upgrade default-okat (CRD createReplace, retry, timeout, remediation).

## `kubernetes/flux/vars/kustomization.yaml`

Változatlan a jelenlegi:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cluster-settings.yaml
  - cluster-secrets.sops.yaml
```

## GitRepository — Flux Operator által generált

A `FluxInstance` automatikusan létrehoz egy `GitRepository`-t a `sync.url` alapján. Nem kell kézzel definiálni.

```yaml
# Auto-generated by FluxInstance:
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1h
  url: https://github.com/zhorvath83/home-ops.git
  ref:
    branch: main                              # vagy talos a fejlesztés alatt
```

A `kubernetes/apps/*/.../ks.yaml`-ekben minden Kustomization erre hivatkozik:

```yaml
sourceRef:
  kind: GitRepository
  name: flux-system
  namespace: flux-system
```

## sops-age Secret bootstrap

A SOPS decryption-höz szükséges az `sops-age` Secret a `flux-system` namespace-ben. Ezt **a bootstrap időben** kell beilleszteni (a Flux még nem tudja maga magát feloldani).

**Recipe:** kubernetes/bootstrap/mod.just `resources` stage-be hozzáadjuk:

```bash
# A resources.yaml.j2 mellett a sops-age Secret kézi apply:
kubectl create secret generic sops-age -n flux-system \
  --from-file=age.agekey="$HOME/.config/sops/age/keys.txt" \
  --dry-run=client -o yaml | kubectl apply --server-side -f -
```

VAGY a `resources.yaml.j2`-ben:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: sops-age
  namespace: flux-system
stringData:
  age.agekey: op://Automation/sops-age/keys.txt
```

A `1Password Automation/sops-age` item-ben tárolt age private key-t injektálja `op inject`-tel.

## Validation

### Flux Operator running

```bash
kubectl -n flux-system get pods -l app.kubernetes.io/name=flux-operator
# 1× flux-operator-XXX Running

kubectl -n flux-system get fluxinstance
# NAME    READY   STATUS
# flux    True    Reconciled
```

### Flux controllerek

```bash
flux check
# Ready check passes for all controllers

kubectl -n flux-system get pods
# kustomize-controller, helm-controller, source-controller, notification-controller — Running
```

### Cluster reconcile

```bash
flux get sources git
# NAME          REVISION   READY
# flux-system   <hash>     True

flux get kustomizations
# cluster-apps reconcile in progress

kubectl get ks -A
# minden Kustomization Ready=True idővel
```

### HelmRelease patch-ek alkalmazódtak

```bash
kubectl -n cert-manager get hr cert-manager -o yaml | grep -A2 "install:"
# install:
#   crds: CreateReplace
#   strategy:
#     name: RetryOnFailure
```

Ha látható → a HelmRelease default patch működik.

## Rollback

### Flux Instance broken

```bash
kubectl -n flux-system describe fluxinstance flux
# Events
```

Tipikus hibák:
- **Git URL elérhetetlen**: `gitea` vagy github auth nem stimmel.
- **Branch nem létezik**: ha `talos` branch még nincs push-olva, FluxInstance hibázik. **Fontos cutover-kor!**

Fix: módosítsd a `flux-instance` HelmRelease `sync.ref:` mezőjét, commit + push (de várj, ha `main`-en vagy és `talos`-on át dolgozol, akkor `talos` branch-be).

### Patch syntax hiba

A FluxInstance `kustomize.patches` szigorúan JSON patch syntax. Ha hibás patch:
```bash
kubectl -n flux-system describe fluxinstance flux
# Patch parse error
```

Fix: javítsd a HelmRelease `values.instance.kustomize.patches`-ot, commit + push.

### Teljes Flux uninstall

```bash
# FluxInstance törli a controllerek-et:
helm -n flux-system uninstall flux-instance
helm -n flux-system uninstall flux-operator

# CRD-k:
kubectl delete crd $(kubectl get crd -o name | grep fluxcd.io)
```

Aztán a bootstrap helmfile újrafutása újra hoz mindent (az apps már a clusterben vannak, csak Flux reconcile-juk újrakezdődik).

## Open issues

- **`sops-age` Secret életciklusa**: jelenleg az `~/.config/sops/age/keys.txt`-t használjuk. 1Password-ba beemelni és `op inject`-tel kezelni — már az tervezés része, csak a 1Password item-et létre kell hozni.
- **GitOps source private vs public repo**: a `home-ops` repo public. Ha jövőben private lenne, a `GitRepository.spec.secretRef`-et kell konfigurálni (SSH key vagy PAT 1Password-ből).
- **Notification controller — Pushover provider**: a jelenlegi `flux-provider-pushover` megőrzött (lásd [06-repo-restructure.md](./06-repo-restructure.md)). FluxInstance `components`-be `notification-controller` benn van.
- **Flux Instance verzió drift**: a `flux-instance` chart verzió és a `distribution.artifact` `flux-operator-manifests:v0.49.0` verzió eltérhet. Renovate ezt egyben frissíti (group: flux-operator).
- **HelmRelease patch override**: ha egy app a default patch-csel nem boldogul (pl. más timeout kell), az `app/helmrelease.yaml`-ben felülírhatja a `spec.timeout`-ot. A default patch csak akkor lép, ha az adott mező hiányzik.
