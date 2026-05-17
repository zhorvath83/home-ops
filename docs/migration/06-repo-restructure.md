# 06 — Repo restructure: apps + namespace refactor

## Status — 2026-05-17

| Részfeladat | Állapot |
|---|---|
| Kustomization név refactor: `cluster-apps-<X>` → `<X>` minden ks.yaml-ben (41 fájl) | ✅ kész |
| `dependsOn` referenciák átvezetése (`cluster-apps-onepassword-store` → `onepassword-store`, stb.) | ✅ kész |
| GitRepository név: `home-ops-kubernetes` → `flux-system` minden sourceRef-ben + `flux/config/cluster.yaml` GitRepository erőforrásban | ✅ kész |
| `sourceRef.namespace: flux-system` mező explicit hozzáadása minden ks.yaml-be | ✅ kész |
| Schema URL: `fluxcd-community/flux2-schemas` → `k8s-schemas.bjw-s.dev` | ✅ kész |
| GitHub webhook receiver GitRepository ref update | ✅ kész |
| `kubernetes/flux/` layout bjw-s-re átállítva (`apps.yaml` + `config/` törölve, `flux/cluster/ks.yaml` létrehozva) | ✅ kész — lásd Phase 5 |
| `kubernetes/apps/kube-system/cilium/` új subtree | ✅ kész — lásd Phase 3 |
| `namespace.yaml` `prune: disabled` LABEL → ANNOTATION fix (8 fájl) | ✅ kész |
| ks.yaml `spec` mezősorrend alfabetikus rendezés (45 fájl, `yq sort_keys`) | ✅ kész |
| `metadata.namespace: flux-system` explicit megőrzése minden ks.yaml-ben (átmeneti) | ✅ kész — később Step 9 keretében visszafordítva |
| `flux-system/addons/ks.yaml` igazítása konvencióhoz (commonMetadata.labels, interval 30m→1h, timeout 3m→5m, retryInterval drop) | ✅ kész |
| `kube-system/kustomization.yaml` resource ordering: namespace.yaml első helyre | ✅ kész |
| **`cluster-settings` ConfigMap eltüntetése** — 4 halott változó törölve, 4 RFC1918 IP hardcodeolva (CONF_NFS_SRV_IP, LB_ENVOY_INTERNAL_IP, LB_K8S_GATEWAY_IP, LB_MEDIASERVER_IP) | ✅ kész |
| **`PUBLIC_DOMAIN` hardcodeolása** (32 fájl) + CLAUDE.md policy módosítás (bjw-s/onedr0p/buroa minta — public domain nem secret, DNS/TLS/Cloudflare publikus) | ✅ kész |
| **`SECRET_QBITTORRENT_PW` migráció** ExternalSecret-re — initContainer secret-mount + append pattern | ✅ kész — ⚠ 1Password item `qbittorrent` (vault: HomeOps, field: `password_pbkdf2`) bootstrap előtt létre kell hozni |
| **`cluster-secrets.sops.yaml` törlése + `kubernetes/flux/vars/` mappa törlése** | ✅ kész |
| **cluster-apps root egyszerűsítése** — `cluster-vars` Kustomization eltüntetve, substituteFrom patch teljesen eltávolítva, marad SOPS decryption + HelmRelease defaults patch | ✅ kész |
| Megszűnő apps eltávolítása (`tigera-operator`, `metallb`, `metallb-config`, `system-upgrade-controller`, `system-upgrade-controller-plans`) | ✅ kész — egyik mappa sem létezik a `talos` branch-en |
| Új `flux-operator` + `flux-instance` app-subtree-k létrehozása | ✅ kész |
| **Step 9** — Kustomization CR-ek kiköltöztetése `flux-system`-ből workload ns-ekbe: `namespace: <ns>` direktíva 8 apps/<ns>/kustomization.yaml-be, metadata.namespace strip 45 ks.yaml-ből, cross-ns dependsOn refek namespace mezővel | ✅ kész — bjw-s parity ELÉRVE: 52 KS elosztva 8 namespace-be (22 default, 8 kube-system, 7 networking, 5 flux-system, 3 volsync-system, 3 observability, 2 external-secrets, 2 cert-manager) |
| **flux-alerts component bevezetése** — per-ns Alert+Provider+ExternalSecret a `kubernetes/components/flux-alerts/`-ből, minden apps/<ns>/kustomization.yaml `components: [../../components/flux-alerts]`-tel; régi apps/flux-system/addons/alerts/pushover/ törölve | ✅ kész |
| **namespace.yaml `name: _` placeholder** átállítás (bjw-s/onedr0p minta) — kustomize directive helyettesíti a workload-ns nevével | ✅ kész |
| **flux-instance HR Helm cache patch eltávolítása** — 0 HelmRepository CR (csak OCIRepo), NOOP volt | ✅ kész |
| **Homepage `secret.sops.yaml` → ExternalSecret migráció** — 4 multi-line YAML mező a 1Password `homepage-config` item-ben, `externalsecret-config-files.yaml` template-szel renderel 9-mezős `homepage-config-files-secret`-et | ✅ kész — ⚠ 1Password item `homepage-config` (vault: HomeOps, mezők: `kubernetes_yaml`, `services_yaml`, `settings_yaml`, `widgets_yaml`) bootstrap előtt létre kell hozni |
| **cluster-apps root SOPS-eltüntetés** — `decryption: sops` spec ÉS injektáló patch is törölve (utolsó SOPS runtime resource a homepage volt) | ✅ kész |
| Egyéb új apps: `tuppr` (system upgrade Talos-ra) | ⏸ Phase 6 |

