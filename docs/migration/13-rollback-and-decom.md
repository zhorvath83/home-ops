# 13 — Rollback és decommission

## Cél

Két forgatókönyv:
1. **Cutover rollback** — ha a cutover napon (vagy az első 1-2 hétben) valami visszafordíthatatlanul elromlik, vissza tudunk térni a régi K3s clusterre.
2. **Decommission** — a megfigyelési ablak (1-2 hét) lezárása után a régi cluster + Proxmox infrastruktúra szétszedése.

## 1. Rollback — vissza a régi K3s clusterre

### Mikor jogos a rollback?

| Tünet | Súlyosság | Rollback? |
|---|---|---|
| 1-2 app nem indul | Alacsony | NEM — fixeld az app-ot |
| Plex nem indul, de minden más OK | Közepes | NEM — debug, ha 1-2 óra alatt nem megy, plex-only rollback |
| Cilium nem stabil, intermittent pod hiba | Magas | LEHET — diagnose, ha 4 óra alatt nem megy, rollback |
| Talos node kernel panic / állandó reboot | Kritikus | IGEN |
| Teljes data corruption (PVC restore hibás) | Kritikus | IGEN |
| Network throughput < 10% — DNS hibák | Magas | IGEN |
| Tudod hogy ma este vendég jön és kell a Plex | n/a | IGEN (pragmatikus) |

**Hüvelykujj-szabály**: ha 4 órán belül nem stabilizálódik az új cluster, rollback. A részleges rollback (DNS visszafordítás) bármikor megoldás 2-3 napon belül, ameddig a régi cluster fut.

### Rollback procedúra — cutover napon

A modell egyszerű: **a két cluster nem fut egyszerre** (azonos LB IP-k, egyetlen Cloudflare tunnel connector). Rollback = HP cluster powerdown + K3s VM power on.

**T+x:00 — döntés rollback-re**

#### Stage R1: HP cluster shutdown

```bash
# Új cluster — Talos node powerdown:
talosctl -n 192.168.1.11 shutdown

# Vagy fizikailag: HP power button (long press).
# Várj 30s, hogy az ARP table-ok kiürüljenek (.18, .19, .20 felszabad):
sleep 30
ping -c 1 192.168.1.18      # no response, IP free
```

**Time**: 2-3 perc.

#### Stage R2: Régi K3s VM power on + resume

```bash
# Proxmox web UI vagy SSH:
ssh proxmox qm start <vmid>
# Vagy Proxmox UI: VM → Start

# Várj amíg a K3s API up:
until kubectl --kubeconfig ~/.kube/config-old get nodes 2>/dev/null; do
  echo "Waiting for K3s..."; sleep 10
done

KUBECONFIG=~/.kube/config-old

# Resume minden HR (a freeze óta):
for hr in $(kubectl get hr -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {end}'); do
  ns=$(echo "$hr" | cut -d/ -f1)
  name=$(echo "$hr" | cut -d/ -f2)
  flux resume hr "$name" -n "$ns"
done

# Várj amíg minden Ready:
kubectl get hr -A
```

**Time**: 5-10 perc (K3s VM boot + app reconcile).

#### Stage R3: Validation

```bash
# LB IP-k a régi K3s MAC-jén:
arp -a | grep "192.168.1.18\|192.168.1.19\|192.168.1.20"
# K3s VM MAC

# Cloudflare tunnel connector:
# - Dashboard: a régi cluster cloudflared pod-ja csatlakozott
# - Külső: curl -I https://homepage.<CLOUDFLARE_DOMAIN> → 200 OK

# LAN: dig homepage.<INTERNAL_DOMAIN> → .18 (változatlan IP, régi cluster mögött)
```

**Time**: 5 perc.

**Total rollback time**: ~10-15 perc.

#### Stage R4: Adatok közti drift kezelés

**Probléma**: a cutover óta (mondjuk 2 óra) az új clusteren történtek változtatások (új Paperless dokumentum, új Sonarr sorozat hozzáadás). Ezek a változások **az új cluster PVC-iben vannak**, a régi clusteren nincsenek.

**Megoldás opciók**:

**Opció 1 — drift elfogadás** (preferált)
A 2 órás drift legtöbb esetben elfogadható (`*arr` újra-scan-elhet, Plex újra-find media). A felhasználó **tudomásul veszi**, hogy az új clusteren született új state elveszett.

