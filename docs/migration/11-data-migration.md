# 11 — Data migration (VolSync OVH round-trip)

## Cél

Minden alkalmazás-adat (17 PVC) átkerül a régi K3s clusterről az új Talos clusterre **az OVH S3 Kopia repository-n keresztül**. A folyamat per-app szinten determinisztikus: ReplicationSource snapshot → OVH → ReplicationDestination restore.

## Inputs

- Régi K3s cluster aktív, VolSync ReplicationSource-ok napi 2:00 schedule-lel futnak.
- Új Talos cluster reconcile-olja a `talos` branch-et, a `kubernetes/components/volsync/`-ben mind a `replicationdestination.yaml`, mind a `pvc.yaml` `dataSourceRef` BE-kommentelve (lásd [07-components-and-shared.md](./07-components-and-shared.md)).
- OVH S3 bucket változatlan, Kopia password változatlan.

## Az adatmigráció modellje

```
[Régi K3s cluster]                     [OVH S3 Kopia bucket]                  [Új Talos cluster]
                                                 ↑↓
ReplicationSource (RS)  ─── snapshot ─→  Kopia repo: ${APP}@default:/data
                                                 ←─── restore ─── ReplicationDestination (RD)
                                                                  → új PVC populated
                                                                  → app pod indul
```

A Kopia **ugyanazt a snapshot identity-t** látja mindkét clusterről (`${APP}@default:/data`), mert a `sourceName: "${APP}"` ugyanaz. Az új cluster RD `sourceIdentity.sourceName: "${APP}"`-tal hivatkozik a régi RS által írt snapshot-okra.

## App-onkénti restore terv

Az alkalmazásokat **kategóriába** soroljuk a kockázat és complexity szerint:

### Kategória A: tisztán PVC adat — egyszerű restore

A teljes Kopia repó OVH-n ~3-4 GB (deduplikált), tehát PVC-nként átlag <500 MB. Az egyes app PVC-k konkrét méretét cutover ELŐTT érdemes lekérdezni:

```bash
# Régi clusteren:
kubectl get pvc -A -o custom-columns=NAME:.metadata.name,NS:.metadata.namespace,SIZE:.status.capacity.storage
```

| App | Speciális | Cutover sorrend |
|---|---|---|
| actual | - | 1 |
| bazarr | - | 2 |
| calibre-web-automated | könyvfájlok (NFS-en, NEM PVC-n) | 3 |
| homepage | config | 4 |
| isponsorblocktv | - | 5 |
| maintainerr | - | 6 |
| prowlarr | - | 7 |
| qbittorrent | aktív letöltések, .torrent metadata | 8 |
| radarr | - | 9 |
| seerr | - | 10 |
| sonarr | - | 11 |
| subsyncarr | n/a (PVC-mentes) | n/a |
| wallos | - | 12 |
| resticprofile | config | 13 |
| home-gallery | n/a (PVC-mentes) | n/a |

### Kategória B: PVC + DB konzisztencia — app-level export ajánlott

| App | Adatbázis | App-level export | Cutover sorrend |
|---|---|---|---|
| mealie | SQLite a PVC-n | Mealie export funkció (JSON) — backup | 14 |
| paperless | SQLite/PG + Redis + index | Paperless `document_exporter` (`/backups/paperless`-be) | 15 |
| plex | SQLite (Plex DB) | Plex automatic library backup — `Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db` | 16 |

Az ezekre vonatkozó **app-level export-okat a cutover ELŐTTI nap** kell futtatni. A snapshot ekkor "konzisztens" tartalmat fog rögzíteni.

### Kategória C: nincs PVC — friss install

- `subsyncarr` — config csak env var-ból (ha kell perzisztens, friss config nullról).
- `home-gallery` — szintén csak config.

Ezeknél a HelmRelease ugyanazt az image-et indítja, nincs adat-restore.

## Per-app restore runbook

