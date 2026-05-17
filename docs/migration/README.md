# Migration plan: K3s + Proxmox + Task → Talos + bare metal + Just

Ez a könyvtár tartalmazza a home-ops infrastruktúra teljes átalakításának tervét. A migráció a `talos` git branch-en zajlik majd, a `main` branch addig az éles K3s clustert tükrözi. A tervet a main branch-en kezdjük, mert az átalakítás GitOps-kívüli része (Talos config, bootstrap helmfile, justfile) is itt fog megszületni.

## Cél állapot

| Réteg | Most | Cél |
|---|---|---|
| Hardver | K3s VM Proxmox-on | Bare metal Talos HP ProDesk 600 G6 DM-en (192.168.1.11) |
| NAS | OMV VM Proxmox-on (M93p) | Bare metal OMV (Debian 13 + OMV 8 Synchrony) M93p-n |
| OS | Debian + K3s | Talos Linux (latest stable) |
| CNI | Calico (tigera-operator) | Cilium (kube-proxy replacement, netkit, BBR, Hubble UI) |
| LoadBalancer | MetalLB | Cilium L2 announcement (`.15-.25` pool) |
| GitOps | Klasszikus Flux install | Flux Operator + FluxInstance |
| Cluster bootstrap | Ansible (xanmanning.k3s role) | Helmfile bootstrap chain + `op inject` resources |
| Flux cluster root | Egyetlen `cluster-apps` Kustomization | `cluster-vars` + `cluster-apps` (dependsOn) |
| Task runner | Task (`.taskfiles/`) | Just (`.justfile` + `mod.just`) |
| Tool versioning | nincs | mise (`.mise.toml`) |
| Templating | nincs | minijinja-cli + `op inject` |
| System upgrade | system-upgrade-controller | Tuppr (bjw-s minta) |
| Renovate | `.github/renovate.json5` | `.renovaterc.json5` root + `.renovate/*.json5` fragmensek |
| Provision | `provision/kubernetes` Ansible (K3s) | `provision/openmediavault` Ansible (OMV base only, NFS UI-ból) |
| Storage | democratic-csi local-hostpath | democratic-csi local-hostpath (változatlan) |
| NVMe szétosztás | n/a | PC801 → OS + etcd, PC711 → data PVC |
| Ingress | Envoy Gateway | Envoy Gateway (változatlan, `envoy-external` + `envoy-internal`) |
| Split-DNS | k8s-gateway | k8s-gateway (változatlan) |
| Backup | VolSync + Kopia + OVH S3 | VolSync + Kopia + OVH S3 (változatlan, 3-4 GB total) |
| Secrets | SOPS + 1P Connect + ExternalSecrets | SOPS (cluster-secrets + homepage) + 1P Connect + ExternalSecrets |
| Plex iGPU | nincs | nincs (i915 extension benne marad, mount NEM — phase 2) |

## Migráció modellje

**Big-bang cutover**: az új cluster a `talos` branch-en teljesen kiépül és teszteltetik, mielőtt egyetlen forgalom is rákerül. A régi cluster a main branch-szel folyamatosan él. Cutover-kor:
1. Régi clusteren utolsó VolSync snapshot OVH-ra.
2. Új clusteren VolSync restore minden PVC-re.
3. DNS cutover (Cloudflare + k8s-gateway split-DNS belső VIP-ek).
4. `talos` branch merge `main`-be.
5. Régi K3s cluster + Proxmox 1-2 hétig **standby** módban, mint biztonsági mentés.
6. Megfigyelési ablak után: régi cluster decom, M93p Proxmox kikapcsolás és bare metal OMV install.

## Fázisok és időbecslés

