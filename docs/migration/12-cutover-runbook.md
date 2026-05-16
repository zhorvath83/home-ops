# 12 — Cutover runbook (big-bang)

## Cél

Egyetlen cutover ablakban átkapcsolni a teljes éles stack-et a régi K3s clusterről az új Talos clusterre. Idő-becslés: **4-8 óra**, egy szombat este vagy vasárnap reggel.

## Pre-cutover kontroll (cutover előtti hét)

### T-7 nap: tervek véglegesítve

- [ ] Minden migráció doc (`docs/migration/00-14`) lezárva.
- [ ] `talos` branch létrehozva (`git checkout -b talos`).
- [ ] Új HP node fizikailag installálva ([01-hardware-and-network.md](./01-hardware-and-network.md)).
- [ ] BIOS beállítások ellenőrizve.

### T-5 nap: új cluster build a talos branch-en

- [ ] Talos schematic + ISO + USB elkészítve ([02-talos-bootstrap.md](./02-talos-bootstrap.md)).
- [ ] `just cluster-bootstrap cluster` lefutott, új cluster `Ready`.
- [ ] Cilium L2 announcement működik (test LoadBalancer service kap IP-t).
- [ ] Flux Operator + FluxInstance reconcile-olja a `talos` branch-et.
- [ ] **MINDEN PVC NÉLKÜLI app fut** (cert-manager, ESO, k8s-gateway, envoy-gateway, observability stack, etc.).

### T-3 nap: új cluster validation app-okkal

- [ ] Volsync component-ben `replicationdestination.yaml` és `pvc.yaml dataSourceRef` **be-kommentelve** a `talos` branch-en.
- [ ] Minden ks.yaml új formátumban (lásd [06-repo-restructure.md](./06-repo-restructure.md)).
- [ ] Új clusteren minden Flux Kustomization `Ready`, de PVC-s app-ok **HelmRelease-i pending** (mert PVC nem létezik még).
- [ ] **Egy próba-app restore** — egy alacsony rizikójú app-on (pl. wallos vagy actual) full lánc validation.

### T-1 nap (cutover előtti este): final preparations

- [ ] **App-level export-ok futtatva** a régi clusteren:
  - [ ] Paperless: `document_exporter` → mentés.
  - [ ] Mealie: web UI Backup → ZIP letöltés.
  - [ ] Plex: automatikus backup ellenőrzés (`Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db` létezik).
- [ ] **Régi cluster full VolSync snapshot lánc** (`just k8s snapshot-all` régi clusteren).
- [ ] Várj, amíg minden RS `lastSyncTime` ≤ 2 órás.
- [ ] **Bejelentés a háztartásnak**: nincs Plex, Paperless, *arr stack ma este 21:00-23:00 között.

## Cutover napja — T+0

### Időbecslés tájolóként

| Fázis | Idő |
|---|---|
| Régi cluster freeze + utolsó snapshot + shutdown | 15-20 perc |
| Új cluster bootstrap RD trigger (mind 17) | 10-15 perc (3-4 GB teljes restore) |
| App smoke test | 1-2 óra |
| Cloudflare tunnel switch | 5 perc |
| **Total** | **1.5-3 óra** |

**Indoklás a rövid restore időre**: a teljes OVH snapshot ~3-4 GB. 1 GbE-n ~30-40 mp letöltés (a Kopia decompression overhead-del ~1-2 perc per snapshot, párhuzamosan futtatva 10-15 perc az összes 17 PVC-re).

### Stage 1: Régi cluster freeze + shutdown

T+0:00 — Régi cluster utolsó snapshot, majd a VM lekapcsolása.

