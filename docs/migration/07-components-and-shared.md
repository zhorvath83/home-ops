# 07 — Components és shared resources

## Cél

A `kubernetes/components/` újrahasznosítható darabok strukturálása + a shared `cluster-secrets` / `cluster-settings` minta finomítása az új clusterre.

## Inputs

- Flux Operator + FluxInstance működik, a `cluster-apps` Kustomization minden Flux Kustomization-be injektálja a SOPS dekripciót és substitueFrom-ot (lásd [05-flux-operator.md](./05-flux-operator.md)).
- A jelenlegi `kubernetes/components/volsync/` 5 fájllal megvan (kustomization, externalsecret, pvc, replicationsource, replicationdestination).

## Jelenlegi components — megőrzött

```
kubernetes/components/
└── volsync/
    ├── kustomization.yaml
    ├── externalsecret.yaml
    ├── pvc.yaml
    ├── replicationsource.yaml
    └── replicationdestination.yaml             # most kikommentelve, bootstrap restore-hoz
```

Ez **változatlanul átkerül** az új clusterre. A komponens postBuild substitute változókkal paraméterezett, app-onként testreszabható.

## Hogyan dolgozik a volsync component

Egy app `ks.yaml`-ben:
```yaml
components:
  - ../../../../components/volsync
postBuild:
  substitute:
    APP: plex
    VOLSYNC_CAPACITY: "5Gi"
    VOLSYNC_CACHE: "2Gi"
    APP_UID: "568"                              # opcionális, default 10001
    APP_GID: "568"                              # opcionális, default 10001
```

A komponens kibővíti az adott Flux Kustomization manifest-jét **3 új resource-szal**:
1. **PVC** — `${APP}` névvel, `democratic-csi-local-hostpath` storage class-szal.
2. **ExternalSecret** — `${APP}-volsync` névvel, Kopia + S3 creds-eket szállít.
3. **ReplicationSource** — `${APP}` névvel, napi 2:00 schedule, Kopia mover, zstd-fastest compression, 7 daily/2 weekly/1 monthly retention.

A **ReplicationDestination** (`${APP}-bootstrap`) ki van kommentelve a `kustomization.yaml`-ben — bootstrap restore-hoz kell, lásd alább.

## Bootstrap restore flow (új clusteren)

Az új clusteren minden PVC-t **0-ról** kell létrehozni az OVH-n tárolt Kopia snapshot-ból. Ehhez a `replicationdestination.yaml`-t **be kell kapcsolni** a komponens kustomization-ben:

**Fájl:** `kubernetes/components/volsync/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - ./externalsecret.yaml
  - ./pvc.yaml
  - ./replicationdestination.yaml               # BE-kapcsolva új clusteren!
  - ./replicationsource.yaml
```

Ezzel egyszerre minden volsync-os app létrehozza:
- A `${APP}-bootstrap` `ReplicationDestination`-t — manuálisan trigger-elhető (`manual: restore-once`).
- A PVC-t (a kommentelt `dataSourceRef` is be lesz kapcsolva — lásd alább).

**A `pvc.yaml`-ben** is kell egy módosítás cutover idejére:

```yaml
spec:
  accessModes:
    - "${VOLSYNC_ACCESSMODES:=ReadWriteOnce}"
  dataSourceRef:                                # BE-kapcsolva új clusteren!
    kind: ReplicationDestination
    apiGroup: volsync.backube
    name: "${APP}-bootstrap"
  resources:
    requests:
      storage: "${VOLSYNC_CAPACITY:=1Gi}"
  storageClassName: "${VOLSYNC_STORAGECLASS:=democratic-csi-local-hostpath}"
```

A `dataSourceRef` azt jelenti, hogy az új PVC tartalma **a `${APP}-bootstrap` ReplicationDestination snapshot-ból kerül feltöltésre**.

**Workflow**:
1. Cutover ELŐTT: a két kommentet feloldjuk a komponens-ben — push a `talos` branch-re.
2. Cluster reconcile: a Flux létrehozza minden volsync-os app-nak a `${APP}-bootstrap` RD-t (még nem fut).
3. Régi clusteren utolsó snapshot OVH-ra (manual VolSync snapshot trigger).
4. Új clusteren: minden RD-t **manuális trigger** indítja → letölti az OVH-ról a snapshot-ot.
5. Az RD befejezi → új PVC-k a snapshot tartalmával létrejönnek.
6. Az app pod-ok elindulnak a populated PVC-kel.
7. Cutover UTÁN: a két komment vissza-kommentelhető (a bootstrap RD-k törlődnek, csak a runtime RS marad). VAGY hagyjuk benn (a `manual: restore-once` triggerre vár, nem fut).