| # | Fázis | Doc | Becslés |
|---|---|---|---|
| 0 | Architecture decisions | [00](./00-architecture-decisions.md) | — |
| 1 | Hardver, hálózat, IP plan | [01](./01-hardware-and-network.md) | 2-4h fizikai setup |
| 2 | Talos bootstrap (machine config, install) | [02](./02-talos-bootstrap.md) | 2-3h |
| 3 | Cilium CNI install + L2 announce | [03](./03-cilium-cni.md) | 1-2h |
| 4 | Bootstrap helmfile chain | [04](./04-bootstrap-helmfile.md) | 2-3h |
| 5 | Flux Operator + FluxInstance | [05](./05-flux-operator.md) | 1h |
| 6 | Repo refactor: apps struktúra | [06](./06-repo-restructure.md) | 4-8h (app-onként) |
| 7 | Components és shared resources | [07](./07-components-and-shared.md) | 2-3h |
| 8 | Just migráció | [08](./08-just-migration.md) | 3-4h |
| 9 | Renovate rewrite | [09](./09-renovate-rewrite.md) | 1-2h |
| 10 | OMV Ansible playbook | [10](./10-omv-ansible.md) | 4-6h (csak cutover után) |
| 11 | Data migration runbook | [11](./11-data-migration.md) | — (refs only) |
| 12 | Pre-cutover checklist | [12](./12-pre-cutover.md) | a cutover előtti hét |
| 13 | Cutover runbook | [13](./13-cutover-runbook.md) | 4-8h éles cutover |
| 14 | Rollback és decommission | [14](./14-rollback-and-decom.md) | — |
| 15 | Post-cutover megfigyelés | [15](./15-post-cutover.md) | 1-2 hét observation |
| 16 | Repo refactor (ks.yaml flatten + doc + AI-guide refresh) | [16](./16-repo-refactor.md) | 5-7h (cutover-előtt) |

**Teljes munkaóra becslés (cutover-ig)**: ~25-40 óra effektív munka. Naptári időben ~2-4 hetes projekt, ha esténként és hétvégénként dolgozol.

## Sorrend

A docok **lazán kapcsolódnak**, ezért nem kell szigorú sorrendben olvasni. A kötelező sorrend a megvalósításnál:

```
01 (hardver) → 02 (Talos) → 03 (Cilium) → 04 (bootstrap helmfile) → 05 (Flux Operator)
                                              ↓
                  06 (repo refactor) ← 07 (components) ← 08 (just) ← 09 (renovate)
                                              ↓
              11 (data migration) → 16 (repo refactor cleanup) → 12 (pre-cutover) → 13 (cutover) → 15 (post-cutover)
                                                                                              ↓
                                                                                     14 (rollback if needed)

10 (OMV) — csak a cutover után, párhuzamosan a 15-össel
```

## Referencia repók

A terv három repó best practice-eit követi, prioritás szerint:

1. **[bjw-s-labs/home-ops](https://github.com/bjw-s-labs/home-ops)** — elsődleges minta, "minden a `kubernetes/` alatt" struktúra, `kubernetes/components/` újrahasznosítható darabokkal.
2. **[onedr0p/home-ops](https://github.com/onedr0p/home-ops)** — másodlagos minta, kifejezetten az L2 announcement Cilium konfig itt érhető el (bjw-s BGP-t használ).
3. **[buroa/k8s-gitops](https://github.com/buroa/k8s-gitops)** — harmadlagos referencia, a minimalista minták és Rook-Ceph integráció miatt.

## Konvenciók a docokban

- Minden doc szerkezete: **Cél → Inputs → Lépések → Validation → Rollback → Open issues**.
- Hungarian (informal tegező), de minden kód, fájlnév, parancs angolul.
- Cross-link forma: `[doc-name](./XX-doc-name.md)`.
- Konkrét fájlpath-ek a repó root-jához viszonyítva.
- Kódblokkok nyelv taggel: ```yaml, ```bash, ```terraform stb.
- Validation = konkrét parancs vagy megfigyelhető állapot, nem "looks good".

## Status — élő tracker

| Fázis | Status | Megjegyzés |
|---|---|---|
| Tervezés (docs) | 🟡 in-progress | Ez a könyvtár |
| `talos` branch létrehozása | ⏸ pending | Tervek lezárása után |
| Talos bootstrap (HP-n) | ⏸ pending | |
| Cilium install | ⏸ pending | |
| App migráció | ⏸ pending | App-by-app |
| Cutover | ⏸ pending | |
| Régi cluster decom | ⏸ pending | 1-2 hét observation után |

A státuszt minden fázis végén frissítjük.
