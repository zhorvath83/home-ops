# 12 — Pre-cutover checklist

## Cél

A cutover (`13-cutover-runbook.md`) előtti hét pontos teendőlistája. Minden elem checkbox — addig nem indul a cutover, amíg minden ki nincs pipálva. A kritikus elem: a régi K3s cluster Flux source-ának átkapcsolása a `k3s` branch-re, mielőtt a `talos` → `main` merge megtörténik.

> **Doc-státusz (2026-05-17):** Az alábbi T-7/T-5/T-3 ütemterv az eredeti, "lazább" forgatókönyvet írja le, amelyben a Talos cluster bootstrap és a PVC restore külön szakaszra esett szét, és a VolSync `replicationdestination.yaml` ideiglenesen ki volt kommentálva. A valóságban a `talos` branchen **Phase 7 ([07-components-and-shared.md](./07-components-and-shared.md))** óta **always-on VolSync RD** modell aktív, és **Phase 11 ([11-data-migration.md](./11-data-migration.md))** keretében már mind a 17 PVC restore megtörtént. Emiatt a T-3 nap obszolét alpontjai `~~áthúzva~~` vannak és **N/A** jelölést kapnak, a tényleges státuszra Phase 7 / Phase 11 cross-ref-fel. A státusz forrása: [STATUS.md](./STATUS.md) "Fázis tracker".

## T-7 nap: tervek véglegesítve

- [x] Minden migráció doc (`docs/migration/00-15`) lezárva.
  - **Phase 16 ([16-repo-refactor.md](./16-repo-refactor.md))** explicit **post-cutover** kerül lezárásra: a `16.c` (per-app CNP threat-model audit), `16.d` (qbittorrent config-handling döntés), `16.e` (kube-prometheus-stack ScrapeConfig + PrometheusRule extract) tudatosan **nem blokkoló** — `main` merge után, post-cutover hígításban érkezik. A `16.a` + `16.b` már lezárva a `talos` HEAD-en.
- [x] `talos` branch HEAD stabil, CI/lokális validation zöld.
- [x] Új HP node fizikailag installálva ([01-hardware-and-network.md](./01-hardware-and-network.md)).
- [x] BIOS beállítások ellenőrizve.

## T-5 nap: új cluster build a `talos` branch-en

- [x] Talos schematic + ISO + USB elkészítve ([02-talos-bootstrap.md](./02-talos-bootstrap.md)).
- [x] `just cluster-bootstrap cluster` lefutott, új cluster `Ready`.
- [x] Cilium L2 announcement működik (test LoadBalancer service kap IP-t).
- [x] Flux Operator + FluxInstance reconcile-olja a `talos` branch-et.
- [x] **MINDEN PVC NÉLKÜLI app fut** (cert-manager, ESO, k8s-gateway, envoy-gateway, observability stack, etc.).

## T-3 nap: új cluster validation app-okkal

- [x] ~~VolSync component-ben `replicationdestination.yaml` és `pvc.yaml dataSourceRef` **be-kommentelve** a `talos` branch-en.~~ **N/A** — Phase 7-ben váltottunk **always-on VolSync RD** modellre, az `replicationdestination.yaml` + `pvc.yaml` aktív a `talos` ágon, restore automatikusan fut új PVC felhúzáskor.
- [x] Minden ks.yaml új formátumban (lásd [06-repo-restructure.md](./06-repo-restructure.md)).
- [x] ~~Új clusteren minden Flux Kustomization `Ready`, de PVC-s app-ok **HelmRelease-i pending** (mert PVC nem létezik még).~~ **N/A** — Phase 11 után minden HR `Ready` (17 PVC restore-olva), nincs pending HelmRelease.
- [x] ~~**Egy próba-app restore** — egy alacsony rizikójú app-on (pl. wallos vagy actual) full lánc validation.~~ **N/A** — Phase 11 keretében **mind a 17 PVC** restore-olva és validálva.

## T-1 nap: K3s Flux source pin a `k3s` branch-re

A `k3s` branch a `main` HEAD-jéről már létrejött (`d22fc20cd`), és pushed: `git push -u origin k3s`. A régi K3s cluster Flux source-át **most** át kell kapcsolni erre az ágra, hogy a `talos` → `main` merge a régi clustert ne tudja se a cutover napon, se később megzavarni.

**Ezt a lépést a régi K3s cluster ellen kell végrehajtani**, nem a HP-n.

