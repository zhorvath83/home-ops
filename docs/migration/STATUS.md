# Migration status

Élő státusz a K3s → Talos migráció állapotáról. Ez a doc gyors pillanatkép — a részletes terv a [README.md](./README.md)-ben és a `00`–`14` doc-okban van.

**Utolsó frissítés:** 2026-05-15

## TL;DR

**Hol tartunk:** Tooling foundation kész (mise + just + setup.sh), Talos config blueprint kész (schematic + machineconfig template + node patch + mod.just recipes). 1Password secrets feltöltés és HP első boot a következő.

**Következő lépés:**
1. ✅ 1Password `HomeOps/talos` item létrehozva (`just talos gen-secrets` egy paranccsal).
2. **Most**: `just talos download-image` → ISO USB-re (dd / balenaEtcher).
3. HP Windows boot leállítás → BIOS F9 → USB boot → Talos maintenance mode.
4. Maintenance mode IP-vel (DHCP-től kapott IP, nem feltétlenül `.11`!) inventory check — verifikáld hogy a `nodes/cp0-k8s.yaml.j2` értékei egyeznek a tényleges HP hardverrel:
   ```bash
   talosctl -n <IP> get links --insecure   # NIC MAC OUI ≟ 50:81:40:80:
   talosctl -n <IP> get disks --insecure   # NVMe modellek ≟ "PC801 NVMe SK hynix 1TB" + "PC711 NVMe SK hynix 1TB"
   ```
   Ha eltérés van: patcheld `kubernetes/talos/nodes/cp0-k8s.yaml.j2`-t (LinkAliasConfig MAC prefix + install.diskSelector.model).
5. `just talos apply-node <maintenance-IP> --insecure` → reboot → install. A reboot után már a `192.168.1.11`-en (DHCP rezervált) jelentkezik.
6. `just talos bootstrap` → `just talos kubeconfig`.
7. `kubectl get nodes` → `cp0-k8s NotReady` (CNI hiányzik még, normális, jön a (C) Cilium fázisban).

## Fázis tracker

| # | Fázis | Doc | Status | Megjegyzés |
|---|---|---|---|---|
| — | Tervezés (docs) | [README](./README.md) | ✅ done | 15 doc kész, lazán kapcsolódó struktúra |
| — | `talos` branch létrehozása | — | ✅ done | 2026-05-15 |
| 1 | Hardver, hálózat, IP plan | [01](./01-hardware-and-network.md) | 🟡 in-progress | HP megvan, Windows törlés szükséges, Talos USB készítendő |
| 2 | Talos bootstrap | [02](./02-talos-bootstrap.md) | 🟡 in-progress | machine config / mod.just kész; 1P secrets + HP első boot következik |
| 3 | Cilium CNI install + L2 announce | [03](./03-cilium-cni.md) | ⏸ pending | kube-proxy replacement |
| 4 | Bootstrap helmfile chain | [04](./04-bootstrap-helmfile.md) | ⏸ pending | `op inject` + helmfile |
| 5 | Flux Operator + FluxInstance | [05](./05-flux-operator.md) | ⏸ pending | |
| 6 | Repo refactor (apps struktúra) | [06](./06-repo-restructure.md) | ⏸ pending | bjw-s-labs minta |
| 7 | Components és shared resources | [07](./07-components-and-shared.md) | ⏸ pending | `kubernetes/components/` |
| 8 | Just migráció | [08](./08-just-migration.md) | 🟡 in-progress | foundation (mise+just+setup.sh) kész; `Taskfile.yml` törlés cutover-előtt |
| 9 | Renovate rewrite | [09](./09-renovate-rewrite.md) | ⏸ pending | `.renovaterc.json5` + fragmensek |
| 10 | OMV Ansible playbook | [10](./10-omv-ansible.md) | ⏸ pending | Csak cutover után |
| 11 | Data migration runbook | [11](./11-data-migration.md) | ⏸ pending | refs only |
| 12 | Cutover runbook | [12](./12-cutover-runbook.md) | ⏸ pending | éles cutover |
| 13 | Rollback és decommission | [13](./13-rollback-and-decom.md) | ⏸ pending | |
| 14 | Post-cutover megfigyelés | [14](./14-post-cutover.md) | ⏸ pending | 1-2 hét observation |

Legend: ✅ done · 🟡 in-progress · ⏸ pending · ❌ blocked · ⏭ skipped

## Tervezés — mit fednek a docok

| Doc | Témakör |
|---|---|
| [00](./00-architecture-decisions.md) | Architecture decisions (ADR-lite) — minden főbb döntés indoklással |
| [01](./01-hardware-and-network.md) | HP ProDesk 600 G6 DM hardver, IP plan, kábelezés |
| [02](./02-talos-bootstrap.md) | Talos machine config, install, etcd |
| [03](./03-cilium-cni.md) | Cilium kube-proxy replacement, L2 announce `.15-.25` pool |
| [04](./04-bootstrap-helmfile.md) | Bootstrap helmfile chain + `op inject` |
| [05](./05-flux-operator.md) | Flux Operator + FluxInstance, `cluster-vars` + `cluster-apps` |
| [06](./06-repo-restructure.md) | Repo refactor — bjw-s mintára |
| [07](./07-components-and-shared.md) | `kubernetes/components/` újrahasznosítható darabok |
| [08](./08-just-migration.md) | Task → Just, `.justfile` + `mod.just` |
| [09](./09-renovate-rewrite.md) | Renovate átírás fragmens-alapú struktúrára |
| [10](./10-omv-ansible.md) | M93p Proxmox tear-down + bare metal OMV install |
| [11](./11-data-migration.md) | VolSync snapshot + restore PVC-nként |
| [12](./12-cutover-runbook.md) | Éles cutover sorrend |
| [13](./13-rollback-and-decom.md) | Rollback path + régi cluster decom |
| [14](./14-post-cutover.md) | 1-2 hét observation window, Plex iGPU phase 2 |

## Branch model

- **`main`** — éles K3s clustert tükrözi, folyamatosan él
- **`talos`** — létrehozva, ezen épül ki az új cluster (big-bang cutover)
- Cutover-kor: `talos` → merge `main`, régi cluster 1-2 hétig standby, utána decom

## Becsült munka

- **Effektív munkaóra cutover-ig:** ~25-40h
- **Naptári idő:** ~2-4 hét esti+hétvégi munkával

## Open items / blocker

- Nincs aktív blocker.
- HP ProDesk 600 G6 DM **megvan**, jelenleg Windows van rajta → törlés szükséges (Talos install felülírja, nem külön lépés).
- PC801 + PC711 NVMe beszerzés státusza külön követendő — ha még nincs, a [01](./01-hardware-and-network.md) bemenete.
- ✅ 1Password `HomeOps/talos` item létrehozva (`just talos gen-secrets`, 2026-05-15).
- `kubernetes/talos/nodes/cp0-k8s.yaml.j2`: az `install.diskSelector.model` és `LinkAliasConfig` MAC OUI értékek konfigurálva — első HP boot után érdemes ellenőrizni `talosctl get disks --insecure` és `get links --insecure` outputjából (modell string + permanent MAC OUI).

## Frissítési konvenció

- Minden fázis végén frissül a fenti tracker tábla.
- A `README.md` "Status — élő tracker" szekciója és ez a doc szinkronban marad — ez a részletesebb, a README-ben rövidebb pillanatkép.
- Új sub-task / blocker → ide az "Open items" alá.