A részleteket a [11-data-migration.md](./11-data-migration.md) tartalmazza app-onként.

## Components inventory — három referencia repo összehasonlítva

Részletes kutatás alapján:

| Component | bjw-s | onedr0p | buroa | Mit csinál | Cél a te setup-odhoz |
|---|---|---|---|---|---|
| **volsync** | ✅ | ✅ | ✅ | Per-app Kopia backup (ExternalSecret + PVC + RS + RD) | **MEGTARTÁS** — már megvan |
| **zeroscaler** | ✅ | ✅ | ✅ | Scale-to-zero HPA blackbox NFS probe metric alapján — ha NAS offline, az NFS-függő pod-ok 0-ra skáláznak | **Phase 2** (NAS redundancia szempontból érdekes) |
| **flux-alerts** | ✅ (`flux-alerts/`) | ✅ (`alerts/`) | ✅ (`namespace/alerts/`) | Per-app Flux Alert + Provider — app-szintű notification | **Phase 2** opcionálisan |
| **github-status** | ❌ | ✅ | ✅ | Flux Kustomization eredményt GitHub commit status-ként | **Nem szükséges** |
| **gpu** (DRA) | ✅ | ❌ | ❌ | Intel iGPU ResourceClaimTemplate (K8s 1.32+ DRA) | **Nem most** (Plex iGPU egyelőre kihagyva) |
| **anubis** | ✅ | ❌ | ❌ | Anti-bot challenge proxy | **Nem szükséges** |
| **dragonfly** | ✅ | ❌ | ❌ | Per-app Dragonfly (Redis-kompatibilis) cache | **Nem szükséges** |
| **namespace** | ❌ | ❌ | ✅ | Per-app namespace + alert bundle, `name: _` placeholder | **Nem szükséges** (cluster-szintű namespace létrehozás működik) |

A jelenlegi `kubernetes/components/volsync/` változatlanul használható (megfelel a három referencia mintáinak).

## Részletes elemzés a "miért nem ment" kérdésre

A user korábban próbálta a components patterns-t bevezetni, de a "alapvető különbségek" megakasztották. A főbb akadályok lehetnek:

### Akadály #1: bjw-s `kubernetes/flux/` minimalizmus vs jelenlegi `cluster-settings`/`cluster-secrets` minta

**bjw-s tényleges állapota**: a `kubernetes/flux/` mappában **egyetlen fájl** van (`cluster/ks.yaml`), és **NINCS** `vars/` mappa. **NINCS** `cluster-settings.yaml` ConfigMap, **NINCS** `cluster-secrets.sops.yaml` Secret. A Helm values-ok közvetlenül az app `helmrelease.yaml`-ben élnek, és a bootstrap a `values.yaml.gotmpl` trükkkel olvas onnan.

**Jelenlegi setup**: `kubernetes/flux/vars/cluster-settings.yaml` + `cluster-secrets.sops.yaml`, minden Kustomization `postBuild.substituteFrom: [cluster-settings, cluster-secrets]`-ot kap (cluster-apps root patch-ben injektálva).

**Ez két INKOMPATIBILIS minta.** Ha tisztán bjw-s-stílusra váltunk, **eltűnik a substituteFrom**, és minden app HelmRelease-ben **közvetlenül** kell hivatkozni a domain-re, NFS IP-re stb. Ez major refaktor minden app-ban.

**Javaslat**: a jelenlegi `cluster-settings`/`cluster-secrets` mintát **megőrizzük** — onedr0p és buroa is ezt használja. Csak a bjw-s minimalista. Az értékeket NEM kell elveszíteni.

### Akadály #2: `cluster-secrets.sops.yaml` tartalmi különbség

bjw-s NEM használ `cluster-secrets.sops.yaml`-t — minden runtime secret ExternalSecret-en keresztül jön 1Password-ből. A jelenlegi te repód viszont SOPS-titkosítva tárol cluster-szintű secret-eket (`PUBLIC_DOMAIN`, `SECRET_QBITTORRENT_PW`).

**Ez OK**: a jelenlegi minta működik, és az ExternalSecret-en kívül egy másik tier-ben élnek a "build-time" secret-ek (substitueFrom-on át beépítve a manifesteknbe). Ez **nem rossz minta** — csak más, mint bjw-s.

### Akadály #3: Component név-konvenció

bjw-s a komponensekben `${APP}-volsync`, `${APP}-anubis`, `${APP}-dragonfly` formátumot használ — egy app több komponensre is feliratkozhat, és mindegyik komponens "saját nevű" resource-okat hoz létre.