Az aktuális 41 Flux Kustomization név (rövid alak): `actual, bazarr, calibre-web-automated, cert-manager, cert-manager-issuers, cilium, cilium-config, cloudflare-tunnel, democratic-csi, echo, envoy-gateway, envoy-gateway-certificate, envoy-gateway-config, external-dns, external-secrets, flux-alerts, flux-provider-pushover, flux-webhooks, grafana, home-gallery, homepage, isponsorblocktv, k8s-gateway, kopia, kube-prometheus-stack, maintainerr, mealie, metallb, metallb-config, metrics-server, onepassword-connect, onepassword-store, paperless, paperless-gpt, plex, plex-trakt-sync, prowlarr, qbittorrent, qbittorrent-upgrade-p2pblocklist, radarr, reloader, restic-gui, resticprofile, seerr, snapshot-controller, sonarr, speedtest-exporter, subsyncarr, system-upgrade-controller, system-upgrade-controller-plans, tigera-operator, volsync, volsync-maintenance, wallos`.

## Cél

A jelenlegi `kubernetes/apps/<ns>/<app>/` szerkezet **alapja már jó** (megegyezik a bjw-s `ks.yaml + app/` mintával), de **két ponton refaktorálni kell**:

1. **Kustomization név**: `cluster-apps-<app>` → `<app>` (bjw-s konvenció).
2. **GitRepository név**: `home-ops-kubernetes` → `flux-system` (FluxInstance default).
3. **Namespace szervezés** kisebb átrendezések.
4. **Megszűnő apps**: `tigera-operator`, `metallb`, `system-upgrade-controller`.
5. **Új apps**: `flux-operator`, `flux-instance`, `tuppr` (system upgrade), `democratic-csi` (ha még nincs külön).

## Inputs

- `talos` branch létrehozva a main-ből.
- Flux Operator + FluxInstance működik új clusteren (lásd [05-flux-operator.md](./05-flux-operator.md)).
- A GitRepository neve `flux-system` (FluxInstance auto-generálja).

## Jelenlegi → új mapping (Kustomization név)

A jelenlegi minta (példa Plex):
```yaml
metadata:
  name: cluster-apps-plex                       # régi
spec:
  sourceRef:
    kind: GitRepository
    name: home-ops-kubernetes                   # régi
```

