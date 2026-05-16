# Migration status

Élő státusz a K3s → Talos migráció állapotáról. Ez a doc gyors pillanatkép — a részletes terv a [README.md](./README.md)-ben és a `00`–`14` doc-okban van.

**Utolsó frissítés:** 2026-05-16 (éjszakai szünet — folytatás holnap)

## TL;DR

**Hol tartunk:** Cluster fent, Cilium + CoreDNS + cert-manager + External Secrets + 1Password Connect + Flux Operator + Flux Instance mind Running. Flux átvette a reconcile-t a `refs/heads/talos` branchről, `cluster-vars` + `cluster-apps` Ready, 10+ app Kustomization Applied. **A storage-rendszer NEM kész** — a `snapshot-controller` Helm release `failed-install` állapotban ragadt (régi VSC-race-condition öröksége), emiatt a `VolumeSnapshot*` CRD-k hiányoznak, a `volsync` CrashLoopBackOff-ban van, és minden PVC-t igénylő app `Pending`.

**A bootstrap menet közben felmerült hibák egyenként kezelve és committolva — a `talos` branch most futható-állapotú minden új clusteren.**

## Session 2026-05-16 — Phase 4 éles bootstrap napló

Mit végzünk el ma:

- ✅ `just k8s-bootstrap cluster` chain végigfutott — 7 release deployed.
- ✅ Útközbeni hibák javítva és pushed (`talos` HEAD: `c1fc548d3`):
  - `talos`/`nodes` változó IP→név (mod-relative path), `shuf`→`jq` (macOS portability) — `f67cb9db7` + `d3b0097a9`.
  - `find -printf` → pure shell loop (macOS) — `d0e453707`.
  - 1Password `homelab-age-key` mezőnév: `keys.txt` (file attachment) → `privateKey` (concealed field) — `1834f388e`.
  - Cilium NIC-felismerés: `net0` alias nem kernel device → `BondConfig name=bond0 links=[net0]` wrapper (bjw-s/onedr0p minta), Cilium `devices: bond+`, L2 policy `^bond[0-9]+$`, DHCP `bond0`-on — `560ec0912`.
  - CoreDNS `clusterIP: 10.96.0.10` → `10.245.0.10` (Talos serviceSubnets miatt) — `339156c98`.
  - onepassword-connect Secret-név alignment bjw-s/onedr0p-vel (`credentialsName: onepassword-connect-credentials-secret`, CSS `connectTokenSecretRef.name: onepassword-connect-vault-secret`) — `64d3839f1`.
  - `flux-operator` chart `web.networkPolicy.create: false` (alapból default-deny NetworkPolicy blokkolta az OCI pull-t ghcr.io-ra) — `d35aeb272`.
  - `snapshot-controller` VolumeSnapshotClass átköltöztetés `democratic-csi/app/volumesnapshotclass.yaml`-ba (race fix, bjw-s minta) — `dad2f5b70`.
  - `snapshot-controller` chart `webhook.enabled: false` (single-node overhead) — `c1fc548d3`.

- ✅ K3s-éra legacy apps Flux Kustomization-jei **suspended** (`tigera-operator`, `metallb`, `metallb-config`, `system-upgrade-controller`, `system-upgrade-controller-plans`) és élő Helm release-ek **uninstalled** (`metallb`, `system-upgrade-controller`); `tigera-operator` namespace törölve; `system-upgrade` Job-ok takarítva. **Repóból a könyvtárak NINCSENEK törölve még** — Phase 6 záró feladat.

- ✅ FluxInstance Ready, `flux-system` GitRepository létrejött, 4 Flux controller fut (source/kustomize/helm/notification), 11 CRD.

- ✅ ClusterSecretStore `onepassword-connect` **Valid + Ready=True**.

- ✅ `cluster-vars` ConfigMap (8 mező) + `cluster-secrets` Secret (2 mező, SOPS dekódolva) létrejött.

- ✅ Node `cp0-k8s` uncordon-olva (bond0-reboot-drain után nem uncordon-olt magától, az minden Pod Pending-jét okozta). **Megjegyzés holnapra**: bármely Talos reboot/upgrade után érdemes `kubectl get nodes` → ha `SchedulingDisabled`, `kubectl uncordon cp0-k8s`.

### Hol akadt el a session vége előtt

