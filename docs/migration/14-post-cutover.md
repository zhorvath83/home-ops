# 14 — Post-cutover (megfigyelési ablak + OMV bare metal)

## Cél

A cutover utáni 1-2 hét **megfigyelési ablak** definíciója: mire kell figyelni, mikor mondhatjuk "kész", és mit kell hozzátenni utána. Plusz az M93p Proxmox+OMV VM → bare metal OMV átalakítás runbook-ja.

## Megfigyelési ablak (T+1 — T+14)

### Daily checks (T+1 — T+7)

Naponta egyszer (reggel, kávé mellett):

```bash
# Cluster health:
kubectl get nodes -o wide
# main Ready
# uptime hosszú

kubectl get pods -A | grep -v "Running\|Completed" | grep -v "1/1\|2/2\|3/3"
# üres output várt

# Flux reconcile:
flux get kustomizations
# minden Ready=True, last reconcile < 1 óra

# Backup status:
kubectl get rs -A
# minden RS lastSyncTime < 26 óra (napi 2:00 + 2 óra puffer)

# Resource usage:
kubectl top nodes
# CPU < 50%, RAM < 70%

kubectl top pods -A --sort-by=memory | head -10
# top 10 memory consumer

# Storage:
kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.status.capacity.storage}{"\n"}{end}'
```

### Weekly checks (T+7, T+14)

```bash
# Backup verify — random app restore-test:
# Másoló RD egy temp namespace-be:
kubectl create ns restore-test
# Másold a paperless-bootstrap RD-t, módosítsd a destination PVC nevét:
kubectl get rd -n default paperless-bootstrap -o yaml \
  | sed 's/namespace: default/namespace: restore-test/' \
  | sed 's/name: paperless-bootstrap/name: paperless-test/' \
  | kubectl apply -f -

# Trigger restore:
kubectl -n restore-test patch rd paperless-test --type merge \
  -p '{"spec":{"trigger":{"manual":"verify-'"$(date +%s)"'"}}}'

# Várj, ellenőrizd:
kubectl -n restore-test wait --for=condition=Synchronizing=False --timeout=20m \
  replicationdestination/paperless-test

kubectl -n restore-test get pvc
# paperless PVC Bound, mérete reasonable

# Cleanup:
kubectl delete ns restore-test
```

### Monitoring dashboards

A Grafana-n nézz rá:
- **Cluster overview** — Node CPU/RAM/Disk
- **Cilium dashboard** — flow rate, drops
- **Hubble** — service-service forgalom (`hubble.<INTERNAL_DOMAIN>` UI)
- **Flux** — reconcile success rate, error count
- **VolSync** — snapshot duration, last success time
- **App-specifikus** — Plex, Sonarr stb. ha vannak custom dashboard-ok

### Alert validation

A cluster Pushover alerts-eket küld a `flux-system/addons/alerts/`-en keresztül. Próba:
```bash
# Manuálisan trigger-elj egy hibát (pl. broken HR):
kubectl -n default edit hr plex
# image: ghcr.io/nonexistent/plex:v0.0.0

# Wait reconcile:
sleep 60

# Pushover-en érkezett alert?
# Ha igen → alerting OK.
# Ha nem → debug flux Alert config.

# Revert:
kubectl -n default edit hr plex
# vagy: git checkout main -- kubernetes/apps/default/plex/app/helmrelease.yaml && git push
```

### Kritikus események — milyen reakció?

| Esemény | Reakció |
|---|---|
| Egy app HR `False` állapot | Diagnose: `kubectl describe hr <app>` |
| Egy RS `lastSyncTime` > 30 óra | Diagnose: `kubectl describe rs <app>` — Kopia errors |
| Node `NotReady` | Talos status: `talosctl -n main health` |
| Node reboot kernel panic | `talosctl -n main dmesg` után Talos bug report |
| Cilium pod crashloop | Diagnose: `kubectl -n kube-system logs ds/cilium` |
| OVH S3 elérhetetlen | OVH status page, retry, vagy OVH API key rotation |