**Opció 2 — drift visszamigrálás** (komplex, ritka)
Az új cluster powerdown ELŐTT trigger-elj egy snapshot-ot:
```bash
# MIELŐTT lekapcsolod az új cluster-t:
KUBECONFIG=~/.kube/config-new
just k8s snapshot-all
# Várj amíg minden RS lefutott (~10-15 perc)
```

Aztán a régi cluster on-power után manuálisan restore-old a régi cluster PVC-jébe (régi cluster nem ismeri a "bootstrap RD" mintát automatikusan — kézi manifest).

**Default**: Opció 1. A drift elfogadható.

#### Stage R5: Bejelentés

"Visszaálltunk a régi clusterre, később újra próbálunk." A HP node lekapcsolva, később debug-olható (boot Talos installer ISO-ról és vizsgáld).

### Részleges rollback — NINCS ilyen lehetőség

Mivel a két cluster nem futhat egyszerre (LB IP-konfliktus), **NINCS** részleges rollback. Vagy az új cluster fut, vagy a régi. App-szintű rollback nem megvalósítható ezzel a setup-pal.

Ha egy app csak az új clusteren nem indul: **debug-old az új clusteren**, ne rollback-elj az egész stack miatt.

### Időkorlátok a rollback-re

| Időpont | Mehet rollback? | Hogyan |
|---|---|---|
| Cutover napján (T+0 — T+12h) | KÖNNYŰ | DNS revert, régi cluster resume |
| T+1 — T+3 nap | KÖZEPES | Drift nagyobb, de még a régi cluster fut |
| T+4 — T+7 nap | NEHÉZ | Drift jelentős, de a régi cluster fizikailag fut |
| T+8 — T+14 nap | ALKALMI | Lehetne, de a régi cluster lassan inaktív |
| T+15+ nap | **NEM** | A régi cluster decom (lásd alább) |

**A megfigyelési ablak (T+1 — T+14) alatt** a régi cluster fizikailag megmarad (M93p-n Proxmox VM-ben). Csak az után dekomisszionáljuk, hogy az új cluster stabil.

## 2. Decommission — régi infrastruktúra szétszedése

### Mikor érdemes?

A megfigyelési ablak (1-2 hét) sikeres lezárása után. Konkrét feltételek:
- [ ] Új cluster 7-14 napja fut, semmilyen kritikus incidens.
- [ ] Minden app stabil, minden snapshot fut.
- [ ] Backup verify pozitív (test restore-test másik namespace-be működött).
- [ ] Felhasználói visszajelzés: "minden OK".

### Régi K3s cluster teardown

```bash
# Régi cluster - utolsó teljes etcd dump (paranoid):
KUBECONFIG=~/.kube/config-old
kubectl get all -A -o yaml > ~/backup-old-cluster-$(date +%Y%m%d).yaml

# Régi Cloudflare tunnel pod definitív kikapcsolás:
flux suspend hr cloudflare-tunnel -n networking
# (már suspended cutover óta, de paranoia)

# K3s teardown (a régi cluster gépen):
KUBECONFIG=~/.kube/config-old
# Old cluster: drain + cordon node
kubectl drain <old-node> --ignore-daemonsets --delete-emptydir-data

# K3s uninstall (a node gépén SSH-n):
ssh <old-node>
sudo /usr/local/bin/k3s-uninstall.sh
# K3s teljesen eltávolítva, OS marad

# VM shutdown:
sudo poweroff
```

### Proxmox VM-ek decom

A régi K3s VM-et (Proxmox-on, `192.168.1.6`):

```bash
# Proxmox web UI (a két Proxmox host-on):
# - Régi K3s VM: Backup → letöltés (utolsó snapshot) → VM törlés
# - Régi M93p OMV VM: marad fenntartva, amíg a bare metal OMV nem készül el

# A két Proxmox host (192.168.1.4, .5):
# Ha mindkettő csak a régi K3s VM-et futtatta — **mindkettő dekomisszionálható**.
# Ha valami más fut rajtuk (másik VM, fizikai hardver) — csak a K3s VM-et töröljük.
```

**Megjegyzés**: Az M93p OMV VM **nem** itt törlődik — az [14-post-cutover.md](./14-post-cutover.md)-ben kerül átfedésre a bare metal OMV install-ra.

### Régi 1Password items törlése

A régi cluster-specifikus 1Password item-ek (ha vannak) törölhetők:
- `op://HomeOps/k3s-token` — ha volt
- `op://HomeOps/old-cluster-*` — bármi cluster-specifikus

