# 12 — Pre-cutover checklist

## Cél

A cutover (`13-cutover-runbook.md`) előtti hét pontos teendőlistája. Minden elem checkbox — addig nem indul a cutover, amíg minden ki nincs pipálva. A kritikus elem: a régi K3s cluster Flux source-ának átkapcsolása a `k3s` branch-re, mielőtt a `talos` → `main` merge megtörténik.

## T-7 nap: tervek véglegesítve

- [ ] Minden migráció doc (`docs/migration/00-15`) lezárva.
- [ ] `talos` branch HEAD stabil, CI/lokális validation zöld.
- [ ] Új HP node fizikailag installálva ([01-hardware-and-network.md](./01-hardware-and-network.md)).
- [ ] BIOS beállítások ellenőrizve.

## T-5 nap: új cluster build a `talos` branch-en

- [ ] Talos schematic + ISO + USB elkészítve ([02-talos-bootstrap.md](./02-talos-bootstrap.md)).
- [ ] `just cluster-bootstrap cluster` lefutott, új cluster `Ready`.
- [ ] Cilium L2 announcement működik (test LoadBalancer service kap IP-t).
- [ ] Flux Operator + FluxInstance reconcile-olja a `talos` branch-et.
- [ ] **MINDEN PVC NÉLKÜLI app fut** (cert-manager, ESO, k8s-gateway, envoy-gateway, observability stack, etc.).

## T-3 nap: új cluster validation app-okkal

- [ ] VolSync component-ben `replicationdestination.yaml` és `pvc.yaml dataSourceRef` **be-kommentelve** a `talos` branch-en.
- [ ] Minden ks.yaml új formátumban (lásd [06-repo-restructure.md](./06-repo-restructure.md)).
- [ ] Új clusteren minden Flux Kustomization `Ready`, de PVC-s app-ok **HelmRelease-i pending** (mert PVC nem létezik még).
- [ ] **Egy próba-app restore** — egy alacsony rizikójú app-on (pl. wallos vagy actual) full lánc validation.

## T-1 nap: K3s Flux source pin a `k3s` branch-re

A `k3s` branch a `main` HEAD-jéről már létrejött (`d22fc20cd`), és pushed: `git push -u origin k3s`. A régi K3s cluster Flux source-át **most** át kell kapcsolni erre az ágra, hogy a `talos` → `main` merge a régi clustert ne tudja se a cutover napon, se később megzavarni.

**Ezt a lépést a régi K3s cluster ellen kell végrehajtani**, nem a HP-n.

```bash
export KUBECONFIG=~/.kube/config-old

# Jelenlegi state ellenőrzése:
kubectl -n flux-system get gitrepository flux-system -o jsonpath='{.spec.ref}{"\n"}'
# {"branch":"main"}

# Pin a k3s branch-re:
kubectl -n flux-system patch gitrepository flux-system --type=merge \
  -p '{"spec":{"ref":{"branch":"k3s","tag":null}}}'

# Reconcile + verifikáció:
flux reconcile source git flux-system
flux get sources git
# flux-system: revision=k3s@sha1:d22fc20cd... — Ready=True

flux get kustomizations
# minden Kustomization Ready, ugyanaz a revision-on
```

- [ ] `GitRepository/flux-system` `spec.ref.branch` = `k3s`.
- [ ] `flux get sources git` Ready=True az új revision-on.
- [ ] `flux get kustomizations` minden Ready (nincs reconcile failure a branch-váltás miatt).
- [ ] **Védő commit a `main`-re** (opcionális, de ajánlott): a `talos` merge előtt a `main`-en egy üres commit (`git commit --allow-empty -m "🔥 chore(main): pre-talos-merge marker"`) push-olva — ha bármi áthibázna, ez a marker megmutatja, mi volt az utolsó K3s-kompatibilis revision.

A `k3s` ágon a Renovate **nem** fog PR-eket nyitni (a `.renovaterc.json5`-ban a `baseBranches: ["main"]` pin a merge után az új `main`-re érvényesül; a régi `main`-en lévő config szintén csak default branch-en operál).

## T-1 nap (cutover előtti este): final preparations

- [ ] **App-level export-ok futtatva** a régi clusteren:
  - [ ] Paperless: `document_exporter` → mentés.
  - [ ] Mealie: web UI Backup → ZIP letöltés.
  - [ ] Plex: automatikus backup ellenőrzés (`Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db` létezik).
- [ ] **Régi cluster full VolSync snapshot lánc** (`just k8s snapshot-all` régi clusteren).
- [ ] Várj, amíg minden RS `lastSyncTime` ≤ 2 órás.
- [ ] **Bejelentés a háztartásnak**: nincs Plex, Paperless, *arr stack ma este 21:00-23:00 között.

## Kapcsolódó

- Cutover végrehajtás: [13-cutover-runbook.md](./13-cutover-runbook.md)
- Rollback (ha menet közben fel kell adni): [14-rollback-and-decom.md](./14-rollback-and-decom.md)
- Késleltetett K3s reanimáció (post-merge): [14-rollback-and-decom.md](./14-rollback-and-decom.md) — a `k3s` ág pin biztosítja, hogy a régi cluster bekapcsolható maradjon a `main` Talos struktúrája nélkül.