### Sikeres ablak kritériumai (T+14)

- [ ] Nincs P0/P1 incidens 14 napon át.
- [ ] Minden napi snapshot lefutott.
- [ ] A backup-verify restore-test sikeres.
- [ ] Node uptime > 13 nap (vagy 1 tervezett reboot).
- [ ] Felhasználó: "minden rendben, nem érez performance különbséget".

## OMV bare metal átalakítás (T+14 után)

Ha a megfigyelési ablak sikeres, a M93p átalakítása következik. Ez **független projekt**, NEM része a cutover-nek.

### Tervezés (T+14)

1. **Időpont egyeztetés** — egy 4-6 órás ablak, amikor a NAS leállhat.
2. **Konfiguráció backup** — `/etc/openmediavault/config.xml` mentve a régi VM-ből.
3. **Új Debian ISO** — Debian 13 (Trixie) net-install USB-re.
4. **`provision/openmediavault/` Ansible** — lásd [10-omv-ansible.md](./10-omv-ansible.md), tesztelve a régi VM-en (`ansible-playbook --check` mode).

### Cutover napon (T+14+x)

#### Stage 1: Régi VM állapot biztosítása

```bash
# Proxmox web UI-on a M93p OMV VM-en:
# - Kapcsold ki: Shutdown (graceful)
# - Készíts Proxmox snapshot-ot: "pre-baremetal-migration"
# - A VM disk file (qcow2) MARAD a Proxmox storage-on, csak nem fut.

# Az USB DAS fizikailag a M93p-be van dugva — a Proxmox passthrough volt eddig.
# Most fizikai elővétel:
# - M93p shutdown: ssh m93p sudo poweroff
# - USB DAS unplug, várj 30s
```

#### Stage 2: Bare metal Debian install

```bash
# USB Debian 13 (Trixie) net-install bedugás M93p-be.
# Boot, "Graphical install".
# Hostname: m93p
# Network: static IP 192.168.1.10 (vagy DHCP, OpenWRT reserveld)
# Storage:
#   - 2.5" SATA SSD: rootfs (/, /boot, swap)
#   - mSATA: NEM kell, hagyd üresen vagy adatként
# User: admin (sudo NOPASSWD beállítva később)
# Tasks: standard system utilities, SSH server
# Reboot → Debian fut.
```

