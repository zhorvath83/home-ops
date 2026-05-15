# 01 — Hardver, hálózat, IP plan

## Cél

A fizikai infrastruktúra cél-állapotát rögzítjük: melyik gép, milyen szerepben, milyen IP-vel, milyen storage szervezéssel, milyen BIOS beállításokkal.

## Hardver áttekintés

### HP ProDesk 600 G6 Desktop Mini — Talos node (`main` cluster)

| Komponens | Spec |
|---|---|
| CPU | Intel Core i7-10700T (8c/16t, Comet Lake, 35W) |
| iGPU | Intel UHD Graphics 630 (QuickSync H.264/HEVC 8+10bit, NO AV1) |
| RAM | 64 GB (2× 32 GB SODIMM DDR4-3200) |
| NIC | Intel I219-V vagy I219-LM (1× 1 GbE, `e1000e` driver) |
| WLAN slot | M.2 2230 (üres vagy Intel AX201) |
| NVMe slot #1 | M.2 2280 PCIe **Gen3 x4** |
| NVMe slot #2 | M.2 2280 PCIe **Gen3 x4** |
| SATA bay | 1× 2.5" belső |
| TPM | 2.0 |
| Chipset | Intel Q470 |
| Idle | ~10-15 W |
| Load | ~35-45 W |

**Kritikus megállapítás:** A Q470 chipset és Comet Lake CPU **NEM tud PCIe Gen4**-et. Mindkét M.2 slot Gen3 x4 (~3500 MB/s seq fal). A SK hynix PC801 (Gen4 SSD) bedugva Gen3 sebességen fog futni — visszafelé kompatibilis, semmi gond, csak az "advertised 7000 MB/s" elveszik.

### Lenovo M93p Tiny — bare metal OMV (M93p)

| Komponens | Spec |
|---|---|
| CPU | Intel Core i5/i7-4xxxT (Haswell, ~2014) |
| RAM | 16 GB (max officially) |
| NIC | Intel I217-LM (1× 1 GbE) |
| Storage | 2.5" SATA HDD/SSD + mSATA (OS) |
| External | USB DAS, Toshiba Enterprise HDD |
| Idle | ~8-10 W |

A jelenlegi Proxmox+OMV VM **leszedésre kerül** a cutover után. Bare metal OMV install Ansible playbook-kal. Részletek: [10-omv-ansible.md](./10-omv-ansible.md).

### SK hynix NVMe-k

| Spec | PC801 | PC711 |
|---|---|---|
| Kapacitás | 1 TB | 1 TB |
| Interfész | PCIe 4.0 x4 (HP-n Gen3-ra korlátozva) | PCIe 3.0 x4 |
| Seq read/write | 7000/6500 (Gen3-on ~3500/3200 valószínű) | 3500/3200 |
| Random IOPS (4K Q32) | 1.4M / 1.3M | 570K / 600K |
| DRAM cache | 1 GB LPDDR4 | 1 GB LPDDR4 |
| TBW | 750 | 750 |
| NAND | 176-layer TLC | 128-layer TLC |
| SLC cache | ~114 GB dynamic | ~92 GB dynamic |