A jelenlegi `kubernetes/components/volsync/` ezt **már jól csinálja** (`${APP}` substitute, `${APP}-volsync-secret`, stb.). Tehát itt nincs eltérés.

## Mit érdemes átvenni — konkrét lista

### Most (a cutover részeként)

1. ✅ **volsync** — már megvan, marad.
2. ❌ **Semmi más új component** — a cutover scope ne bővüljön.

### Phase 2 (cutover utáni 1-3 hónapban)

1. **flux-alerts** komponens — per-app Flux Alert. A jelenlegi cluster-szintű alert (`flux-system/addons/alerts/`) durva: minden HR/KS hibára azonos notification. App-szintű alerts (groupName tag-elve) jobb diagnosztika.
   - Hivatkozási pont: bjw-s `kubernetes/components/flux-alerts/`.
2. **zeroscaler** komponens — érdekes a NAS-függő app-okhoz (Plex, Sonarr, Radarr stb.). Ha az M93p NFS share-e időszakosan offline (pl. update miatt), a függő pod-ok scale 0-ra → nincs CrashLoopBackOff log spam.
   - Feltétel: blackbox-exporter telepítve van (jelenleg lehet, hogy a `speedtest-exporter` mellett már fut, de érdemes ellenőrizni).

### NEM tervezve

- **gpu** — Plex HW transcode nem cél.
- **anubis** — nincs bot-kockázat.
- **dragonfly** — nincs cache igény.
- **github-status** — overkill single-developer setup.

## Shared resources: cluster-settings + cluster-secrets

**Fontos megjegyzés**: a bjw-s repó **nem használja** ezt a mintát (csak egyetlen `cluster/ks.yaml` fájl a `flux/` alatt). Az onedr0p sem már (újabb átszervezés). A te setup-od ezt a `flux/vars/` mintát követi, és **változatlanul megőrizzük** mindkettőt — a SOPS-titkosított `cluster-secrets.sops.yaml` és a plain `cluster-settings.yaml` is. Egy későbbi projekt feladat eldönteni, hogy 1Password ExternalSecret-re migráljuk-e (ld. doc végén "Open issues").

A `kubernetes/flux/vars/` tartalma az új clusteren:

### `kubernetes/flux/vars/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./cluster-settings.yaml
  - ./cluster-secrets.sops.yaml
```

### `kubernetes/flux/vars/cluster-settings.yaml`

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: flux-system
  name: cluster-settings
data:
  # Networking
  CLUSTER_POD_CIDR: "10.244.0.0/16"
  CLUSTER_SVC_CIDR: "10.245.0.0/16"
  CLUSTER_NODE_1_CIDR: "192.168.1.11/32"

  # LoadBalancer pool (Cilium L2)
  LB_POOL_RANGE_START: "192.168.1.15"
  LB_POOL_RANGE_END: "192.168.1.25"

  # Service VIP-ek — változatlan (megegyezik a jelenlegi MetalLB allokációval)
  LB_ENVOY_INTERNAL_IP: "192.168.1.18"
  LB_K8S_GATEWAY_IP: "192.168.1.19"
  LB_MEDIASERVER_IP: "192.168.1.20"

  # NFS server
  CONF_NFS_SRV_IP: "192.168.1.10"
```

A jelenlegihez képest **csak a node IP változik**: `.6` (régi K3s) → `.11` (új HP Talos). A LB IP-k a `.15-.25` tartományban kerülnek allokálásra, ezen belül a meglévő `.18/.19/.20` szolgáltatás IP-i változatlanok. Az `envoy-external` Gateway nem kap LAN LB IP-t (Cloudflare Tunnel ClusterIP-n keresztül megy ki).

### `kubernetes/flux/vars/cluster-secrets.sops.yaml` — **megmarad SOPS-ban**

A jelenlegi SOPS-titkosított Secret változatlanul átkerül az új clusterre. **Tartalma (két field)**:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-secrets
  namespace: flux-system
stringData:
  PUBLIC_DOMAIN: <encrypted>
  SECRET_QBITTORRENT_PW: <encrypted>