Új minta:
```yaml
metadata:
  name: plex                                    # új — kustomization név
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: flux-system                           # új — Flux Operator GitRepository neve
    namespace: flux-system
```

A `dependsOn:` listák is frissítendők (`cluster-apps-onepassword-store` → `onepassword-connect`, stb.).

## Kötelező ks.yaml minta — referenciákhoz illeszkedő

A bjw-s konvenció szerint (Step 9 után ELÉRVE):
- **NINCS** `metadata.namespace` a ks.yaml-ekben — a `kustomize` directive `namespace: <ns>` (apps/<ns>/kustomization.yaml-ben) injektálja workload-ns-be a Flux Kustomization CR-eket. A Namespace resource neve egyezik a direktíva értékével (`name: <ns>` matches `namespace: <ns>` → kustomize transformer no-op a Namespace-re).
- **Cross-namespace dependsOn** esetén kötelező az explicit `namespace:` mező a dependsOn item-en:
  ```yaml
  dependsOn:
    - name: onepassword-connect
      namespace: external-secrets
  ```
  Same-ns dependsOn-nál nincs namespace mező.
- **NINCS** YAML anchor (`&app`/`*app`) — a nevet kétszer ismételjük plain szöveggel (egyszer `metadata.name`, egyszer `commonMetadata.labels`).
- **NINCS** `retryInterval` explicit (controller default ~30s elég).
- `wait: false` default — csak akkor `true`, ha valami másik Kustomization explicit `dependsOn`-nal a Ready-re vár (pl. Cilium HR-jét).
- `prune: true` default — kivételek: Cilium app, cluster-secrets (substituteFrom függő erőforrások) ahol `prune: false` (CNI/Secret törlése veszélyes).
- `dependsOn` legitim, ha valós erőforrás-függőség áll mögötte (pl. `onepassword-connect` mielőtt egy ExternalSecret reconcile-ol, `cert-manager-issuers` mielőtt egy Certificate kiállítódik, `kube-prometheus-stack` mielőtt Grafana a datasource-t kéri).
- Mezősorrend a `spec`-en belül **alfabetikus** (bjw-s konvenció, `kustomization_v1.json` schema szerint).

**Single-stage app** (legtöbb):

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.bjw-s.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <APP_NAME>
  # metadata.namespace NINCS — apps/<ns>/kustomization.yaml `namespace: <ns>` direktívája injektálja
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: <APP_NAME>
  interval: 1h
  path: ./kubernetes/apps/<TARGET_NAMESPACE>/<APP_NAME>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: <TARGET_NAMESPACE>
  timeout: 5m
  wait: false
```

**VolSync-os app** (PVC-vel):

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <APP_NAME>
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: <APP_NAME>
  components:
    - ../../../../components/volsync
  interval: 1h
  path: ./kubernetes/apps/<TARGET_NAMESPACE>/<APP_NAME>/app
  postBuild:
    substitute:
      APP: <APP_NAME>
      VOLSYNC_CAPACITY: 5Gi
      VOLSYNC_CACHE: 2Gi
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: <TARGET_NAMESPACE>
  timeout: 5m
  wait: false
```

A `dependsOn:` mezőt **csak valós futásidejű függőség** esetén tegyük be (pl. onepassword-connect ClusterSecretStore, kube-prometheus-stack Prometheus datasource, cert-manager-issuers Certificate kibocsátáshoz). A retry loop magától megoldja a "csak késés" típusú konfliktusokat, de bootstrap-kor az explicit ordering csökkenti az initial reconcile zajt.

**Kétstage app** (HelmRelease + utána config CR, pl. cilium, envoy-gateway):