> **Resource-nevek (a `k3s` ág `kubernetes/flux/config/cluster.yaml` szerint):** a régi K3s clusteren a Flux GitRepository neve **`home-ops-kubernetes`** (namespace `flux-system`), a top-level Kustomization neve **`cluster`** — nem `flux-system`, mint korábban tévesen szerepelt itt. A `kubectl` és `flux` parancsok ezzel a két névvel dolgoznak.

```bash
# Kubeconfig — a régi K3s clustert célozzuk (k8s-0 @ 192.168.1.6).
# Cutover idejére ez `~/.kube/config-old`-ra mozgatható; a jelenlegi setupban
# a default `~/.kube/config` még a K3s-t mutatja (a Talos kubeconfig külön él).
export KUBECONFIG=~/.kube/config

# Sanity-check: tényleg a K3s API-jával beszélünk?
kubectl config current-context
kubectl cluster-info | head -2

# Jelenlegi state ellenőrzése:
kubectl -n flux-system get gitrepository home-ops-kubernetes \
  -o jsonpath='{.spec.ref}{"\n"}'
# {"branch":"main"}

# Pin a k3s branch-re (minimális merge patch — csak ref-et nyúl):
kubectl -n flux-system patch gitrepository home-ops-kubernetes --type=merge \
  -p '{"spec":{"ref":{"branch":"k3s","tag":null}}}'

# Reconcile + verifikáció:
flux -n flux-system reconcile source git home-ops-kubernetes
flux -n flux-system get sources git home-ops-kubernetes
# home-ops-kubernetes: revision=k3s@sha1:d22fc20cd... — Ready=True

flux -n flux-system get kustomizations
# minden Kustomization Ready, ugyanaz a revision-on (k3s@sha1:d22fc20cd...)
```

- [ ] `GitRepository/home-ops-kubernetes` `spec.ref.branch` = `k3s`.
- [ ] `flux get sources git home-ops-kubernetes` Ready=True az új revision-on (`k3s@sha1:d22fc20cd…`).
- [ ] `flux get kustomizations` minden Ready (nincs reconcile failure a branch-váltás miatt).
- [ ] **Védő commit a `main`-re** (opcionális, de ajánlott): a `talos` merge előtt a `main`-en egy üres commit (`git commit --allow-empty -m "🔥 chore(main): pre-talos-merge marker"`) push-olva — ha bármi áthibázna, ez a marker megmutatja, mi volt az utolsó K3s-kompatibilis revision.

A `k3s` ágon a Renovate **nem** fog PR-eket nyitni (a `.renovaterc.json5`-ban a `baseBranches: ["main"]` pin a merge után az új `main`-re érvényesül; a régi `main`-en lévő config szintén csak default branch-en operál).

## T-1 nap (cutover előtti este): final preparations

- [x] ~~**App-level export-ok futtatva** a régi clusteren:~~ **N/A** — Phase 11 ([11-data-migration.md](./11-data-migration.md)) keretében elvégezve.
  - [x] ~~Paperless: `document_exporter` → mentés.~~
  - [x] ~~Mealie: web UI Backup → ZIP letöltés.~~
  - [x] ~~Plex: automatikus backup ellenőrzés (`Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db` létezik).~~
- [x] ~~**Régi cluster full VolSync snapshot lánc** (`just k8s snapshot-all` régi clusteren).~~ **N/A** — Phase 11 alatt elvégezve, az always-on RD a `talos` clusteren ezeket a snapshotokat húzta restore-ra.
- [x] ~~Várj, amíg minden RS `lastSyncTime` ≤ 2 órás.~~ **N/A** — Phase 11 zárás után érvénytelen mérőszám (a restore-anchor snapshot már beolvadt).
- [ ] **Bejelentés a háztartásnak**: nincs Plex, Paperless, *arr stack a cutover ablakban.

## Kapcsolódó

- Cutover végrehajtás: [13-cutover-runbook.md](./13-cutover-runbook.md)
- Rollback (ha menet közben fel kell adni): [14-rollback-and-decom.md](./14-rollback-and-decom.md)
- Késleltetett K3s reanimáció (post-merge): [14-rollback-and-decom.md](./14-rollback-and-decom.md) — a `k3s` ág pin biztosítja, hogy a régi cluster bekapcsolható maradjon a `main` Talos struktúrája nélkül.
