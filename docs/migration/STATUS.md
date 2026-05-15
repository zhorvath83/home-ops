# Migration status

Élő státusz a K3s → Talos migráció állapotáról. Ez a doc gyors pillanatkép — a részletes terv a [README.md](./README.md)-ben és a `00`–`14` doc-okban van.

**Utolsó frissítés:** 2026-05-15

## TL;DR

**Hol tartunk:** A tervezési fázis (15 doc) elkészült. A `talos` branch még **nincs** megnyitva, megvalósítás még nem indult.

**Következő lépés:** Tervek átolvasása és véglegesítése → `talos` branch létrehozása → Phase 1 (hardver, hálózat).

## Fázis tracker

| # | Fázis | Doc | Status | Megjegyzés |
|---|---|---|---|---|
| — | Tervezés (docs) | [README](./README.md) | ✅ done | 15 doc kész, lazán kapcsolódó struktúra |
| — | `talos` branch létrehozása | — | ⏸ pending | Következő lépés |
| 1 | Hardver, hálózat, IP plan | [01](./01-hardware-and-network.md) | ⏸ pending | HP ProDesk 600 G6 DM beszerzés / fizikai setup |
| 2 | Talos bootstrap | [02](./02-talos-bootstrap.md) | ⏸ pending | machine config, install |
| 3 | Cilium CNI install + L2 announce | [03](./03-cilium-cni.md) | ⏸ pending | kube-proxy replacement |
| 4 | Bootstrap helmfile chain | [04](./04-bootstrap-helmfile.md) | ⏸ pending | `op inject` + helmfile |
| 5 | Flux Operator + FluxInstance | [05](./05-flux-operator.md) | ⏸ pending | |
| 6 | Repo refactor (apps struktúra) | [06](./06-repo-restructure.md) | ⏸ pending | bjw-s-labs minta |
| 7 | Components és shared resources | [07](./07-components-and-shared.md) | ⏸ pending | `kubernetes/components/` |
| 8 | Just migráció | [08](./08-just-migration.md) | ⏸ pending | Task → Just |
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
- **`talos`** — még nincs létrehozva, majd ezen épül ki az új cluster (big-bang cutover)
- Cutover-kor: `talos` → merge `main`, régi cluster 1-2 hétig standby, utána decom

## Becsült munka

- **Effektív munkaóra cutover-ig:** ~25-40h
- **Naptári idő:** ~2-4 hét esti+hétvégi munkával

## Open items / blocker

- Nincs aktív blocker — a tervezés zárása után indulhat a Phase 1.
- Hardver (HP ProDesk 600 G6 DM, P41 + P31 NVMe) beszerzés státusza külön követendő — a [01](./01-hardware-and-network.md) bemenete.

## Frissítési konvenció

- Minden fázis végén frissül a fenti tracker tábla.
- A `README.md` "Status — élő tracker" szekciója és ez a doc szinkronban marad — ez a részletesebb, a README-ben rövidebb pillanatkép.
- Új sub-task / blocker → ide az "Open items" alá.