A `snapshot-controller` HelmRelease `.spec.values` frissült (webhook off, VSC nincs benne), DE az **élő Helm release** továbbra is a régi (`failed-install`) állapotban van, a helm-controller nem próbálja újra a fresh install-t magától. A pod nem létezik → CRD-k nincsenek apply-olva → `volsync` CrashLoopBackOff (`VolumeSnapshot` CRD missing) → `democratic-csi` Kustomization dry-run fail (`VolumeSnapshotClass` CRD missing) → minden PVC-t igénylő app `Pending`.

### Folytatás holnap — sorrend

1. **snapshot-controller force-fresh install** (a fő blocker):
   ```bash
   helm -n kube-system list -a
   helm -n kube-system uninstall snapshot-controller 2>/dev/null || true
   flux reconcile hr snapshot-controller -n kube-system --force
   kubectl -n kube-system get pods -l app.kubernetes.io/name=snapshot-controller -w
   kubectl get crd | grep snapshot     # várt: 3 CRD (VolumeSnapshot, VolumeSnapshotClass, VolumeSnapshotContent)
   ```

2. **volsync visszajön magától**, amint a CRD-k léteznek; ha nem, restart:
   ```bash
   kubectl -n volsync-system rollout restart deploy volsync
   kubectl -n volsync-system get pods
   ```

3. **democratic-csi Kustomization** automatikusan apply-olja a VSC-t és telepíti a CSI drivert:
   ```bash
   flux reconcile ks democratic-csi -n flux-system
   kubectl get sc                # várt: democratic-csi-local-hostpath storage class
   kubectl get volumesnapshotclass  # várt: democratic-csi-local-hostpath
   ```

4. **PVC-k provisioner-t találnak** → minden függő app sorra Running-ba megy:
   ```bash
   flux get ks -A | grep -v True   # várt: fokozatosan üres
   flux get hr -A | grep -v True   # várt: fokozatosan üres
   kubectl get pods -A | grep -v -E "Running|Completed"
   ```

5. **`envoy-gateway-config` BackendTrafficPolicy validation hiba** (P2 — független az 1-4-től):
   ```
   BackendTrafficPolicy.gateway.envoyproxy.io "rate-limit-external" is invalid:
   <nil>: Invalid value: "": Maximum boundary value must be of type integer with format int32
   in spec.rateLimit.global.rules[0].limit.requests
   ```
   Az Envoy Gateway 1.8.0 CRD schema-ja eltér a régi manifest-től. Megoldandó:
   ```bash
   grep -B 2 -A 20 "rate-limit-external\|BackendTrafficPolicy" \
     kubernetes/apps/networking/envoy-gateway/config/*.yaml
   ```
   Az értéket `int32`-vé kell konvertálni (pl. `requests: 100` ne string legyen).

6. **Megszűnő apps repo-szintű törlés** (Phase 6 záró):
   - `kubernetes/apps/tigera-operator/` — Calico, lecseréli Cilium
   - `kubernetes/apps/networking/metallb/` — lecseréli Cilium L2 announcement
   - `kubernetes/apps/system-upgrade/` — Rancher SUC nem Talos-kompatibilis (későbbi: `tuppr`)
   - Minden namespace `kustomization.yaml`-ből kivenni a hivatkozást
   - Flux reconcile prune-olja, ami már nem deklarált
   - Suspend feloldása nem kell (a Kustomization törlésével együtt megy)

### Freelens setup (független, opcionális)

A Freelens default `~/.kube/config`-ot olvas, ami csak a régi K3s clusterre mutat (`192.168.1.6:6443`). Talos cluster a repo `kubeconfig`-jában van (`https://192.168.1.11:6443`, context `main`).

Opciók:
- **Settings → Kubernetes → Kubeconfig sync directories**-be `/Users/zhorvath83/Projects/personal/home-ops` felvenni
- VAGY: **Catalog → Add Cluster → Custom Kubeconfig** → fájl: `kubeconfig` a home-ops gyökerében

Régi K3s context-et célszerű törölni: `kubectl config delete-context default --kubeconfig ~/.kube/config`.

### Ami **nem** változott a session során

- Cilium runtime hagyhatatlan baj nélkül fut (`cilium-xcmnd`, `cilium-operator`, Hubble relay + UI).
- A `cluster-settings` substitution-ök rendben dolgoznak.
- Az ExternalSecret-ek beérkeznek (1P Connect Ready, store Valid).
- Az `apply` chain idempotensen újrafuttatható: `just k8s-bootstrap apps` bármikor szabadon ismételhető.

## Korábbi szakasz — kész munka (commit-hash-ekkel)

A `talos` branchen idáig (cumulative, 2026-05-16 estére):

## Fázis tracker