```

- `PUBLIC_DOMAIN`: a publikus DNS zone név (Cloudflare-managelt domain), 25+ manifest-ben `${PUBLIC_DOMAIN}` substituteFrom-mal hivatkozott.
- `SECRET_QBITTORRENT_PW`: a qBittorrent web UI admin PBKDF2 jelszava, a `qBittorrent.conf` ConfigMap-renderingben felhasznált.

**Cutover-kor** ennek a fájlnak a tartalma **változatlan** marad. A `.sops.yaml` age recipient-je is változatlan, így a fájl decrypt-elhető az új clusteren ugyanazzal az age private key-jel.

**1Password-re migráció**: külön projekt-feladat (post-cutover phase 2). Most a SOPS pattern működik, nem érintjük.

### Bootstrap időben a SOPS dekripció elérhetősége

Ahhoz, hogy a Flux a `cluster-secrets.sops.yaml`-t reconcile-on dekódolja, a `sops-age` Secret-nek léteznie kell a `flux-system` namespace-ben. Ezt a bootstrap **resources** stage hozza létre 1Password-ből `op inject`-tel — részletek a [04-bootstrap-helmfile.md](./04-bootstrap-helmfile.md) "SOPS bootstrap" szekcióban.

### `kubernetes/flux/vars/cluster-settings.yaml` — **megmarad**

## SOPS age key

Cluster bootstrap-kor a `sops-age` Secret-et a `flux-system` namespace-be kell injektálni — `op://Automation/sops-age/keys.txt`-ből. Részletek a [05-flux-operator.md](./05-flux-operator.md)-ben.

A `.sops.yaml` változatlan (`age1el7uu5gzqsdp8wz7y9mcpqsy08l894twxg0jm5cm0jps3hkp2veqdpn5az` continues).

## ClusterSecretStore (1Password) — runtime

A `kubernetes/apps/external-secrets/onepassword-connect/app/clustersecretstore.yaml` a runtime ClusterSecretStore-t definiálja:

```yaml
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepassword:
      connectHost: http://onepassword-connect.external-secrets.svc.cluster.local:8080
      vaults:
        Kubernetes: 1                          # main vault
        Automation: 2                          # bootstrap creds
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-connect-vault-secret
            key: token
            namespace: external-secrets
```

A `vaults:` lista a 1Password vault neveket és prioritásokat. **A jelenlegi vault setup-ot** megőrizzük.

## Validation

```bash
# Components reuse:
flux build kustomization plex --path kubernetes/flux/cluster --kustomization-file kubernetes/apps/default/plex/ks.yaml \
  | grep -E "kind: (PersistentVolumeClaim|ExternalSecret|ReplicationSource)"
# Mind a 3 megjelenik

# cluster-settings substitueFrom:
flux build kustomization plex --path kubernetes/flux/cluster --kustomization-file kubernetes/apps/default/plex/ks.yaml \
  | grep "192.168.1"
# A LB_*_IP értékek behelyettesítődnek

# Volsync ES:
kubectl -n default get es plex-volsync
# Ready=True, target Secret létrehozva
```

## Rollback

A components önmagukban nem törhetnek el — Flux Kustomization-ek hivatkoznak rájuk. Ha valami el van rontva:
1. Lokálisan `flux build` paranccsal renderelhető.
2. `git diff main -- kubernetes/components/` — milyen change ütött be.

A `replicationdestination.yaml` bekapcsolásakor (cutover idejére) az új clusteren ha a manifest hibás, csak az érintett app reconcile fail-el — más app-ok mennek tovább.

## Open issues

- **Bootstrap RD vs runtime RS schedule overlap**: ha mind a bootstrap RD, mind a runtime RS megfut egyszerre, a Kopia repository egy időben olvas+ír. Hivatalosan oké (Kopia konkurens), de cutover napon **ne hagyd véletlenül futni az RS-t** a régi clusteren ÉS az RD-t az újon egyszerre. A részletes timing a [12-cutover-runbook.md](./12-cutover-runbook.md)-ban.
- **`enableFileDeletion: true`** a RD-ben azt jelenti, hogy a snapshot tartalom **felülírja** a PVC tartalmat (törli a snapshot-ban nem szereplő fájlokat). Friss PVC esetén ez OK, de ha jövőben in-place restore kell, óvatosan.
- **`runAsUser/runAsGroup: 10001`** default — sok app-nak más UID/GID kell (Plex: 568, Sonarr: 1000 stb.). Az app `ks.yaml`-ben felülírjuk a `APP_UID`/`APP_GID` substitute-tel.
- **`volsync-template` 1Password item**: ennek kell tartalmaznia `KOPIA_S3_BUCKET` és `KOPIA_PASSWORD` mezőket. Jelenleg már megvan — változatlan.
- **`ovh` 1Password item**: `ovh_s3_access_key`, `ovh_s3_secret_key`, `ovh_s3_endpoint` — változatlan.
- **gatus/flux-alerts/dragonfly components** átemelése phase 2 — itt csak megemlítjük, hogy később hozzáadható.