```yaml
---
# Stage 1: HelmRelease deploy
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
  namespace: flux-system
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: cilium
  interval: 1h
  path: ./kubernetes/apps/kube-system/cilium/app
  prune: false                                  # CNI: SOHA prune
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: kube-system
  timeout: 5m
  wait: true                                    # CRD-k léte garantált a következő stage-hez
---
# Stage 2: Config CR-k (IPPool, L2 Policy)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium-config
  namespace: flux-system
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

Figyeld: a second stage `app.kubernetes.io/component: config` extra labelt is kap. Ez bjw-s konvenció.

## App inventory — refactor mapping

A jelenlegi és új állapot az alábbi táblázatban:

### Default namespace (18 app)

| App | PVC | VolSync | ExternalSecret | Cutover megjegyzés |
|---|---|---|---|---|
| actual | ✓ | ✓ | - | VolSync restore |
| bazarr | ✓ | ✓ | - | VolSync restore |
| calibre-web-automated | ✓ | ✓ | - | VolSync restore |
| home-gallery | - | - | - | nincs adat — friss install |
| homepage | - | - | ✓ | ExternalSecret újragenerálódik |
| isponsorblocktv | ✓ | ✓ | - | VolSync restore |
| maintainerr | ✓ | ✓ | - | VolSync restore |
| mealie | ✓ | ✓ | ✓ | VolSync restore + ES |
| paperless | ✓ | ✓ | ✓ | VolSync restore + ES + app-level export |
| plex | ✓ | ✓ | ✓ | VolSync restore + ES (iGPU device mount NEM most — phase 2) |
| prowlarr | ✓ | ✓ | - | VolSync restore |
| qbittorrent | ✓ | ✓ | - | VolSync restore |
| radarr | ✓ | ✓ | - | VolSync restore |
| resticprofile | ✓ | ✓ | ✓ | VolSync restore + ES |
| seerr | ✓ | ✓ | - | VolSync restore |
| sonarr | ✓ | ✓ | - | VolSync restore |
| subsyncarr | - | - | - | friss install |
| wallos | ✓ | ✓ | - | VolSync restore |

### Platform apps (per namespace)

| Namespace | App | Cutover megjegyzés |
|---|---|---|
| cert-manager | cert-manager | helmfile bootstrap-ben jön, **app/-ban** managed |
| networking | cloudflare-tunnel | megőrzött, ES-szel |
| networking | echo | megőrzött (debug) |
| networking | envoy-gateway | megőrzött, 2-stage (app + gateway) |
| networking | external-dns | megőrzött |
| networking | k8s-gateway | megőrzött (split-DNS) |
| networking | **metallb** | **TÖRÖL** — Cilium L2 váltja le |
| external-secrets | external-secrets | helmfile bootstrap, **app/-ban** managed |
| external-secrets | onepassword-connect | helmfile bootstrap, **app/-ban** managed + ClusterSecretStore |
| kube-system | **cilium** | **ÚJ** — helmfile bootstrap + app/ managed + config/ |
| kube-system | **coredns** | **ÚJ** — Talos default disabled, Helm-en jön |
| kube-system | democratic-csi | megőrzött (vagy first install ha még nincs külön) |
| kube-system | metrics-server | megőrzött |
| kube-system | reloader | megőrzött |
| kube-system | snapshot-controller | megőrzött |
| observability | grafana | megőrzött |
| observability | kube-prometheus-stack | megőrzött |
| observability | speedtest-exporter | megőrzött |
| volsync-system | kopia | megőrzött |
| volsync-system | volsync | megőrzött |
| system-upgrade | **system-upgrade-controller** | **TÖRÖL** — Tuppr váltja le |
| system-upgrade | **tuppr** | **ÚJ** (lásd alább) |
| **tigera-operator** | tigera-operator | **TÖRÖL** — Cilium váltja le, namespace is törlődik |
| flux-system | **flux-operator** | **ÚJ** |
| flux-system | **flux-instance** | **ÚJ** |
| flux-system | addons (alerts, webhooks) | megőrzött |
| flux-system | flux-provider-pushover | megőrzött |

### Új namespace lista (rendezve)

```
kubernetes/apps/
├── cert-manager/
├── default/
├── external-secrets/
├── flux-system/
├── kube-system/
├── networking/
├── observability/
├── system-upgrade/
└── volsync-system/
```

`tigera-operator` namespace **megszűnik**.

## Példa: app refactor — Plex

### Régi `ks.yaml` (`kubernetes/apps/default/plex/ks.yaml`)

```yaml
metadata:
  name: cluster-apps-plex
  namespace: flux-system