| # | Fázis | Doc | Status | Megjegyzés |
|---|---|---|---|---|
| — | Tervezés (docs) | [README](./README.md) | ✅ done | 15 doc kész, lazán kapcsolódó struktúra |
| — | `talos` branch létrehozása | — | ✅ done | 2026-05-15 |
| 1 | Hardver, hálózat, IP plan | [01](./01-hardware-and-network.md) | ✅ done | HP fent, Talos installálva |
| 2 | Talos bootstrap | [02](./02-talos-bootstrap.md) | ✅ done | etcd Healthy, kubeconfig megvan, `cp0-k8s NotReady` (CNI várja) |
| 3 | Cilium CNI install + L2 announce | [03](./03-cilium-cni.md) | ✅ done | Cilium 1.19.4 fent + L2 announce egyedül felelős az LB IP-kért (MetalLB uninstalled), Hubble UI elérhető |
| 4 | Bootstrap helmfile chain | [04](./04-bootstrap-helmfile.md) | 🟡 in-progress | Chain végigfutott (7 release deployed); **maradt**: snapshot-controller force-fresh install (failed-install state-ben ragadt), volsync stabilizálás, democratic-csi VSC apply |
| 5 | Flux Operator + FluxInstance | [05](./05-flux-operator.md) | ✅ done | FluxInstance Ready, 4 controller fut, 11 CRD apply-olva, `flux-system` GitRepository auto-created, `cluster-vars` + `cluster-apps` Ready |
| 6 | Repo refactor (apps struktúra) | [06](./06-repo-restructure.md) | 🟡 in-progress | bjw-s naming + layout refactor + onepassword bjw-s alignment kész; megszűnő apps Kustomization-jei suspended, Helm release-ek uninstalled — **repo-szintű törlés még hátra** (tigera-operator/, networking/metallb/, system-upgrade/) |
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

- **🟡 Aktív blocker**: `snapshot-controller` Helm release `failed-install` state-ben → CSI/snapshot CRD-k hiányoznak → volsync + democratic-csi + minden PVC-t igénylő app blokkolva. Megoldás: `helm uninstall snapshot-controller -n kube-system` + `flux reconcile hr snapshot-controller -n kube-system --force`. Részletek a "Session 2026-05-16" szekcióban fent.
- **🟡 Phase 6 záró feladat**: K3s-éra app-subtree-k (tigera-operator/, networking/metallb/, system-upgrade/) repo-szintű törlése + namespace `kustomization.yaml`-ek tisztítása. Jelenleg csak Flux Kustomization-jeik suspended állapotban, a manifestek még a repo-ban élnek.
- **🟡 P2 — envoy-gateway-config validation**: `BackendTrafficPolicy/rate-limit-external` schema-drift (`Maximum boundary must be int32`). Manifest update kell (`requests: 100` → numeric, nem string).
- HP ProDesk 600 G6 DM fent, Talos `v1.13.2` v1.36.1 K8s, `cp0-k8s Ready` (bond0 az aktív kernel device, eno1 a slave).
- PC801 + PC711 NVMe beszerelve és felismerve.
- ✅ 1Password `HomeOps/talos` + `HomeOps/homelab-age-key` (`privateKey` field) + `HomeOps/1password-connect-kubernetes` (`credentials` + `token`) item-ek mind verifikálva.
- ✅ Cilium runtime up + L2 announce egyedül felelős az LB IP-kért (CiliumLoadBalancerIPPool `.15-.25` 11 IP, default policy `^bond[0-9]+$`).
- ✅ ClusterSecretStore `onepassword-connect` Valid/Ready.
- ⚠️ **Holnapra emlékeztető**: Bármely Talos reboot/apply-node után `kubectl get nodes` → ha `SchedulingDisabled`, `kubectl uncordon cp0-k8s` (ma a bond0-reboot drain után nem uncordon-olt automatikusan, ez minden Pod Pending-jét okozta — időigényes diagnosztika).
- ⚠️ **Freelens**: a default `~/.kube/config` még a régi K3s cluster-re mutat. A repo `kubeconfig`-ját kell hozzáadni a Freelens-be (Settings → Kubeconfig sync directory), és a K3s context-et törölni.

## Frissítési konvenció

- Minden fázis végén frissül a fenti tracker tábla.
- A `README.md` "Status — élő tracker" szekciója és ez a doc szinkronban marad — ez a részletesebb, a README-ben rövidebb pillanatkép.
- Új sub-task / blocker → ide az "Open items" alá.