**Szétosztás:** Lásd [AD-012](./00-architecture-decisions.md#ad-012-két-nvme-szétosztás--gyorsabb-az-osetcd-re-lassabb-a-pvc-re).
- **PC801 (Gen4)** → Talos OS install disk + etcd + EPHEMERAL (`install.disk`)
- **PC711 (Gen3)** → democratic-csi data disk (`/var/mnt/extra-disk`)

A két M.2 slot közül a primary slot (általában az alaplaphoz közelebbi) kapja a **PC801**-et (OS, boot priority), a másodlagos a **PC711**-et. Talos `install.disk` mezőben `/dev/disk/by-id/nvme-...` formátum, nem `/dev/nvme0n1` (boot-order független).

## Hálózati terv

### IP cím szétosztás (`192.168.1.0/24` LAN)

| IP | Eszköz | Megjegyzés |
|---|---|---|
| 192.168.1.1 | OpenWRT router | DHCP server, gateway, k8s-gateway DNS resolver target |
| 192.168.1.4 | Proxmox PVE-1 | **DECOM** cutover után (régi K3s host) |
| 192.168.1.5 | Proxmox PVE-0 | **DECOM** cutover után |
| 192.168.1.6 | Régi K3s VM | **DECOM** cutover után (teszt alatt shutdown) |
| 192.168.1.10 | M93p (jelenleg Proxmox+OMV VM, később bare metal OMV) | NAS, NFS server |
| 192.168.1.11 | **HP Talos node (új `main` cluster)** | **ÚJ** |
| 192.168.1.15-25 | Cilium L2 announcement pool | 11 db LB IP |
| 192.168.1.18 | LB_ENVOY_INTERNAL_IP (változatlan) | Cilium L2 announcement |
| 192.168.1.19 | LB_K8S_GATEWAY_IP (változatlan) | Cilium L2 announcement |
| 192.168.1.20 | LB_MEDIASERVER_IP (változatlan) | Cilium L2 announcement |

**Megjegyzés a HP IP-jére**: A HP node IP-je `192.168.1.11` (új). A régi K3s VM IP-je `192.168.1.6` — a teszt időszak alatt a K3s VM **lekapcsolva** marad, így nincs IP-konfliktus. A DNS rekordok és OpenWRT dnsmasq config **változatlan**, mert az LB IP-k (`.18-.20`) megegyeznek a régi tartománnyal.

### LoadBalancer IP allokáció (Cilium L2)

A `cluster-settings.yaml`-ban (új cluster):
```yaml
data:
  LB_POOL_RANGE_START: "192.168.1.15"
  LB_POOL_RANGE_END: "192.168.1.25"
  LB_ENVOY_INTERNAL_IP: "192.168.1.18"   # megegyezik a jelenlegivel
  LB_K8S_GATEWAY_IP: "192.168.1.19"      # megegyezik
  LB_MEDIASERVER_IP: "192.168.1.20"      # megegyezik
```

A pool `.15-.25` tartomány (11 IP), ezen belül a meglévő szolgáltatás VIP-ek (`.18/.19/.20`) változatlanok maradnak. A `LB_ENVOY_EXTERNAL_IP` **nem szükséges** — az `envoy-external` Gateway nem kap LAN LoadBalancer IP-t, csak a Cloudflare Tunnel kapcsolódik a ClusterIP service-éhez.

Az L2 announcement workflow:
1. Régi K3s VM **shutdown** a teszt elején.
2. HP cluster Cilium átveszi az `.18-.20` IP-ket (`.18` ARP-pal bejelentkezik, stb.).
3. Ha rollback: HP powerdown → K3s power on → IP-k visszamenadzselődnek a MetalLB-vel.

### Pod és service CIDR

```yaml
CLUSTER_POD_CIDR: "10.244.0.0/16"   # új (régi: 10.42.0.0/16)
CLUSTER_SVC_CIDR: "10.245.0.0/16"   # új (régi: 10.43.0.0/16)
```

A változtatás indoka: cutover ablakban mindkét cluster él, IP-konfliktus elkerülése a router routing táblájában (ha pod CIDR-t route-olnánk át).

### Cluster control plane endpoint

```
https://192.168.1.11:6443
```

Single-node, VIP nincs. A `kubeconfig` server URL ezt használja.

### Hálózati topológia diagram

```
                ┌──────────────────┐
                │   OpenWRT 1.1    │ (DHCP, DNS forwarder)
                └────────┬─────────┘
                         │ 1 GbE switch
        ┌────────────────┼─────────────────┬──────────────┐
        │                │                 │              │
   ┌────▼────┐     ┌────▼─────┐     ┌─────▼──────┐  ┌────▼─────┐
   │ HP 1.11 │     │ M93p 1.10│     │ régi K3s   │  │ kliens   │
   │ Talos   │     │ OMV      │     │ VM 1.6     │  │ desktop  │
   │ Cilium  │     │ NFS srv  │     │ (shutdown  │  │ /laptop  │
   │ LB pool:│     │          │     │  during    │  │          │
   │ .18-.20 │     │ + USB    │     │  testing)  │  │          │
   └─────────┘     │   DAS    │     └────────────┘  └──────────┘
                  └──────────┘
```

## BIOS beállítások a HP-n

A HP ProDesk BIOS-ba boot közben **F10** billentyűvel lehet belépni. A fejezet négy alszekcióra bontva tárgyalja a beállításokat:

- **Cél**: a Talos bare metal install végállapota — minden érték, ami a node helyes működéséhez kell, függetlenül attól, hogy jelenleg mi van beállítva.
- **Javasolt (de nem kötelező)**: kényelmi / kisebb hardening opciók, amiket nem feltétlenül muszáj módosítani.
- **Jelenlegi állapot (fotók alapján)**: a 2026-05-15-i BIOS-fotózás eredménye + a delta táblázat (csak azokat a sorokat sorolja fel, amik még _nincsenek_ célállapotban).
- **BIOS firmware update**: firmware-verzió helyzet.

### Cél (Talos bare metal kompatibilitás)

| Menüpont | Érték | Indok |
|---|---|---|
| Security → System Security → **Virtualization Technology (VTx)** | **Enabled** | KVM / nested VM ha kell, alapszintű |
| Security → System Security → **Virtualization Technology for Directed I/O (VTd)** | **Enabled** | IOMMU, PCI passthrough alap |
| Security → **Secure Boot Configuration** | **Disabled** | Talos saját aláírást használ |
| Advanced → Boot Options → **Fast Boot** | **Disabled** | Megbízható NIC init, PXE/USB boot |
| Advanced → Built-in Device Options → **Wake On LAN** | **Boot to Hard Drive** | S4/S5 WoL aktív, távoli felébresztés OS-re |
| Advanced → Power Management → **S5 Maximum Power Savings** | **Disabled** | WoL csak akkor működik S5-ben, ha ez OFF |
| Advanced → Boot Options → **After Power Loss** | **Power On** | Headless restart áramkimaradás után |
| Security → **TPM Device** | **Available (Enabled)** | TPM 2.0 — későbbi disk encryption opcióhoz |
| Advanced → System Options → **Hyperthreading (HT)** | **Enabled** | 16 logical CPU |
| Advanced → System Options → **Configure Storage Controller for RAID** | **Disabled** | NVMe AHCI/direct, Talos kernel a chipset RAID-et nem támogatja |
| Advanced → System Options → **Configure Storage Controller for Intel Optane** | **Disabled** | Nem használunk Optane-t |
| Advanced → System Options → **DMA Protection** | **Enabled** | IOMMU-alapú DMA védelem |
| Advanced → System Options → **Pre-boot DMA protection** | **Thunderbolt Only** | Hagyományos belső buszok mehetnek, csak a hot-plug Thunderbolt blokkolva |
| Advanced → HP Sure Recover → **HP Sure Recover** | **Disabled** | Windows-specifikus, Talos node-on nincs értelme, attack surface |
| Advanced → System Options → **HP Application Driver** | **Disabled** | Windows-only WPBT injection, Talos-on irreleváns |
| Advanced → Remote Management Options → **Intel AMT** | **Disabled** | Nem használjuk, ME/AMT-felület csökkentés (lásd Hardening) |

### Javasolt (de nem kötelező)

| Menüpont | Érték | Indok |
|---|---|---|
| Advanced → Boot Options → **USB Storage Boot** | **Enabled** | Recovery USB-ről bootolhatóság (jelenleg már be) |
| Advanced → Boot Options → **NumLock on at boot** | **Enabled** | Konzol billentyűzet praktikum |

**BIOS Administrator Password**: tudatosan **nem** állítunk be jelszót. Ennek következménye, hogy a `Sure Start BIOS Settings Protection` nem aktiválható; a többi Sure Start védelem (Dynamic Runtime Scanning, Secure Boot Keys Protection, Enhanced HP Firmware Runtime Intrusion Prevention) viszont továbbra is aktív. Fizikai hozzáférés esetén a BIOS-ba szabadon be lehet lépni — a homelab fenyegetésmodellben ezt elfogadjuk.

### Jelenlegi állapot (2026-05-15, fotók alapján)

A telepítés előtt a BIOS-t végigfotóztuk. A `Cél` szekció szerinti **kötelező változtatások**:

| Menüpont | Jelenlegi | Cél | Megjegyzés |
|---|---|---|---|
| Advanced → Boot Options → **Fast Boot** | ✓ Enabled | ✗ **Disabled** | NIC / USB init késleltetése Talos installer USB-hez |
| Advanced → Boot Options → **After Power Loss** | Power Off | **Power On** | Headless restart áramkimaradás után |
| Advanced → HP Sure Recover (és minden alpontja) | ✓ Enabled | ✗ **Disabled** | Windows-only HP-recovery, Talos node-on nem kell, hálózati boot-csatorna lezárása |
| Advanced → System Options → **HP Application Driver** | ✓ Enabled | ✗ **Disabled** | Windows-only WPBT-injection, Talos node-on irreleváns |
| Advanced → Remote Management Options → **Intel AMT** | ✓ Enabled | ✗ **Disabled** | I219-LM AMT-t nem használjuk, ME-felület csökkentés |
| Advanced → Boot Options → **Network (PXE) Boot** | ✓ Enabled | ✗ **Disabled** | Nem tervezünk PXE bootstrapot; boot-csatorna lezárása |
| Advanced → Boot Options → **IPv6 during UEFI Boot** | ✓ Enabled | ✗ **Disabled** | PXE-vel együtt jár, nem szükséges |
| Advanced → System Options → **M.2 WLAN/BT** | ✓ Enabled | ✗ **Disabled** | M.2 2230 slot üres (a WLAN modul nincs beszerelve), opció letiltása |
| Security → BIOS Sure Start → **Verify Boot Block on every boot** | ✗ Disabled | ✓ **Enabled** | Sure Start minden bootnál ellenőrzi a boot block integritását (kis lassulás, +integritás) |

**Már célállapotban (ne módosítsd):**

- Secure Boot: Disabled
- VTx, VTd, Hyperthreading, Turbo-boost, DMA Protection: Enabled
- Storage Controller RAID / Intel Optane: Disabled (AHCI/NVMe direct)
- Pre-boot DMA protection: Thunderbolt Only
- M.2 SSD 1 / M.2 SSD 2: Enabled
- Wake On LAN: Boot to Hard Drive
- Power Management: Runtime PM / Extended Idle / SATA PM / PCIe PM mind enabled, S5 Maximum Power Savings disabled
- TPM 2.0: Available, State enabled
- Sure Start: Dynamic Runtime Scanning + Secure Boot Keys Protection + Enhanced HP Firmware Runtime Intrusion Prevention enabled
- Physical Presence Interface, System Management Command: enabled
- Remote HP PC Hardware Diagnostics → Scheduled / Execute On Next Boot: Disable

**További hardening opció — visszafordíthatatlan, megfontolandó:**

- **Security → Utilities → Absolute Persistence Module — Permanent Disable**: jelenleg `No` (modul `Inactive`). Az Absolute (régen Computrace) egy firmware-szintű OEM tracking/anti-theft modul, ami minden bootnál képes letöltődni és Windows-ba telepedni; saját laptop/desktop esetén ez attack surface. A `Permanent Disable` **egyirányú** művelet (a flag-et a firmware sosem engedi vissza). Mivel Talos node-on Windows agent nincs és nem is lesz, a permanens letiltás tiszta nyereség — de csak akkor csináld meg, ha biztos, hogy ez a gép nem fog visszamenni vállalati Absolute-ot használó környezetbe. **Ajánlott**: állítsd be a következő bootciklus alatt.

### BIOS firmware update

**A BIOS már a legfrissebb verzión van** ezen a HP-n. A telepítés előtti teendő a fenti `Jelenlegi állapot` táblázat szerinti 9 kötelező módosítás végrehajtása (Fast Boot, After Power Loss, HP Sure Recover, HP Application Driver, Intel AMT, PXE Boot, IPv6 during UEFI Boot, M.2 WLAN/BT, Verify Boot Block on every boot), plusz opcionálisan az Absolute Permanent Disable.

## NVMe fizikai beszerelés sorrend

1. **Power off**, AC ki.
2. **Talp eltávolítás** (általában 1 csavar a hátlapon).
3. **Mind a két M.2 slot azonosítás** (alaplap felirata: `M.2_1` és `M.2_2`, vagy hasonló).
4. **PC801 az elsődleges slotba** (M.2_1, közelebbi az alaplap éléhez, általában a CPU-hűtő mellé) → ez lesz a Talos OS install disk (+ etcd, EPHEMERAL).
5. **PC711 a másodlagos slotba** (M.2_2) → ez lesz a democratic-csi data disk.
6. Csavarok visszahúzás (M.2 sztender csavarok, NE húzd túl).
7. Talp vissza, AC be, boot, BIOS-ban ellenőrizd, hogy mindkét NVMe felismerve.

**Tipp**: A BIOS Storage screen mutatja a felismert disk-eket model és serial alapján — innen tudod, melyik fizikai SSD melyik `nvme0n1` / `nvme1n1`. Jegyezd fel a serial → device mapping-et, a Talos `install.disk` mezőhöz `nvme-<model>_<serial>` formátumban kell.

## Hálózati eszköz előkészítés

### OpenWRT router

A `192.168.1.11` IP-t **statikusan rezerváld** a router DHCP-jén, a HP node MAC címére (MAC-t az NIC alján olvasd le, vagy első boot után `ip link show`).

```sh
# OpenWRT példa (LuCI vagy CLI):
uci add dhcp host
uci set dhcp.@host[-1].name='talos-main'
uci set dhcp.@host[-1].mac='XX:XX:XX:XX:XX:XX'
uci set dhcp.@host[-1].ip='192.168.1.11'
uci commit dhcp
service dnsmasq restart
```

### DNS

A `k8s-gateway` LAN-on belüli DNS-t szolgáltat HTTPRoute-okra. Az OpenWRT router `dnsmasq` konfigja **változatlan** — mivel a `LB_K8S_GATEWAY_IP` `.19` ugyanaz az IP marad az új clusteren. A Cilium L2 announcement bejelentkezik az `.19`-re a HP node MAC-jével.

```sh
# OpenWRT dnsmasq config (változatlan):
# /etc/config/dhcp vagy /etc/dnsmasq.d/k8s-gateway.conf
server=/<INTERNAL_DOMAIN>/192.168.1.19
```

### NFS export (M93p)

A jelenlegi OMV NFS exportok IP whitelist-jét kell **kibővíteni** a HP node IP-jére (`192.168.1.11`), hogy az új cluster pod-jai is mountolni tudják. Ezt az OMV UI-ban manuálisan állítjuk be cutover ELŐTT. Ha az export `192.168.1.0/24` CIDR-re engedélyez, nincs változtatás.

## Validation checklist (HP bekapcsolás után)

- [ ] BIOS-ban mindkét NVMe felismerve, modell + serial olvashatóan (M.2 SSD 1 = PC801 `SJBAN46291390A74W`, M.2 SSD 2 = PC711 `KDA8N47141100896P`).
- [ ] BIOS-ban VT-d enabled, Secure Boot disabled.
- [ ] BIOS delta végrehajtva: Fast Boot = Disabled, After Power Loss = Power On, HP Sure Recover = Disabled, HP Application Driver = Disabled, Intel AMT = Disabled, PXE Boot = Disabled, IPv6 during UEFI Boot = Disabled, M.2 WLAN/BT = Disabled, Sure Start Verify Boot Block on every boot = Enabled.
- [ ] (Opcionális, irreverzibilis) Absolute Persistence Module → Permanent Disable.
- [ ] NIC link up, MAC felismerhető OpenWRT-n.
- [ ] DHCP reserved IP `192.168.1.11` adva a HP MAC-jére.
- [ ] Talos installer USB-ről boot-olható (későbbi lépés).
- [ ] Ping `192.168.1.11` egy másik gépről átmegy (Talos boot után).

## Rollback

Ha a hardver setup problémás:
- BIOS reset (F10 → Restore Defaults), újrakonfigurálás.
- NVMe-ket swappelni a slotok között, ha boot order furcsán működik.
- Talos installer USB recovery módra váltani (lásd [02-talos-bootstrap.md](./02-talos-bootstrap.md) Rollback szekció).

## Open issues

- **NIC variáns** — **megerősítve: Intel I219-LM** (a BIOS-ban az `Advanced → Remote Management Options → Intel AMT` menüpont látszik és bekapcsolható; az I219-V-n ez nincs). Talos kernel `e1000e` driver kompatibilis. AMT-t **nem** használjuk, a BIOS-ban kikapcsoljuk (lásd `BIOS beállítások`).
- **iGPU passthrough Plex pod-ba** — Talos `siderolabs/i915` extension benne marad a schematic-ban, de a Plex pod-spec NEM kapja meg a `/dev/dri` mount-ot a cutover részeként. Plex HW transcode bevezetése **post-cutover phase 2** feladat, részletek a [14-post-cutover.md](./14-post-cutover.md) "Phase 2" szekcióban.
- **WLAN modul jelenléte** — **megerősítve: nincs M.2 2230 WLAN modul a gépben.** A BIOS-ban a `M.2 WLAN/BT` opció jelenleg ✓ Enabled, de mivel fizikailag nincs kártya, az opciót `Disabled`-re tesszük (lásd `BIOS beállítások` kötelező delta).