### Lépés 0 (cutover előtti héten): full snapshot lánc

Régi clusteren minden RS-t manuálisan trigger-elsz, hogy egy friss snapshot menjen OVH-ra:

```bash
# A régi cluster-en futtatva (KUBECONFIG=régi):
for app in $(kubectl get rs -n default -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n default patch rs "$app" --type merge \
    -p "{\"spec\":{\"trigger\":{\"manual\":\"$(date +%s)\"}}}"
  echo "Triggered: $app"
done
# Wait until all complete:
kubectl -n default get rs -o wide --watch
```

A Kopia automatikus retention (7 daily / 2 weekly / 1 monthly) miatt minden snapshot ott lesz az OVH-n.

### Lépés 1 (cutover napján, app előtt): final snapshot

A cutover napján, miután lekapcsoltad a régi app pod-ját (vagy a teljes régi cluster reconcile-t suspendelted), trigger-elj egy **utolsó snapshot-ot**:

```bash
# Adott app utolsó snapshot:
kubectl -n default patch rs plex --type merge \
  -p "{\"spec\":{\"trigger\":{\"manual\":\"final-$(date +%s)\"}}}"

# Várj amíg kész:
kubectl -n default get rs plex -o jsonpath='{.status.lastSyncTime}'
```

Ez biztosítja, hogy a **legfrissebb állapot** kerül OVH-ra, NEM a tegnapi automatikus snapshot.

### Lépés 2 (cutover napján, új clusteren): restore

Az új cluster-en (KUBECONFIG=új):

```bash
# A volsync-component már be van kommentelve a pvc dataSourceRef-fel és a replicationdestination.yaml-lal.
# A Flux reconcile létrehozta a `${APP}-bootstrap` ReplicationDestination-t.

# Trigger a restore-t:
just k8s restore plex default

# Vagy manuálisan:
kubectl -n default patch replicationdestination plex-bootstrap --type merge \
  -p '{"spec":{"trigger":{"manual":"restore-once"}}}'

# Várj:
kubectl -n default wait --for=condition=Synchronizing=False --timeout=30m \
  replicationdestination/plex-bootstrap
```

A folyamat:

1. RD pod indul (Kopia mover container).
2. Lehúzza az OVH-ról a `plex@default:/data` snapshot-ot.
3. Új PVC-t hoz létre (a `pvc.yaml` `dataSourceRef`-en keresztül).
4. PVC `Bound` állapotba kerül a snapshot tartalmával.
5. A Plex pod elindul a populated PVC-vel.

### Lépés 3 (cutover napján, validation): smoke test

```bash
kubectl -n default get pods -l app.kubernetes.io/name=plex
# Running 1/1

kubectl -n default port-forward svc/plex 32400:32400
# open http://localhost:32400/web → működik, library látható
```

Részletes smoke test app-onként a [12-cutover-runbook.md](./12-cutover-runbook.md)-ben.

### Lépés 4 (cutover UTÁN, 1 nap múlva): bootstrap RD cleanup

Miután minden app működik, a `replicationdestination.yaml`-t és a `pvc.yaml` `dataSourceRef`-et **vissza lehet kommentelni** a `kubernetes/components/volsync/kustomization.yaml`-ben. A `${APP}-bootstrap` RD-k törlődnek a Flux reconcile-jával.

**VAGY** — egyszerűbb: hagyjuk benn. A `manual: restore-once` triggerre vár, nem fut. Akkor takarítjuk el, amikor a következő app újra-bootstrap-jét **nem** akarjuk. Most marad benn, döntés cutover után.

## Plex-specifikus megfontolások

Plex DB-je érzékeny. Ajánlott:

