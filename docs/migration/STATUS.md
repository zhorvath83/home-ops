# Migration status

Élő státusz a K3s → Talos migráció állapotáról. Ez a doc gyors pillanatkép — a részletes terv a [README.md](./README.md)-ben és a `00`–`14` doc-okban van.

**Utolsó frissítés:** 2026-05-16

## TL;DR

**Hol tartunk:** Talos node fent (`cp0-k8s NotReady`, CNI hiányzik). Phase 3 manifestek (Cilium app subtree) és a teljes bjw-s naming + layout refactor a `talos` branch-en kész. A következő nagy lépés a Phase 4 — bootstrap helmfile chain — ami a Cilium-tól a Flux Instance-ig minden release-t telepít, és élesíti a clustert.

**Mit végeztünk el a `talos` branchen idáig (Phase 3 + Phase 5/6 részmunkák, 2026-05-16):**

- ✅ Talos schematic + machineconfig template + node patch + `just talos` recipe-ek.
- ✅ Talos node bootolt, kubeconfig megvan, `cp0-k8s NotReady`.
- ✅ Cilium app-subtree: `kubernetes/apps/kube-system/cilium/{ks.yaml,app,config}` — bjw-s-stílusú HelmRelease (Cilium 1.19.4, netkit datapath, kubeProxyReplacement, L2 announce), `CiliumLoadBalancerIPPool` (`.15-.25`), `CiliumL2AnnouncementPolicy` (`^net0$`).
- ✅ Cilium regisztráció a `kubernetes/apps/kube-system/kustomization.yaml`-ben.
- ✅ bjw-s naming refactor minden Flux Kustomization-en (41 ks.yaml): `cluster-apps-<X>` → `<X>`, `home-ops-kubernetes` → `flux-system`, `sourceRef.namespace: flux-system` mindenhol, schema URL `kubernetes-schemas.pages.dev`-re.
- ✅ `flux/cluster/ks.yaml` létrehozva (cluster-vars + cluster-apps + HelmRelease default patches, doc 05 spec szerint).
- ✅ Legacy bootstrap fájlok törölve: `flux/apps.yaml`, `flux/config/{cluster.yaml,flux.yaml,kustomization.yaml,crds/.gitkeep}` — Flux Operator + FluxInstance fogja a feladatukat ellátni.
- ✅ `kustomize build` minden namespace-en zöld (10/10).

**Következő lépések (Phase 4 kezdő):**
1. `kubernetes/bootstrap/helmfile.d/{00-crds,01-apps,templates}` létrehozása (doc 04 spec szerint).
2. `kubernetes/bootstrap/resources.yaml.j2` létrehozása (1Password Connect creds + sops-age Secret `op://` referenciákkal).
3. `kubernetes/bootstrap/mod.just` recipe-ek (`cluster`, `talos`, `kubernetes`, `kubeconfig`, `wait`, `namespaces`, `resources`, `crds`, `apps`).
4. `kubernetes/apps/flux-system/flux-operator/` + `kubernetes/apps/flux-system/flux-instance/` app-subtreek (Phase 5 maradék — HelmRelease + OCIRepo + ks.yaml).
5. `just k8s-bootstrap cluster` → teljes bootstrap chain: Cilium → CoreDNS → cert-manager → ESO → 1P Connect → Flux Operator → Flux Instance.
6. FluxInstance reconcile-ja kapcsolódik a `flux/cluster/ks.yaml`-hez → `cluster-apps` reconcile-olja a teljes apps fát.

## Fázis tracker

| # | Fázis | Doc | Status | Megjegyzés |
|---|---|---|---|---|
| — | Tervezés (docs) | [README](./README.md) | ✅ done | 15 doc kész, lazán kapcsolódó struktúra |
| — | `talos` branch létrehozása | — | ✅ done | 2026-05-15 |
| 1 | Hardver, hálózat, IP plan | [01](./01-hardware-and-network.md) | ✅ done | HP fent, Talos installálva |
| 2 | Talos bootstrap | [02](./02-talos-bootstrap.md) | ✅ done | etcd Healthy, kubeconfig megvan, `cp0-k8s NotReady` (CNI várja) |
| 3 | Cilium CNI install + L2 announce | [03](./03-cilium-cni.md) | 🟡 in-progress | manifestek kész; runtime install Phase 4 közben |
| 4 | Bootstrap helmfile chain | [04](./04-bootstrap-helmfile.md) | ⏸ pending | **Következő**: helmfile.d + resources.yaml.j2 + mod.just recipe-ek |
| 5 | Flux Operator + FluxInstance | [05](./05-flux-operator.md) | 🟡 in-progress | `flux/cluster/ks.yaml` kész, legacy törölve; flux-operator + flux-instance app-subtreek és runtime install Phase 4 része |
| 6 | Repo refactor (apps struktúra) | [06](./06-repo-restructure.md) | 🟡 in-progress | bjw-s naming + layout refactor kész; megszűnő apps eltávolítása és új apps hozzáadása maradt |
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
- HP ProDesk 600 G6 DM **fent**, Talos installálva (`cp0-k8s NotReady`, CNI várja).
- PC801 + PC711 NVMe beszerelve (a 2026-05-16-i `talosctl get disks` output szerint).
- ✅ 1Password `HomeOps/talos` item létrehozva (`just talos gen-secrets`, 2026-05-15).
- ✅ `kubernetes/talos/nodes/cp0-k8s.yaml.j2`: `install.diskSelector.model` és `LinkAliasConfig` MAC OUI értékek validálva az élő hardveren.
- ⏭ Cilium runtime install: nem külön lépés — a Phase 4 bootstrap helmfile chain első release-e fogja telepíteni a `kubernetes/apps/kube-system/cilium/app/helmrelease.yaml` value-jaival (templates/values.yaml.gotmpl readback).
- ⏭ Phase 5 flux-operator + flux-instance app-subtreek a Phase 4 előfeltétele (a bootstrap helmfile a `kubernetes/apps/flux-system/flux-operator/` és `flux-instance/` HelmRelease-eit a `values.yaml.gotmpl`-en keresztül fogja olvasni).

## Frissítési konvenció

- Minden fázis végén frissül a fenti tracker tábla.
- A `README.md` "Status — élő tracker" szekciója és ez a doc szinkronban marad — ez a részletesebb, a README-ben rövidebb pillanatkép.
- Új sub-task / blocker → ide az "Open items" alá.
