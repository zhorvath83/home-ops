# 15 — Post-cutover TODO

Személyes teendőlista a cutover utáni 1-2 hetes megfigyelési ablakra, az utána következő M93p bare metal OMV install-ra, és a doc-réteg lezárására. A `13-cutover-runbook.md` és a `14-rollback-and-decom.md` a részletes runbook-ok — ez itt csak az időrendi pipalista.

## Megfigyelési ablak (T+1 — T+14)

### Napi pipalista (T+1 — T+7)

- [ ] `kubectl get nodes -o wide` — Ready, uptime nő.
- [ ] `kubectl get pods -A | grep -v Running\|Completed` — üres.
- [ ] `flux get kustomizations` — minden Ready, last reconcile < 1h.
- [ ] `kubectl get rs -A` — minden `lastSyncTime` < 26h.
- [ ] `kubectl top nodes` — CPU < 50%, RAM < 70%.
- [ ] Grafana cluster overview + Cilium + Flux + VolSync dashboard egyszer átfutva.

### Hetente (T+7, T+14)

- [ ] **Backup verify** — egy random app PVC restore-test másik namespace-be (RD másolás + manual trigger + PVC bound check + cleanup).
- [ ] **Alert validation** — kézzel kibillenteni egy HR-t, Pushover alert megjött-e, revert.
- [ ] Hubble dashboard átfutás (drop rate, top talkers).

### Reakció — mikor mit

| Esemény | Reakció |
|---|---|
| Egy app HR `False` | `kubectl describe hr <app>`, fix vagy rollback |
| `lastSyncTime` > 30h | `kubectl describe rs <app>` — Kopia / OVH hiba |
| Node `NotReady` | `talosctl -n k8s-cp0 health`, `talosctl dmesg` |
| Cilium pod crashloop | `kubectl -n kube-system logs ds/cilium` |
| OVH S3 elérhetetlen | OVH status page, retry, esetleg API key rotation |

### Exit kritérium (T+14)

- [ ] Nincs P0/P1 incidens 14 napon át.
- [ ] Minden napi snapshot lefutott.
- [ ] Backup-verify restore-test legalább 1× sikeres.
- [ ] Node uptime > 13 nap (vagy egy tervezett reboot).
- [ ] Saját megérzés: "minden rendben".

A megfigyelési ablak lezárása után indul a [14-rollback-and-decom.md](./14-rollback-and-decom.md) "2. Decommission" szekciója (régi K3s cluster + Proxmox VM-ek), és párhuzamosan az OMV bare metal átalakítás (lent).

## OMV bare metal átalakítás (T+14 után)

Független projekt, NEM része a cutover-nek. A részletes runbook a [10-omv-ansible.md](./10-omv-ansible.md)-ben — itt csak a teendők sorrendje.

### Tervezés

- [ ] 4-6 órás karbantartási ablak egyeztetve a háztartással.
- [ ] `/etc/openmediavault/config.xml` mentve a régi VM-ből.
- [ ] Debian net-install USB előkészítve (Debian 13 Trixie, ha OMV stable támogatja — különben Debian 12 + későbbi in-place upgrade).
- [ ] `provision/openmediavault/` Ansible playbook `--check` módban lefutva a régi VM-en (idempotencia ellenőrzés).

### Cutover napon

- [ ] Régi M93p OMV VM `Shutdown` (graceful) + Proxmox snapshot `pre-baremetal-migration`.
- [ ] M93p fizikai poweroff, USB DAS unplug, 30s wait.
- [ ] Debian net-install USB-ről (hostname `m93p`, static IP `192.168.1.10`, SSH server, standard utilities).
- [ ] SSH key copy + sudoers NOPASSWD beállítva.
- [ ] `just omv check` zöld.
- [ ] `just omv install` lefutott.
- [ ] `scp` config.xml → `/tmp/` + `sudo omv-confdbadm load` + `sudo omv-salt deploy run`.
- [ ] USB DAS fizikai bedugás + `lsblk` ellenőrzés.
- [ ] `showmount -e 192.168.1.10` az exportok látszanak.
- [ ] HP clusteren `kubectl get pods -A` — semmi `ContainerCreating` NFS miatt; szükség esetén `kubectl rollout restart deployment <app>`.
- [ ] `systemctl list-timers | grep restic` — resticprofile timer aktív.
- [ ] `curl http://192.168.1.10:9100/metrics` — node_exporter scrape él.
- [ ] Sonarr/Radarr import smoke test + Plex library scan.

### OMV utáni cleanup

- [ ] Régi M93p OMV VM törlése Proxmox-ról ("Delete unreferenced disks" ON).
- [ ] Mindkét Proxmox host (`192.168.1.4`, `.5`) shutdown, ha más VM nem fut rajtuk.
- [ ] `provision/cloudflare/` + OpenWRT DHCP felszabadult IP-k frissítve.

## Doc + status frissítés a cutover után

- [ ] `docs/migration/README.md` "Status" táblázat: `Cutover` → `✅ completed YYYY-MM-DD`.
- [ ] `docs/migration/STATUS.md` "Élő tracker" tábla frissítve.
- [ ] Decom után: `Régi cluster decom` → `✅ completed`.
- [ ] OMV bare metal után: `OMV bare metal` → `✅ completed`.
- [ ] A `docs/` egyéb K3s-éra cleanup külön projekt — [14-rollback-and-decom.md](./14-rollback-and-decom.md) "Doc cleanup" szekció.

## Phase 2 — opcionális fejlesztések

Külön projektek, NEM a cutover része. Akkor érdemes nekiállni, ha minden zöld.

- [ ] Namespace szétbontás `default` → `media`, `productivity`, `system` (lásd [06-repo-restructure.md](./06-repo-restructure.md) vége).
- [ ] `kubernetes/components/` bővítés bjw-s mintákkal (`flux-alerts`, `gatus`, esetleg `dragonfly`).
- [ ] Hubble UI HTTPRoute + Anubis / basic-auth.
- [ ] iGPU device plugin (Intel `i915`) bevezetés a Plex-be a direct host mount helyett.
- [ ] L2 → BGP refactor (csak ha worker node-ot kap a cluster).
- [ ] Phase 16.c — per-app CiliumNetworkPolicy threat-model audit (lásd [16-repo-refactor.md](./16-repo-refactor.md) "16.c" szekció).

## Open issues

- **NFS UUID stability**: ha a bare metal Debian install **újraformázza** az USB DAS partícióját (NE tedd), az UUID megváltozik → minden HP PV mountpath törik. Mitigáció: Ansible storage role `state: mounted` + `nofail`, fstab kézi diff a régi VM és az új gép között.
- **Proxmox VM disk file teardown**: a régi M93p OMV VM disk-jét csak akkor lehet törölni, ha a "Delete unreferenced disks" markelve van — különben a qcow2 a Proxmox storage-on marad. Az OMV adat **nincs** a qcow2-ben (USB DAS-on van), tehát biztonságos.
- **OMV plugin forward-compat**: ha a bare metal frissebb OMV verzión megy, mint a régi VM, plugin-szintű inkompatibilitás előfordulhat. Backup-pal lefedve, fail esetén kézi reinstall.
- **node_exporter scrape config**: a `kube-prometheus-stack` scrape-je `additionalScrapeConfigs`-en keresztül kell, hogy lássa az M93p-t (NEM cluster node). Ha még nincs beállítva, post-cutover follow-up.
- **OMV web UI plugins reinstall**: bizonyos pluginek config-restore után újra-install-álást igényelhetnek a web UI-ról.