1. **Cutover előtti este**: Plex pod-ot megálllítod (`flux suspend hr plex`), majd manuálisan trigger-eled az RS-t. A pod nem ír közben → DB konzisztens.
2. **Cutover napján**: utolsó snapshot manuál trigger, miután a régi cluster Plex pod-ja megállt.
3. **Új cluster restore**: PVC-be a DB-vel együtt jön.
4. **Új cluster Plex pod indítás**: első indítás után a Plex library scan-elhet (5-10 perc), de a DB ott van, csak frissül.

**Hardware Transcoding most NEM kerül bevezetésre** — eddig sem volt konfigurálva, és ezt nem változtatjuk a migráció részeként. A Talos `i915` extension benn marad a schematic-ban jövőbeni lehetőségként, de a Plex pod-spec változatlan.

## Paperless-specifikus megfontolások

Paperless három adatforrást használ:

- **DB** (SQLite vagy PG) — PVC-n él.
- **Documents** — PVC-n (`/usr/src/paperless/media`).
- **Index** (whoosh) — PVC-n (regenerálható).

A **VolSync** mindhárom-at egyetlen PVC-ből menti (jelenlegi setup). Restore után:

- Documents fizikailag ott vannak.
- DB konzisztens (cutover előtti utolsó snapshot).
- Index esetleg újraindexel `paperless_document_renamer + paperless_document_archiver` task-okkal.

**App-level export** (opcionális, defense-in-depth):

```bash
# Régi cluster Paperless pod-ban:
kubectl -n default exec -it deploy/paperless -- \
  document_exporter /usr/src/paperless/export

# Az export PVC-re kerül, a VolSync együtt menti.
```

Az új cluster-en az `/usr/src/paperless/export` mappa visszaáll, és **vész esetén** `document_importer`-rel restore-olható.

## qBittorrent-specifikus megfontolások

qBittorrent **aktív torrent-eket** futtat. Cutover-kor:

1. Régi cluster: `flux suspend hr qbittorrent` → pod megáll → torrent-ek leállnak.
2. Utolsó snapshot (a torrent state, `.torrent` fájlok, metaadat).
3. Új cluster: restore → új pod indul → torrent-ek folytatódnak.

A `qbittorrent_data` PVC tartalma:

- `BT_backup/` — torrent metaadat
- `BT_files/` — letöltött tartalom (ha ide állítva)

A **letöltött tartalom** néha NFS-en (a M93p OMV-n) van, nem PVC-n. Ezt **nem érinti** a migráció — az NFS share változatlan.

## Mealie-specifikus megfontolások

Mealie SQLite-ot használ a PVC-n. Hasonló DB-konzisztencia mint a Plex-nél:

1. Pod megállítás cutover előtt.
2. Utolsó snapshot.
3. App-level export (opcionális): Mealie web UI-n „Backup" → ZIP letöltés egy NFS share-re.

## ExternalSecret-tel rendelkező app-ok

A 6 app (mealie, paperless, plex, resticprofile, homepage, és onepassword-connect maga) `ExternalSecret`-eket használ. Ezek **nem migrálódnak** — minden új clusteren újragenerálódnak az 1Password ClusterSecretStore-ból.

Validation:

```bash
kubectl -n default get es
# minden ES Ready=True az új clusteren
```

## Méret-becslés és időbecslés

| Mennyiség | Becslés |
|---|---|
| Snapshot teljes méret | **3-4 GB** (mind az 17 PVC, deduplikálva + tömörítve) |
| Letöltés OVH-ról HP-ra (1 GbE) | 100 MB/s elméleti, gyakorlatban ~70-80 MB/s |
| Kopia decompression overhead | ~20% lassítás |
| Teljes restore idő (mindenre) | **10-15 perc** |

A 17 RD-t **párhuzamosan** indíthatjuk, mert mindegyik külön Kopia mover pod-ban fut. A bottleneck a hálózati sávszél (1 GbE), de 3-4 GB teljes méret mellett ez nem szűk keresztmetszet. A target PVC írási sebesség (P31 NVMe Gen3-on) bőven a hálózati throughput felett.