**FONTOS — NE töröld**:
- `op://HomeOps/talos/*` — az új clusternek kell
- `op://HomeOps/1password-connect-kubernetes/*` — a Connect Server-nek kell
- `op://HomeOps/*` — app-secrets, runtime-ban használt

### Provision/kubernetes mappa törlése

A `talos` branch-en (vagy main-ben cutover után):

```bash
git rm -r provision/kubernetes/
git commit -m "🔥 remove(provision): old Ansible K3s provisioning"
```

A régi `provision/kubernetes/` Ansible setup, K3s install playbook, inventory — törölhető.

### DNS rekord cleanup

A Cloudflare DNS-ben:
- Régi cluster-specifikus rekordok (ha pl. `old.<domain>` test rekord volt) — törölhető.
- A főbb rekordok (Plex, Sonarr stb.) **maradnak** — az új clusterre mutatnak.

### Régi cluster Kopia identity törlése (opcionális)

Az új clusteren induló RS új identity-t használ — más `hostname` (`@main` cluster). A régi RS identity (`@home-ops` cluster vagy bármi volt) **még az OVH bucket-ben** áll, retention szerint kifutva.

```bash
# Az új clusteren a Kopia pod-ban:
kubectl -n volsync-system exec deploy/kopia -- \
  kopia repository connect s3 ...

kubectl -n volsync-system exec deploy/kopia -- \
  kopia snapshot list --all --owner @old-cluster
# kilistázza a régi cluster snapshot-jait

# Törlés:
kubectl -n volsync-system exec deploy/kopia -- \
  kopia snapshot delete <snapshot-id>

# Vagy hagyni a retention-nak (1 hónap múlva törölődik automatikusan).
```

**Default**: hagyni a retention-nak. Spórolt OVH storage idővel.

### Megőrzött infrastruktúra audit

Decom után az aktív infra:
- HP ProDesk 600 G6 DM (Talos node, IP `192.168.1.11`)
- M93p (még Proxmox+OMV VM, az átalakítás külön projekt — [14](./14-post-cutover.md))
- OpenWRT router (változatlan)
- Cloudflare (változatlan)
- OVH S3 (változatlan, csak az új cluster snapshot-jaival)
- 1Password vaults (változatlan, csak az aktív item-ekkel)

### Doc cleanup

Cutover után, decom UTÁN:
```bash
# A docs/migration/ mappa cutover utáni státusza:
# - README.md: a státusz táblát "completed"-re frissítjük
# - 13-rollback-and-decom.md: ide visszanézünk, hogy mi a teendő decom-kor

# A docs/migration/ MARAD a main branch-en mint historikus referencia.
# Nem törlünk semmit — egy év múlva is hasznos lehet.

# A többi docs/* (régi readme-k a K3s-ről, host-configuration stb.) frissítendő:
# - docs/k3s-readme.md → docs/talos-readme.md vagy törlés
# - docs/host-configuration.md → frissítés Talos-ra
# - docs/kubernetes-readme.md → frissítés Talos+Cilium+Flux Operator
# Ez **külön projekt** cutover utáni 1-2 hónappal.
```

## Open issues

- **Régi K3s VM Proxmox-snapshot megőrzés**: a Proxmox VM-et **NE töröld azonnal**, csak shut down. Tarts egy backup-ot 1 hónapig. Csak utána (ha semmilyen "ó, ez kellett volna" eset nem jött elő) töröld.
- **OVH S3 retention auditing**: Kopia retention beállítva (7 daily / 2 weekly / 1 monthly). Decom után, ha a régi cluster snapshot-jai már nem kellenek, manuális prune-olható.
- **Renovate régi PR-ek**: a `talos` branch merge után a Renovate aktívvá válik az új struktúrán. Régi PR-ek (`.github/renovate/*`-ra mutatók) bezárhatók manuálisan.
- **Régi Cloudflare tunnel routes vs új**: ha bármilyen route a régi cluster-specifikus volt (pl. `old.<domain>`), törlendő a Cloudflare Zero Trust dashboard-on.
- **DNS history**: a Cloudflare DNS Terraform (`provision/cloudflare/`) változatlan a cutover-nél — az IP-k DNS-ben **nem hardcoded**, hanem Cloudflare tunnel-en keresztül routolnak. Tehát nincs Terraform apply szükséges cutover-kor.
- **Régi `provision/kubernetes/` git history**: a mappa törlése a git history-t **nem** vágja, csak future commit-okból tűnik el. Ha valami referenciát akarsz őrizni, hagy meg egy "archive" branch-et: `git branch archive/k3s-provision <commit-előtt-törlés>`.
