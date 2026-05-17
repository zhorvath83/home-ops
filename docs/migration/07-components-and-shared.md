# 07 — Components és shared resources

> **2026-05-17 — Frissítés**: a `cluster-settings` ConfigMap és `cluster-secrets` SOPS Secret **eltüntetve** (lásd doc 06 STATUS). A `kubernetes/flux/vars/` mappa törölve. A korábbi `${PUBLIC_DOMAIN}` substitution layer helyett a domain (`horvathzoltan.me`) **hardcoded** mindenhol (bjw-s/onedr0p/buroa minta). A `SECRET_QBITTORRENT_PW` ExternalSecret-re migrálva (1Password `qbittorrent` item, `password_pbkdf2` mező). A doc alábbi szekciói **historikus dokumentáció** — a tényleges futó állapot már nem substituteFrom-mintát követ.

## Cél

A `kubernetes/components/` újrahasznosítható darabok strukturálása + a shared `cluster-secrets` / `cluster-settings` minta finomítása az új clusterre.

## Inputs

- Flux Operator + FluxInstance működik, a `cluster-apps` Kustomization minden HelmRelease-be injektálja a default-okat (install/upgrade strategy, retries, timeout — lásd [05-flux-operator.md](./05-flux-operator.md)). Runtime SOPS és substituteFrom NINCS (Phase 6.7 után bjw-s parity).
- A jelenlegi `kubernetes/components/volsync/` 5 fájllal megvan (kustomization, externalsecret, pvc, replicationsource, replicationdestination).

## Jelenlegi components

```
kubernetes/components/
├── flux-alerts/                              # ÚJ — Step 9 után bevezetett, per-ns Alert+Provider+ExternalSecret
│   ├── kustomization.yaml                    # kind: Component
│   ├── externalsecret.yaml                   # 1Password "pushover" → flux-pushover-secret
│   ├── provider.yaml                         # type: generic, name: pushover
│   └── alert.yaml                            # eventSources GR/HR/HRepo/KS/OCIRepo "*"
└── volsync/
    ├── kustomization.yaml
    ├── externalsecret.yaml
    ├── pvc.yaml
    ├── replicationsource.yaml
    └── replicationdestination.yaml           # bootstrap-only manifest, `ssa: IfNotPresent` címkével permanensen aktiválva (manual: restore-once trigger)
```

A `volsync` component **változatlanul** átkerül az új clusterre. A `flux-alerts` component pedig minden `apps/<ns>/kustomization.yaml`-ből hivatkozva van (`components: [../../components/flux-alerts]`), így a 8 workload namespace mindegyike kap saját Alert+Provider+ExternalSecret hármast — per-ns notification coverage (a Step 9 utáni szétszórt KS/HR-ekhez).

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
| **flux-alerts** | ✅ (`flux-alerts/`) | ✅ (`alerts/`) | ✅ (`namespace/alerts/`) | Per-namespace Alert + Provider + ExternalSecret — workload-ns notification | **BEVEZETVE** — Step 9 után minden apps/<ns>/kustomization.yaml-ben `components: [../../components/flux-alerts]` |
| **github-status** | ❌ | ✅ | ✅ | Flux Kustomization eredményt GitHub commit status-ként | **Nem szükséges** |
| **gpu** (DRA) | ✅ | ❌ | ❌ | Intel iGPU ResourceClaimTemplate (K8s 1.32+ DRA) | **Nem most** (Plex iGPU egyelőre kihagyva) |
| **anubis** | ✅ | ❌ | ❌ | Anti-bot challenge proxy | **Nem szükséges** |
| **dragonfly** | ✅ | ❌ | ❌ | Per-app Dragonfly (Redis-kompatibilis) cache | **Nem szükséges** |
| **namespace** | ❌ | ❌ | ✅ | Per-app namespace + alert bundle, `name: _` placeholder | **Nem szükséges** (cluster-szintű namespace létrehozás működik) |

A jelenlegi `kubernetes/components/volsync/` változatlanul használható (megfelel a három referencia mintáinak).

## Részletes elemzés a "miért nem ment" kérdésre