spec:
  dependsOn:
    - name: cluster-apps-onepassword-store
    - name: cluster-apps-democratic-csi
  path: ./kubernetes/apps/default/plex/app
  sourceRef:
    name: home-ops-kubernetes
  targetNamespace: default
  components:
    - ../../../../components/volsync
  postBuild:
    substitute:
      APP: plex
      VOLSYNC_CAPACITY: "5Gi"
      VOLSYNC_CACHE: "2Gi"
```

### Új `ks.yaml`

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.bjw-s.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: plex
  namespace: flux-system
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: plex
  components:
    - ../../../../components/volsync
  dependsOn:
    - name: onepassword-connect
    - name: democratic-csi
  interval: 1h
  path: ./kubernetes/apps/default/plex/app
  postBuild:
    substitute:
      APP: plex
      VOLSYNC_CAPACITY: "5Gi"
      VOLSYNC_CACHE: "2Gi"
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: default
  timeout: 5m
  wait: false
```

Változások:
- `metadata.name`: `cluster-apps-plex` → `plex` (referencia konvenció)
- `metadata.namespace: flux-system` **megőrizve** — a substituteFrom (`cluster-settings`/`cluster-secrets`) a flux-system namespace-beli resource-okat kéri, ezért minden child Kustomization-nek ott kell léteznie. A bjw-s "parent öröklés" minta nem kompatibilis ezzel.
- `sourceRef.name`: `home-ops-kubernetes` → `flux-system` (FluxInstance default GitRepo név)
- `sourceRef.namespace: flux-system` explicit
- `commonMetadata.labels.app.kubernetes.io/name: plex` hozzáadva
- `dependsOn` **megtartva** — az `onepassword-connect` ClusterSecretStore és a `democratic-csi` StorageClass mindkettő Flux-szel reconcile-olódik (nem helmfile bootstrap-ből), ezért bootstrap idején tényleges resource-függőség. A retry loop kezelné a végén, de az explicit ordering csökkenti az initial reconcile zajt.
- Mezősorrend alfabetikus a `spec`-en belül.
- Mezősorrend alfabetikus (bjw-s konvenció kustomization_v1.json schema rendezést követ).

A Plex `helmrelease.yaml` **változatlan** — Hardware Transcoding most nem kerül bevezetésre (eddig sem volt). A Talos `i915` extension a schematic-ban benn marad jövőbeni lehetőségként, de a Plex pod-spec nem kap `/dev/dri` mount-ot.

## Új app: Tuppr (system-upgrade)