```bash
# Régi cluster kubeconfig:
export KUBECONFIG=~/.kube/config-old

# Suspend minden HR (megáll minden writeable app):
for hr in $(kubectl get hr -A -o jsonpath='{.items[*].metadata.name}'); do
  ns=$(kubectl get hr -A -o jsonpath="{.items[?(@.metadata.name=='$hr')].metadata.namespace}")
  flux suspend hr "$hr" -n "$ns"
done

# Várj 30 mp, hogy a pod-ok megálljanak / DB sync-eljen:
sleep 30

# Utolsó manual snapshot minden RS-en:
ts=$(date +%s)
for app in $(kubectl get rs -n default -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n default patch rs "$app" --type merge \
    -p "{\"spec\":{\"trigger\":{\"manual\":\"final-$ts\"}}}"
done

# Várj amíg minden snapshot fut és kész:
kubectl -n default get rs -o wide --watch
# (Ctrl+C, ha mind kész — `lastSyncTime` frissebb mint a `manual` érték)

# K3s VM SHUTDOWN — Proxmox web UI vagy SSH:
ssh 192.168.1.6 sudo poweroff
# Vagy Proxmox-on: qm shutdown <vmid>

# Validation — IP-k szabad:
ping -c 1 192.168.1.6      # no response (régi K3s)
ping -c 1 192.168.1.19     # no response (régi LB IP)
```

**Várható idő**: 15-20 perc (a snapshot diff kicsi, ~3-4 GB teljes méret).

### Stage 2: DNS állapot — NINCS változtatás

**A DNS rekordok és a dnsmasq config változatlan.** Mivel a LB IP-k azonosak (`.18`, `.19`, `.20`), és a Cloudflare tunnel ID/token is ugyanaz, csak a cloudflared pod helye változik:
- Régi cluster: cloudflared pod lekapcsolva (VM shutdown miatt).
- Új cluster: cloudflared pod elindul, ugyanahhoz a tunnel-hez csatlakozik.

A LAN dnsmasq `server=/<INTERNAL_DOMAIN>/192.168.1.19` változatlan — az új cluster Cilium L2 announcement-je bejelentkezik a `.19`-re. **Nincs router-side módosítás**.

### Stage 3: Új cluster restore lánc indítás

T+0:20 — Trigger minden bootstrap RD-t az új clusteren.

```bash
export KUBECONFIG=~/.kube/config-new

# Trigger all bootstrap RD-s:
just k8s restore-all

# Vagy egyenként:
for app in actual bazarr calibre-web-automated homepage isponsorblocktv maintainerr mealie paperless plex prowlarr qbittorrent radarr resticprofile seerr sonarr wallos; do
  just k8s restore "$app" default
done

# Status watch:
watch -n 5 'kubectl get replicationdestinations -A | grep bootstrap'
```

**Várható idő**: 10-15 perc (párhuzamos restore, kis snapshot méret).

### Stage 4: App pod-ok indulása

T+0:35 — Miután az RD-k befejezték, a PVC-k Bound állapotba kerülnek, és a Flux HelmRelease-ek elindítják az app pod-okat.

```bash
# Várj amíg minden HR Ready:
kubectl get hr -A
# minden Ready=True

# Pod-ok:
kubectl get pods -A
# minden Running 1/1 vagy Completed Job
```

Ha valami nem indul:
```bash
kubectl -n default describe hr <app>
kubectl -n default describe pod -l app.kubernetes.io/name=<app>
kubectl -n default logs <pod> --previous
```

Tipikus hibák:
- **PVC nem Bound**: az RD még fut. Várj.
- **Secret hiányzik**: ExternalSecret nem sync-elt. `kubectl -n default get es` ellenőrzés. Trigger: `just k8s sync-es default <app>-secret`.
- **ConfigMap substitution miss**: cluster-settings nem frissült. `kubectl -n flux-system get cm cluster-settings -o yaml`.

### Stage 5: App-szintű smoke test

T+0:45 — Minden app-on alap funkciók ellenőrzése.

#### Smoke test checklist