**OMV verzió kompatibilitás**: ha az OMV jelenlegi stable még Debian 12-höz kötött (OMV 7 Sandworm), akkor Debian 12-vel kezdj. Frissítés Debian 13 + OMV 8-ra később, in-place migration-nel. A jelenlegi info: az OMV release ciklusa Debian-követő, ellenőrizd a [openmediavault.org](https://www.openmediavault.org/) hivatalos stable verzióját az install előtt.

#### Stage 3: Ansible setup

```bash
# Lokálisan:
cd provision/openmediavault

# Inventory: 192.168.1.10 stimmel (régi VM IP-je, most a bare metal-t kapja).
# SSH key copy:
ssh-copy-id admin@192.168.1.10

# Sudoers config (kézi):
ssh admin@192.168.1.10 'echo "admin ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/admin'

# Ansible reach check:
just omv check

# Full install:
just omv install
```

A playbook végigfut:
1. Base hardening (UFW, packages).
2. OMV BASE install (apt repo, omv-confdbadm populate).
3. USB DAS bedugás után fstab mount.
4. resticprofile + Backrest (NEM OMV-managed).
5. node_exporter (NEM OMV-managed).

**Az NFS exports, shares, users a `config.xml` restore-jából jönnek vissza** (Stage 4), NEM az Ansible-ből — lásd [10-omv-ansible.md](./10-omv-ansible.md) "Megközelítés A" szekciót.

**Időbecslés**: 30-60 perc.

#### Stage 4: OMV config restore

```bash
# A régi VM-ből mentett config.xml:
scp ~/backup-omv-config.xml admin@192.168.1.10:/tmp/

# Restore:
ssh admin@192.168.1.10
sudo omv-confdbadm load /tmp/backup-omv-config.xml
sudo omv-salt deploy run
```

A `omv-confdbadm load` overwrite-olja a bare metal OMV config-ot a régi VM beállításaival. Plugins, shares, users — minden vissza.

#### Stage 5: USB DAS bedugás + fstab finomítás

```bash
# Fizikailag dugd be az USB DAS-t a bare metal M93p-be.
# Várj 10 másodperc.

# Check:
ssh admin@192.168.1.10 'lsblk'
# /dev/sdb (USB DAS) megjelenik

# Mount path:
ssh admin@192.168.1.10 'ls /srv/dev-disk-by-uuid-*'
# Az OMV automatikusan felmountolja az ismert UUID-jű disk-et a config alapján.

# Verify NFS:
showmount -e 192.168.1.10
# /srv/dev-disk-by-uuid-<UUID>/media 192.168.1.0/24
# /srv/dev-disk-by-uuid-<UUID>/backup 192.168.1.0/24
```

#### Stage 6: HP cluster NFS reconnect

A HP cluster app-jainak NFS mountja megszakadt az M93p shutdown alatt. Az új OMV bekapcsolása után **automatikusan visszakapcsolódnak** (NFS hard mount default).

Ellenőrzés:
```bash
KUBECONFIG=~/.kube/config-new
kubectl -n default get pods | grep -i "ContainerCreating\|Error"
# Ha valami stuck NFS-en, restart:
kubectl -n default rollout restart deployment <app>
```

#### Stage 7: resticprofile cron + monitoring

```bash
# resticprofile timer:
ssh admin@192.168.1.10 'systemctl list-timers | grep restic'
# resticprofile-backup@ovh.timer active

# Backup test (dry-run):
ssh admin@192.168.1.10 'sudo resticprofile -n ovh backup --dry-run'

# node_exporter scrape:
curl -s http://192.168.1.10:9100/metrics | head -20
# Prometheus output
```

### Stage 8: Régi Proxmox VM cleanup

```bash
# Proxmox web UI:
# - Régi M93p OMV VM (a régi Proxmox host-ján, .4 vagy .5):
# - Verify: a bare metal OMV fut 1-2 napja, mindent kiszolgál.
# - Töröld a VM-et (Disk-eket is).
```

**MOST** mindkét Proxmox host (`192.168.1.4`, `.5`) **dekomisszionálható**, ha más VM nem fut rajtuk:
```bash
# Proxmox host SSH:
ssh proxmox-host
# Shutdown:
sudo poweroff

# Fizikai gép kikapcsolás, kihúzás.
# Az IP-k felszabadulnak (.4, .5).
```

A `provision/cloudflare/`-ben és az OpenWRT DHCP-ben **frissítendő**: a 4 és 5 IP-k szabaddá válnak.

### Validation a bare metal OMV után

```bash
# Lokálisan:
just omv check                                  # ping + showmount

# HP cluster-en:
kubectl -n default get pods                    # minden Running

# Sonarr/Radarr import-test:
# (web UI-n próbálj új sorozat/film-t hozzáadni — letöltődik NFS-re)

# Plex library scan:
# (web UI-n indítsd manuálisan — felismeri az új tartalmat NFS-en)
```

### Sikeres OMV bare metal — kritériumok

- [ ] M93p bootol < 30 másodperc alatt.
- [ ] NFS export-ok elérhetők a HP-ról (`mount -t nfs ... && ls`).
- [ ] OMV web UI ugyanolyan állapotban, mint a VM-ben volt (shares, users, plugins).
- [ ] resticprofile lefut éjszaka, log látszik.
- [ ] node_exporter scrape-elve Prometheus-ban (Grafana node dashboard renderel).

## Doc updates a cutover után

A `docs/migration/README.md` státusz táblát frissíteni:
```markdown
| Fázis | Status | Megjegyzés |
|---|---|---|
| Tervezés (docs) | ✅ completed | |
| `talos` branch létrehozása | ✅ completed | |
| Talos bootstrap (HP-n) | ✅ completed | |
| Cilium install | ✅ completed | |
| App migráció | ✅ completed | |
| Cutover | ✅ completed | YYYY-MM-DD |
| Régi cluster decom | ✅ completed | YYYY-MM-DD |
| OMV bare metal | ✅ completed | YYYY-MM-DD |
```

A `docs/`-ban egyéb dokumentumok frissítése külön projekt — listázva a [13-rollback-and-decom.md](./13-rollback-and-decom.md) végén.

## Phase 2 — opcionális fejlesztések

A cutover sikeres lezárása után érdemes lehet:

- **Namespace szétbontás** — `default` → `media`, `productivity`, `system` (lásd [06-repo-restructure.md](./06-repo-restructure.md) végén).
- **kubernetes/components/ bővítés** — bjw-s minták átemelése: `flux-alerts`, `gatus`, esetleg `dragonfly` ha cache kell.
- **Hubble UI HTTPRoute + auth** — a UI-t LAN-on elérhetővé tenni Anubis/basic-auth védelemmel.
- **BGP migration** — ha worker node-okat adsz a cluster-hez, L2 → BGP refaktor (OpenWRT BGP peer).
- **iGPU device plugin** — Intel `i915` device plugin (`intel-gpu-plugin`) használata a direct host mount helyett, hogy a Plex `gpu.intel.com/i915: 1` resource request-tel kérje.
- **GPU shared pool** — ha jövőben másik app is használja az iGPU-t (pl. Jellyfin transcode tesztelés), a device plugin sharing-et engedélyez.
- **OpenWRT BGP + ExternalDNS BGP integráció** — több zóna kezelés.

Ezek mind **külön projekt** — független a cutover-től.

## Open issues

- **NFS UUID stability**: ha a bare metal Debian install **újraformázza** az USB DAS partícióját (NE tedd), az UUID megváltozik → minden HP PV mountpath törik. **Mitigáció**: az Ansible storage role-t úgy állítsd be, hogy `state: mounted` + `nofail`, és a fstab-ot **manuálisan ellenőrizd** a régi VM-ből az új-on.
- **Proxmox VM disk file teardown**: a régi M93p OMV VM disk file (qcow2) a Proxmox storage-on marad még a VM törlése után, ha nem markeled "Delete unreferenced disks". OMV adat tartalom **nincs** a qcow2-ben (az adat a USB DAS-on), tehát biztonságos törölni.
- **OMV plugin compatibility OMV verzió update-tel**: a bare metal OMV friss verzió (sandworm), a régi VM esetleg régebbi (shaitan/usul). A `omv-confdbadm load` ezt **általában** kezeli (forward-compat), de plugin-szintű inkompatibilitás előfordulhat. Backup-ra építve, fail esetén manuálisan újra config.
- **node_exporter scrape az M93p-ről**: a `kube-prometheus-stack` scrape config-ja PrometheusRule-ban vagy ServiceMonitor-on keresztül kell konfigurálva legyen az új clusteren. Erre **külön PrometheusScrapeConfig vagy AdditionalScrapeConfig** kell, mert a M93p NEM cluster node. Jelenlegi setup-ban ez valószínűleg már megvan — ha nem, akkor egy `additionalScrapeConfigs`-be hozzáadandó.
- **Ansible playbook a régi VM-en tesztelve**: az ideális workflow, hogy a `provision/openmediavault/` Ansible-t a régi M93p OMV VM-en `--check` módban próbáljuk először, hogy lássuk, milyen change-eket javasolna. Ha minden idempotens, OK. Ha nem, javítjuk.
- **OMV web UI plugins reinstall**: bizonyos plugins post-config restore-kor újra-install-álást igényelhetnek a web UI-n keresztül.