> **Phase 6.7 — törlés**: az eredeti dokumentum három akadályt (kustomize-flux minimalizmus, `cluster-secrets.sops.yaml`, component név-konvenció) sorolt fel, amelyek a bjw-s parity-t megakadályozták. Phase 6.7 audit során mindhárom akadály megoldódott: a `vars/` mappa törölve, a runtime SOPS megszűnt (`PUBLIC_DOMAIN` hardcoded, `SECRET_QBITTORRENT_PW` ESO-n), a component név-konvenció (`${APP}-volsync-secret`) bevezetve. **A részletes akadály-elemzés mostantól értelmét vesztette** — lásd [06-repo-restructure.md](./06-repo-restructure.md) STATUS L20-32.

## Mit érdemes átvenni — konkrét lista

### Cutover részeként (elvégezve)

1. ✅ **volsync** — már megvan, marad. `ssa: IfNotPresent` címkével permanensen aktiválva (bjw-s minta, Phase 6.7).
2. ✅ **flux-alerts** komponens — per-namespace Alert+Provider+ExternalSecret, minden `apps/<ns>/kustomization.yaml`-ből hivatkozott (bevezetve Phase 6 Step 9).

### Phase 2 (cutover utáni 1-3 hónapban)

1. **zeroscaler** komponens — érdekes a NAS-függő app-okhoz (Plex, Sonarr, Radarr stb.). Ha az M93p NFS share-e időszakosan offline (pl. update miatt), a függő pod-ok scale 0-ra → nincs CrashLoopBackOff log spam.
   - Feltétel: blackbox-exporter telepítve van (jelenleg lehet, hogy a `speedtest-exporter` mellett már fut, de érdemes ellenőrizni).

### NEM tervezve

- **gpu** — Plex HW transcode nem cél.
- **anubis** — nincs bot-kockázat.
- **dragonfly** — nincs cache igény.
- **github-status** — overkill single-developer setup.

## ClusterSecretStore (1Password) — runtime

A `kubernetes/apps/external-secrets/onepassword-connect/app/clustersecretstore.yaml` a runtime ClusterSecretStore-t definiálja:

```yaml
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword-connect
spec:
  provider:
    onepassword:
      connectHost: http://onepassword-connect.external-secrets.svc.cluster.local:8080
      vaults:
        HomeOps: 1                             # single source vault for runtime + bootstrap items
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-connect-vault-secret
            key: token
            namespace: external-secrets
```

A `vaults:` listában csak a `HomeOps` vault szerepel — a tényleges setupban minden 1Password item (bootstrap creds, runtime app secrets, talos secrets, age key) ebben él. A `Kubernetes`/`Automation` névcsoport elképzelés a doc korábbi verziójában megjelent, de a tényleges repo Taskfile-ja (`.taskfiles/Flux/Tasks.yaml`) is `HomeOps`-ra mutat — egy vault elég.

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

- **Bootstrap RD vs runtime RS schedule overlap**: ha mind a bootstrap RD, mind a runtime RS megfut egyszerre, a Kopia repository egy időben olvas+ír. Hivatalosan oké (Kopia konkurens), de cutover napon **ne hagyd véletlenül futni az RS-t** a régi clusteren ÉS az RD-t az újon egyszerre. A részletes timing a [13-cutover-runbook.md](./13-cutover-runbook.md)-ban.
- **`enableFileDeletion: true`** a RD-ben azt jelenti, hogy a snapshot tartalom **felülírja** a PVC tartalmat (törli a snapshot-ban nem szereplő fájlokat). Friss PVC esetén ez OK, de ha jövőben in-place restore kell, óvatosan.
- **`runAsUser/runAsGroup: 10001`** default — sok app-nak más UID/GID kell (Plex: 568, Sonarr: 1000 stb.). Az app `ks.yaml`-ben felülírjuk a `APP_UID`/`APP_GID` substitute-tel.
- **`volsync-template` 1Password item**: ennek kell tartalmaznia `KOPIA_S3_BUCKET` és `KOPIA_PASSWORD` mezőket. Jelenleg már megvan — változatlan.
- **`ovh` 1Password item**: `ovh_s3_access_key`, `ovh_s3_secret_key`, `ovh_s3_endpoint` — változatlan.
- **gatus/flux-alerts/dragonfly components** átemelése phase 2 — itt csak megemlítjük, hogy később hozzáadható.