**Megjegyzés**: a "3-4 GB" a Kopia repó teljes mérete az OVH-n (deduplikált). Egy-egy app PVC fizikai mérete nagyobb lehet, de a Kopia mover csak a snapshot blokkokat tölti le → restore-kor a target PVC csak a snapshot-ban szereplő fájlokat tartalmazza.

A `just k8s restore-all` recipe (új, hozzá kell adni a `kubernetes/mod.just`-hoz):

```just
[doc('Restore ALL bootstrap RD-s in parallel')]
[script]
restore-all:
    kubectl get replicationdestinations -A --no-headers \
      | grep "bootstrap" \
      | awk '{print $1, $2}' \
      | while read -r ns name; do
          kubectl -n "$ns" patch replicationdestination "$name" --type merge \
            -p '{"spec":{"trigger":{"manual":"restore-once"}}}' &
        done
    wait
    just log info "All RD-s triggered, waiting for completion..."
    kubectl get replicationdestinations -A -w
```

## Validation

```bash
# Minden RD lefutott:
kubectl get replicationdestinations -A
# minden Synchronizing=False

# Minden PVC Bound:
kubectl get pvc -A | grep -v Bound
# üres output

# Minden HR Ready:
kubectl get hr -A | grep -v True
# üres output

# Pod-ok futnak:
kubectl get pods -A | grep -v Running
# csak Completed Job-ok és Succeeded init container-ek

# App-szintű smoke test (lásd 12-es doc)
```

## Rollback

### Egy app restore hibázik

```bash
kubectl -n default describe replicationdestination plex-bootstrap
# Events:
#   Kopia restore failed: ...

# Manual retry:
kubectl -n default delete pod -l app.kubernetes.io/name=plex-bootstrap
# RD újra indít

# Vagy: másik snapshot ID-vel:
kubectl -n default edit replicationdestination plex-bootstrap
# spec.kopia.sourceIdentity.sourceName: ${APP}
# spec.kopia.sourceIdentity.snapshot: <korábbi snapshot ID>
```

### Teljes restore-flow összeomlik

Régi cluster **továbbra is fut** (1-2 hét fenntartás). Cutover visszavonható:

1. DNS rekord vissza-mutat a régi cluster IP-jére.
2. Új cluster reconcile suspend (`flux suspend ks cluster-apps`).
3. Új cluster sense van mint development/testing branch.

Részletes rollback procedúra a [13-rollback-and-decom.md](./13-rollback-and-decom.md)-ben.

## Open issues

- **Kopia repo lock**: ha a régi cluster RS és az új cluster RD egyszerre fut, a Kopia repo-n lock-ot kérnek. Hivatalosan ez OK (Kopia konkurens), de gyakorlatban óvatosan időzítsd: utolsó RS előtt **suspend** az RS schedule-t.
- **PVC storage class mismatch**: ha az új cluster `democratic-csi-local-hostpath` storage class neve eltér a régitől (`democratic-csi`?), a PVC bound állapotba nem kerül. Ellenőrizd az új clusteren `kubectl get sc`.
- **PV teljes méret restore eltér**: ha a snapshot 3 GB-os tartalmat tartalmaz egy 5 GB-os PVC-ben, a Kopia mover **csak a tartalmat** állítja vissza, a PVC marad 5 GB. Ez OK.
- **RD futás közben app pod indítás kísérlete**: Flux esetleg túl agresszívan próbálja indítani a HelmRelease-t. Megoldás: **vagy** `flux suspend hr plex` cutover-rel, **vagy** az app-on `dependsOn:` a saját bootstrap RD-re — bonyolult. Inkább suspend → restore → resume.
- **A bootstrap RD-t másodszor futtatni**: ha valami félresikerült és újraindítod a restore-t, a `manual: restore-once` triggert új értékre kell állítani (pl. `restore-twice`). VolSync látja, hogy "új trigger érték = új run".