| App | Smoke test |
|---|---|
| Plex | Web UI bejön, library látható, **video play-able** (transcoding teszt) |
| Sonarr | Web UI bejön, sorozatok látszanak, indexer health OK |
| Radarr | Web UI bejön, filmek látszanak |
| Prowlarr | Indexer-ek health OK |
| Bazarr | Sonarr+Radarr integration OK, felirat keresés működik |
| qBittorrent | Web UI bejön, torrent-ek listája megvan (status: stopped, manuál resume) |
| Seerr | Web UI bejön, Plex integration OK |
| Maintainerr | Web UI bejön, rules listája megvan |
| Paperless | Web UI bejön, dokumentum kereshető, OCR fut új dokumentumra |
| Mealie | Web UI bejön, receptek látszanak |
| Actual | Web UI bejön, accounts látszanak |
| Wallos | Web UI bejön, subscription-ök látszanak |
| Calibre-Web | Web UI bejön, könyvek listája |
| Home Gallery | Web UI bejön (friss állapot, gallery üres vagy újra-scan) |
| Homepage | Dashboard render-elődik, widgets élnek |
| isponsorblocktv | Backend service működik (logs nézés) |
| resticprofile | Cron job lefut, log látszik |

#### Smoke test parancsok

```bash
# Web UI port-forward (envoy-gateway HTTPRoute-on keresztül még nem érhetők el LAN-ról cutover előtt):
kubectl -n default port-forward svc/plex 32400:32400 &
open http://localhost:32400/web

# Vagy belső LAN-on, ha új k8s-gateway DNS-cutover megtörtént (Stage 6):
open https://plex.<INTERNAL_DOMAIN>
```

### Stage 6: Cloudflare tunnel "switch"

T+2:15 — A régi K3s VM már shutdown, a régi cloudflared pod elérhetetlen. Cloudflare automatikusan átvált az új cluster cloudflared pod-jára (ugyanaz a tunnel ID, csak más connector).

```bash
# Új clusteren a cloudflared már fut a bootstrap után — ellenőrzés:
KUBECONFIG=~/.kube/config-new
kubectl -n networking get pods -l app.kubernetes.io/name=cloudflare-tunnel
# Running

kubectl -n networking logs deploy/cloudflare-tunnel | grep "Registered connector"
# Registered tunnel connection
```

A külső forgalom (`*.<CLOUDFLARE_DOMAIN>`) az új clusterre megy — **automatikus**, nincs aktív cutover lépés.

#### k8s-gateway split-DNS (LAN)

**Nincs DNS változtatás szükséges** — a `LB_K8S_GATEWAY_IP` `.19` IP **változatlan** az új clusteren is (Cilium L2 announcement bejelentkezik az `.19`-re a HP MAC-jével, miután a régi K3s VM lekapcsolódott). Az OpenWRT dnsmasq config marad:
```
server=/<INTERNAL_DOMAIN>/192.168.1.19
```

#### Validation

```bash
# Külső (Cloudflare):
curl -I https://homepage.<CLOUDFLARE_DOMAIN>
# 200 OK, server: envoy

# Belső (LAN):
dig homepage.<INTERNAL_DOMAIN>
# A 192.168.1.18 (envoy-internal — változatlan IP, új cluster mögött)

# ARP table check (másik LAN gépről):
arp -a | grep "192.168.1.18\|192.168.1.19\|192.168.1.20"
# Az IP-k a HP node MAC-jét mutatják (nem a régi K3s VM-ét)
```

### Stage 7: FluxInstance ref switch

T+2:30 — A `flux-instance` HelmRelease értékeinek frissítése: `talos` branch → `main` branch (vagy a `talos → main` merge a git-en).

**Két út**:

#### Út A: Talos branch merge main-be

```bash
git checkout main
git merge --no-ff talos
git push
```

A FluxInstance továbbra is `refs/heads/main`-re mutat (de a talos branch változásaival együtt — minden új ott van).

#### Út B: FluxInstance ref váltás közvetlen

Ha a talos branch még külön akarjuk tartani egy ideig (kockázatkezelés), a FluxInstance HR-t át kell írni:
```yaml
# kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml
spec:
  values:
    instance:
      sync:
        ref: refs/heads/main                  # vissza main-re
```