[Tuppr](https://github.com/bjw-s-labs/tuppr) — Talos-natív node frissítés. Lecseréli a `system-upgrade-controller` (SUC) app-ot.

**Fájl-layout:**
```
kubernetes/apps/system-upgrade/tuppr/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml
    └── ocirepository.yaml
```

**bjw-s `tuppr/ks.yaml`** mint példa (átemelve):
```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app tuppr
  namespace: &namespace flux-system
spec:
  targetNamespace: system-upgrade
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/apps/system-upgrade/tuppr/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: *namespace
  wait: false
  interval: 1h
  retryInterval: 2m
  timeout: 5m
```

A `helmrelease.yaml` Tuppr Helm chart-ot install-ál és a Talos `Plan` resource-ot deklaratíve menedzseli.

A jelenlegi `system-upgrade-controller` `Plan` resource-ok **NEM migrálnak át** — új Tuppr `Plan`-okat kell írni.

## Új app: democratic-csi (ha még nem külön)

A jelenlegi `democratic-csi` valószínűleg már megvan a `kube-system`-ben — ellenőrizd:

```bash
ls kubernetes/apps/kube-system/democratic-csi/ 2>/dev/null
```

Ha nincs, akkor [bjw-s democratic-csi-local-hostpath mintát](https://github.com/bjw-s-labs/home-ops/tree/main/kubernetes/apps/kube-system/democratic-csi-local-hostpath) követve hozzá kell adni:

**Fájl-layout:**
```
kubernetes/apps/kube-system/democratic-csi-local-hostpath/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml
    └── ocirepository.yaml
```

A `helmrelease.yaml` értékek: `hostPathDir: /var/mnt/local-hostpath` (Talos UserVolume mount — a `local-hostpath` UserVolume nevéből származó path).

## Namespace szervezés — bjw-s mintába illeszkedés

A bjw-s repo finomabb namespace bontást használ (`media`, `home-automation`, `selfhosted`, `downloads` stb.). **Mi most NEM bontjuk szét** a `default`-ot, mert:
- 18 app `default`-ban kezelhető.
- A bontás cutover-rel egyszerre overkill — egy projekt, egy fókusz.
- Később (cutover után) megfontolandó: `media` (Plex, Sonarr, Radarr, Bazarr, Prowlarr, Seerr, Maintainerr, qbittorrent, isponsorblocktv, calibre-web-automated, subsyncarr, home-gallery), `productivity` (Paperless, Mealie, Actual, Wallos, Homepage), `system` (resticprofile).

Most az új cluster-en **megtartjuk a `default`-ot** mint single bucket. Refactor a cutover után, külön branch-en.

## Refactor migráció batch-ek

A refaktort branch-en végezzük (`talos`), batch-ekben. Egy batch = egy commit:

### Batch 1: Új apps (előzetes)
- `kubernetes/apps/flux-system/flux-operator/` + `flux-instance/`
- `kubernetes/apps/kube-system/cilium/` + `coredns/`
- `kubernetes/apps/kube-system/democratic-csi-local-hostpath/` (ha új)
- `kubernetes/apps/system-upgrade/tuppr/`

### Batch 2: Megszűnő apps törlés
- `kubernetes/apps/tigera-operator/` **teljes mappa törlés**
- `kubernetes/apps/networking/metallb/` **teljes mappa törlés**
- `kubernetes/apps/system-upgrade/system-upgrade-controller/` **mappa törlés** (ha külön mappa)
- `kubernetes/apps/kustomization.yaml` — referenciák törlése (`- ./tigera-operator` sor)
- `kubernetes/apps/networking/kustomization.yaml` — `- ./metallb/ks.yaml` sor törlés

### Batch 3: Kustomization name refactor (script-tel)
Script futtatás (lásd alább) ami minden `ks.yaml`-en végigmegy:
```bash
# A folder név alapján rename-li a metadata.name-et
just k8s refactor-ks-names
```

(A `just` recipe-t megírjuk — `find` + `yq` lánccal.)

### Batch 4: GitRepository név refactor
```bash
# minden ks.yaml sourceRef.name: home-ops-kubernetes → flux-system
find kubernetes/apps -name "ks.yaml" -exec yq -i '.spec.sourceRef.name = "flux-system"' {} \;
find kubernetes/apps -name "ks.yaml" -exec yq -i '.spec.sourceRef.namespace = "flux-system"' {} \;
```

### Batch 5: dependsOn refactor
Manuálisan — a `dependsOn:` listák `cluster-apps-X` referenciáit `X`-re átírni, és **felülvizsgálni**, hogy szükségesek-e még (sok kiesik, mert helmfile bootstrap kezeli).

### Batch 6: (SKIPPED — Plex iGPU passthrough most NEM kerül bevezetésre)
Eddig sem volt a Plex-nek hardware transcode konfigurálva, ezért a migráció során sem adunk neki. Ha később bevezetjük: külön projekt, lásd phase 2 a [15-post-cutover.md](./15-post-cutover.md)-ben.

### Batch 7: cluster-settings.yaml frissítés
- `kubernetes/flux/vars/cluster-settings.yaml`:
  - `CLUSTER_POD_CIDR`: `10.244.0.0/16` (változás: `10.42` → `10.244`)
  - `CLUSTER_SVC_CIDR`: `10.245.0.0/16` (változás: `10.43` → `10.245`)
  - `CLUSTER_NODE_1_CIDR`: `192.168.1.11/32` (változás: `.6` → `.11`)
  - `LB_ENVOY_INTERNAL_IP`: `192.168.1.18` (változatlan)
  - `LB_K8S_GATEWAY_IP`: `192.168.1.19` (változatlan)
  - `LB_MEDIASERVER_IP`: `192.168.1.20` (változatlan)

## Refactor helper script (just recipe)

Az `kubernetes/mod.just`-be (lásd [08-just-migration.md](./08-just-migration.md)):

```just
[doc('Refactor: rename Flux Kustomization names from cluster-apps-X to X (idempotent)')]
[script]
refactor-ks-names:
    find "{{ kubernetes_dir }}/apps" -name "ks.yaml" | while read -r f; do
      app_name=$(basename "$(dirname "$f")")
      yq -i ".metadata.name = \"$app_name\"" "$f"
      just log info "Renamed" "file" "$f" "name" "$app_name"
    done
```

A `dependsOn:` listák refactor-jához:

```just
[doc('Refactor: dependsOn references from cluster-apps-X to X')]
[script]
refactor-dependson:
    find "{{ kubernetes_dir }}/apps" -name "ks.yaml" | while read -r f; do
      yq -i '(.spec.dependsOn[]?.name) |= sub("^cluster-apps-"; "")' "$f"
    done
```

## Validation

```bash
# Minden ks.yaml új formátumban:
grep -L "name: cluster-apps-" kubernetes/apps/**/ks.yaml | wc -l
# == teljes ks.yaml szám

# Minden ks.yaml jó sourceRef-fel:
grep -l "name: home-ops-kubernetes" kubernetes/apps/**/ks.yaml
# == 0 (nincs maradék)

# Flux dry-run reconcile:
flux build kustomization cluster-apps --path kubernetes/flux/cluster --kustomization-file kubernetes/flux/cluster/ks.yaml
```

Az új cluster-en `flux get kustomizations` után minden `Ready=True` kell legyen.

## Rollback

A refactor lokálisan történik a `talos` branch-en — ha valami félresikerül:
```bash
git checkout talos
git diff main -- kubernetes/apps/
# áttekintés
git reset --hard <previous-commit>
```

Cluster-on a régi (`main` branch) `home-ops-kubernetes` GitRepository-vel reconcile-olja — semmi nem törik.

## Open issues

- **`commonMetadata.labels: app.kubernetes.io/name`** anchor használat (`&app`/`*app`): YAML anchorrel a `metadata.name` és a `labels.app.kubernetes.io/name` szinkronban marad. Régi ks.yaml-ekben nincs ez a label — felvesszük.
- **A democratic-csi storage class név**: jelenleg `democratic-csi-local-hostpath`. Új clusteren ugyanaz a név, az app-ok `helmrelease.yaml`-ben hivatkozott `storageClassName`-ek változatlanok.
- **plex-trakt-sync sub-Kustomization**: a jelenlegi Plex egy plusz `trakt-sync/` mappát is tartalmaz, külön Kustomization-nel. Refactor-ban ez ugyanúgy megmarad — `plex-trakt-sync` névvel.
- **Cutover-ig a main branch változatlan**: a refactor csak a `talos` branch-en él. Main-en a régi struktúra fut (régi cluster).
- **K8s 1.36 compatibility**: minden HelmRelease chart verzió kompatibilis kell legyen K8s 1.36.x-szel. Renovate-tel a frissítések érkeznek, de cutover ELŐTT ellenőrizd, hogy nincs régóta nem update-elt chart, ami breaking-be ütközne.