A talos branch megtartható debug-ra; minden új commit main-be megy.

**Default**: **Út A** — clean state, talos branch beolvad.

### Stage 8: Régi cluster freeze final + stay-alive

T+3:00 — A régi cluster **lekapcsolva, de NEM törölve**.

```bash
# Régi cluster kubectl:
KUBECONFIG=~/.kube/config-old kubectl get nodes
# Még fut, de minden HR suspended.

# Régi cluster Cloudflare tunnel ki van kapcsolva.
# Régi cluster k8s-gateway nincs használva (LAN dnsmasq már az újra mutat).
# A régi cluster csendben pihen — gyorsan visszakapható, ha kell.
```

### Stage 9: Háztartás bejelentés

T+3:30 — "Új clusterre átálltunk. Ha valami furcsa: szólj." Plex, Paperless, *arr működnek.

## Post-cutover (T+1 nap)

- [ ] **Cutover utáni snapshot az ÚJ clusteren** — első RS-trigger, hogy a Kopia repository-ban legyen friss snapshot az új cluster identity-vel is.
- [ ] **Monitoring dashboards check** — Prometheus, Grafana, alerts.
- [ ] **Backup verify** — egy random app PVC restore-test egy másik (test) namespace-be.
- [ ] **Üzem 1-2 hét** ([14-post-cutover.md](./14-post-cutover.md)).

## Rollback (ha valami ELROMLIK)

Lásd [13-rollback-and-decom.md](./13-rollback-and-decom.md). Rövid forma:

1. **DNS visszafordítás** — Cloudflare tunnel + dnsmasq config vissza a régi cluster IP-jére.
2. **Régi cluster resume** — `flux resume hr -A` régi clusteren.
3. **Új cluster suspend** — `flux suspend ks cluster-apps` új clusteren.

Időigény: ~30 perc.

## Open issues

- **Cloudflare tunnel double-connector overlap**: a régi és új cloudflared egy időben fut a tunnel mögött. Cloudflare load balancing valószínűleg OK-é, de **érdemes ezt T-1 napon tesztelni** — régi clusteren `flux resume` az új cluster cloudflare-tunnel-jét manuálisan, és látni, hogy mindketten csatlakoznak.
- **DNS TTL**: a Cloudflare DNS recordok TTL-je (jelenlegi 300s vagy default), az LAN dnsmasq cache (300s default). Cutover után **5-10 perc** lehet, mire minden kliens átáll.
- **App-level export PVC-n**: a Paperless export és a Mealie ZIP a régi cluster PVC-n él. A VolSync snapshot együtt menti, restore után az új cluster PVC-n elérhető — egyébként nem.
- **Cutover utáni régi cluster ne reconcile-oljon**: a régi cluster Flux-ja a régi `home-ops-kubernetes` GitRepository-ra mutat (main branch régi struktúrával). Ha valaki véletlen commit-ol main-re a cutover NAPJÁN, a régi cluster reconcile-ol — de minden HR suspended, így nem aktívvá válik. Mégis: cutover napon **NE commit-olj main-re** semmit, csak `talos` branch-re.
- **Régi cluster k8s-gateway DNS válaszol-e még?**: a `k8s-gateway` régi clusteren még fut (suspend csak HR-en — a Service és Deployment él). A LAN dnsmasq már nem oda mutat, de ha valaki direct query-zi a régi IP-t, válaszolna. Ártalmatlan.
- **Régi NFS mountok app pod-okból**: az NFS share a M93p-n változatlan. Új cluster app pod-jai ugyanazt a `192.168.1.10:/<path>`-t mountolják. Nincs migrációs lépés ehhez.
- **Renovate aktivitás cutover napon**: capacities, hogy ne nyisson PR-t épp a cutover ablakban — Renovate `schedule: ["after 10pm on Sunday"]` opcionálisan beállítható erre a napra. **Nem kötelező**, de jó ötlet.
