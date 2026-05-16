# Migration status

Élő státusz a K3s → Talos migráció állapotáról. Ez a doc gyors pillanatkép — a részletes terv a [README.md](./README.md)-ben és a `00`–`14` doc-okban van.

**Utolsó frissítés:** 2026-05-16 este — Phase 4–7 + 11 ✅, adatmigráció + ingress stack E2E zöld, orphan `metallb` HR runtime cleanup (Cilium LB-IPAM stabil), **CiliumNetworkPolicy migráció ✅** (stateful ingress hardening visszahozva), follow-up-ok rögzítve.

## TL;DR

**Hol tartunk:** Teljes GitOps reconcile zöld (**0 Failing KS, 0 Failing HR**). 17 VolSync ReplicationDestination Kopia-restore-olt OVH snapshotokból (12–19 s/db). 18+ default app pod 1/1 Running, `cloudflare-tunnel` 1/1 Running 4 connection regisztrálva (bud01/vie05/vie06). A `replicationdestination + dataSourceRef` mostantól **always-on** pattern (bjw-s/onedr0p minta), nem cutover-only. **Ingress stack él** kívülről (Cloudflare tunnel) és belülről (envoy-internal `192.168.1.18`) — végpont tesztek HTTP 200/302 (normál login redirectek). A régi K3s cluster áll, a migráció gyakorlatilag adat-szinten is megtörtént a `talos` branchen.

**Ismert follow-up-ok** (egyik sem blocker, részletek az `Open items`-ben): `plex-trakt-sync` Plex API token frissítés, `envoy-gateway` v1.9.0 GA → BTP rate-limit visszakapcsolás, search domain `lan` cluster-szintű kezelés, `Taskfile.yml` törlés cutover-előtt, **Phase 15: repo doc + AI-guide refresh** (13 `docs/*.md` + 11 `CLAUDE.md` + 12 skill audit, cutover-előtt).

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

### Folytatás holnap — sorrend (TÖRTÉNELMI — mind elvégezve délután)

> Az alábbi 6 lépés a reggeli session-záró terve volt. **Mind a 6 a délutáni session-ben elvégezve** (lásd "Session 2026-05-16 délután" szekció). Megőrizve dokumentációs hivatkozásként.

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

### Freelens setup (TÖRTÉNELMI — megoldva délután)

> A Freelens default kubeconfig-ja már a Talos clustert látja a délutáni session-ben rögzítettek szerint. A részletes utasítás megőrizve referenciaként, ha valaha újra-setup kell.

A Freelens default `~/.kube/config`-ot olvas. Talos cluster a repo `kubeconfig`-jában van (`https://192.168.1.11:6443`, context `main`).

Opciók:
- **Settings → Kubernetes → Kubeconfig sync directories**-be `/Users/zhorvath83/Projects/personal/home-ops` felvenni
- VAGY: **Catalog → Add Cluster → Custom Kubeconfig** → fájl: `kubeconfig` a home-ops gyökerében

### Ami **nem** változott a reggeli session során

- Cilium runtime hagyhatatlan baj nélkül fut (`cilium-xcmnd`, `cilium-operator`, Hubble relay + UI).
- A `cluster-settings` substitution-ök rendben dolgoznak.
- Az ExternalSecret-ek beérkeznek (1P Connect Ready, store Valid).
- Az `apply` chain idempotensen újrafuttatható: `just k8s-bootstrap apps` bármikor szabadon ismételhető.

## Session 2026-05-16 délután — Phase 6 záró + adatmigráció

A reggeli felmérés szerint a `snapshot-controller` blocker (failed-install) **magától megoldódott** éjszaka — a Flux retry-loop visszahozta. Innen indultunk, és végigvittük az alábbi 6 lépést.

### 1. Phase 6 záró cleanup — K3s-éra subtree-k törlése (`478446aaf`)

- `kubernetes/apps/tigera-operator/`, `kubernetes/apps/networking/metallb/`, `kubernetes/apps/system-upgrade/system-upgrade-controller/` mappák törölve.
- Parent `kustomization.yaml`-ek tisztítva (`./tigera-operator`, `./metallb/ks.yaml`, `./system-upgrade-controller/ks.yaml` referenciák kivéve).
- `kubernetes/apps/system-upgrade/namespace.yaml` megőrizve (Tuppr ide kerül később).
- 23 fájl, 507 sor törölve.

### 2. Cilium LB-IPAM annotation csere (`e90d92ca0`)

A Plex Service `<pending>` ExternalIP-vel volt — kiderült, hogy a `metallb.io/loadBalancerIPs` annotáció Cilium L2 announcement alatt **nem ismert**.

- `kubernetes/apps/networking/envoy-gateway/config/gateway-internal.yaml`: `metallb.io/loadBalancerIPs` → `lbipam.cilium.io/ips`
- `kubernetes/apps/default/plex/app/helmrelease.yaml`: ugyanaz a csere
- `kubernetes/apps/networking/k8s-gateway/ks.yaml`: `dependsOn: metallb-config` eltávolítva (a Kustomization már nem létezett)

### 3. Új komponens verziók — bjw-s parity (`d094085d5`)

Verzió-felmérés referencia repok ellen (bjw-s + upstream GitHub releases):

- `external-secrets`: 2.4.1 → **2.5.0** (bjw-s + upstream egyezik)
- `kube-prometheus-stack`: 85.0.3 → **85.1.1** (bjw-s + upstream egyezik)
- Többi 10 komponens (cilium, coredns, cert-manager, 1password-connect, flux-operator, flux-instance, envoy-gateway, grafana-operator, democratic-csi, Talos) **már latest**.

### 4. envoy-gateway-config BackendTrafficPolicy disable (`778571544`)

A `rate-limit-external` BTP K8s 1.36 strict OpenAPI validation alatt elbukik: **upstream Envoy Gateway v1.8.0 regression** (PR `envoyproxy/gateway#8798`, merged 2026-04-21). A `Requests` Go-type `uint`→`uint32`-re változott; kubebuilder a CRD-ben `format: int32 + maximum: 4294967295` (uint32 max) ellentmondást emit. K8s 1.36 elutasítja.

- A manifest kommentbe téve. Visszakapcsolás envoy-gateway v1.9.0 GA-kor.
- Cloudflare WAF amúgy is fedezi az external rate-limitet az `envoy-external` előtt.

### 5. envoy-gateway HR + cloudflare-tunnel recovery

**envoy-gateway HR ValidatingAdmissionPolicy issue** — a Helm upgrade "original object ValidatingAdmissionPolicy `safe-upgrades.gateway.networking.k8s.io` not found" hibára futott. Diagnose:

- A VAP a `gateway-helm` chart `crds` subchart-jának `gatewayapi-crds.yaml`-jéből származik (3 kind: CRD, ValidatingAdmissionPolicy, ValidatingAdmissionPolicyBinding).
- A bootstrap `00-crds.yaml` `yq` szűrője `select(.kind == "CustomResourceDefinition")` — **kihagyta** a VAP-ot és VAPB-t.
- Az első Helm install timeout-olt a `certgen` Job-on; a `cluster-apps` Flux Kustomization rátette a `helm.toolkit.fluxcd.io/name` ownership labelt, **de a Helm release-tracking Secret-be NEM rögzült**.
- A referencia repok (bjw-s, onedr0p, buroa) ugyanezt a CRD-only szűrőt használják — náluk az első install sikerült, így nincs probléma.

**Recovery** (egyedi, NEM repo-szintű):
1. `helm uninstall metallb -n networking` (régi leftover release törlése — pod még futott)
2. `kubectl delete validatingadmissionpolicy safe-upgrades.gateway.networking.k8s.io` + `validatingadmissionpolicybinding`
3. `kubectl uncordon cp0-k8s` (a certgen Job Pending volt, mert a node SchedulingDisabled állapotban volt — Talos reboot drain után)
4. `flux reconcile hr envoy-gateway -n networking --force` → Helm reinstall sikeres, VAP visszajött Helm-ownership-ben
5. `envoy-external` + `envoy-internal` pod-ok 1/1 Running

### 6. kopia + external-dns HR recovery

Mindkét HR `MissingRollbackTarget` reason-nel ragadt — kezdeti install timeout + következő upgrade is `Failed`, így nincs prev revision rollback-re.

- `helm uninstall kopia -n volsync-system` és `helm uninstall external-dns -n networking`
- `flux reconcile hr kopia --force` és `flux reconcile hr external-dns --force` (KS reconcile NEM elég — HR-en külön kell)
- Mindkettő `Helm install succeeded` → 1/1 Running

### 7. Always-on VolSync component pattern (`a9d5a5f79`)

Referencia repok (bjw-s + onedr0p) **alapból engedélyezve** tartják a `replicationdestination.yaml`-t és a `pvc.yaml` `dataSourceRef`-et. NEM cutover-only minta, hanem **always-on**.

- `kubernetes/components/volsync/kustomization.yaml`: `replicationdestination.yaml` resource visszakommentelve.
- `kubernetes/components/volsync/pvc.yaml`: `dataSourceRef` visszakommentelve.
- Új PVC-k mostantól mindig `${APP}-bootstrap` ReplicationDestination-ből populálódnak.

### 8. Adatmigráció — 18 PVC újra-kreálás + OVH snapshot restore

Mivel a `dataSourceRef` immutable, a meglévő (üres) PVC-ket törölni kellett, hogy az új dataSourceRef-fel létrejöhessenek.

Per app (15 + 3 rejtett, két-KS-es ks.yaml fájlokban):
- `actual, bazarr, calibre-web-automated, isponsorblocktv, maintainerr, mealie, paperless, plex, prowlarr, qbittorrent, radarr, resticprofile, seerr, sonarr, wallos` (15 fő)
- `paperless-gpt, plex-trakt-sync, backrest` (3 rejtett, két-KS-es ks.yaml fájlokban, `restic-gui` `backrest` PVC-t hivatkozza)

Lépések batch-szel:
1. `flux suspend hr <app> -n default` minden 15+3 app-ra
2. `kubectl scale deploy/<app> --replicas=0`
3. `kubectl delete pods --field-selector=status.phase=Failed -A` (régi Error pod-ok takarítása) + force delete az új Error pod-okra (`pvc-protection` finalizer szabadítása)
4. `kubectl delete pvc <app>` (Delete reclaim policy → PV is törlődik)
5. `flux resume hr <app>` + `kubectl scale deploy/<app> --replicas=1` (a Helm a meglévő `replicas` mezőt nem patcheli felül)
6. `flux reconcile ks <app> -n flux-system` → új PVC `dataSourceRef`-fel + új RD `manual: restore-once` triggerrel
7. RD azonnal restore-ol (Kopia letöltés OVH-ról) → VolumeSnapshot → PVC Bound a snapshot tartalmával
8. Pod elindul a populated PVC-vel

**Eredmény: 17 RD synced 12–19 másodperc alatt.** Csak a `resticprofile` nem volsync-os PVC-szinten (NFS + emptyDir-en fut), ott RD nem létezik.

### 9. cloudflare-tunnel NetworkPolicy fix (`b98f7a859`)

A `cloudflare-tunnel` CrashLoopBackOff-ban volt 12 órája — DNS timeout `cfd-features.argotunnel.com` és `_v2-origintunneld._tcp.argotunnel.com` lekérdezéseken (CoreDNS `10.245.0.10:53`).

Root cause diagnose **Hubble flow log**-gal:
- `cloudflare-tunnel → CoreDNS:53` UDP query: **ALLOWED + FORWARDED** ✅
- `CoreDNS:53 → cloudflare-tunnel:<random_port>` UDP **reply**: **Policy denied DROPPED** ❌

A `cloudflare-tunnel` `NetworkPolicy` `policyTypes: [Ingress, Egress]` mindkettőt kontrollálta, az ingress oldalon **csak `prometheus:8080` TCP**-t engedte. A K8s NetworkPolicy spec szerint elvileg stateful (return-traffic auto-allowed), de a **Cilium UDP replyket az ingress plane-en validálja** — a destination port a return packetben random, nem matchel sem ingress rule.

- A Calico (régi K3s) stateful tracking-ben ez működött; a Cilium-ra váltáskor regressziót okozott.
- Referencia repok (bjw-s, onedr0p, buroa) **NEM** korlátozzák az ingress-t a `cloudflared` pod-on.

**Fix**: `policyTypes: [Egress]` (`Ingress` kivéve). Az egress hardening megmarad (Cloudflare CIDR-ek, kube-dns UDP 53, envoy backend portok). A `prometheus:8080` scrape default-allow-on át megy be.

**Eredmény**: tunnel pod 1/1 Running, 4 connection registered (`bud01`, `vie05`, `vie06`).

### 10. envoy-external / envoy-internal NetworkPolicy fix (`606fe6479`)

Felhasználói visszajelzés: a HTTPRoute-on publikált erőforrások sem kívülről, sem belülről nem érhetők el. Diagnose tárta fel:

- `envoy-external` Gateway `PROGRAMMED=False`
- `envoy-internal` Service `EXTERNAL-IP=<pending>` (Cilium LB-IPAM nem osztotta ki a `192.168.1.18`-at)
- Mindkét envoy pod `1/2 Running`, **18 RESTART**: az `envoy` container az xDS upstream-et nem éri el (`no healthy upstream`), SIGTERM, restart loop. A `shutdown-manager` sidecar "shutdown readiness timeout exceeded" üzenetekkel.

**Root cause** — **ugyanaz a Cilium-NetworkPolicy stateless UDP minta** mint a `cloudflare-tunnel`-nél: a `kubernetes/apps/networking/envoy-gateway/config/networkpolicy-{external,internal}.yaml` `policyTypes: [Ingress, Egress]` mindkettőt szabályozza, és az ingress oldalon csak konkrét portokat enged (TCP 10080/10443, UDP 10443, prometheus 19001). A **CoreDNS-ből visszaérkező UDP DNS reply random destination porton** érkezik, nem matchel egyik ingress rule-lal sem → Cilium policy DENIED + DROPPED.

Hubble flow log megerősítve: `kube-dns:53 → envoy-internal:<random>` "Policy denied DROPPED (UDP)".

Az `envoy-internal` Service `externalTrafficPolicy: Local` mód miatt a Cilium LB-IPAM csak akkor allokál IP-t, ha van ready endpoint a node-on — a CrashLooping envoy pod nem ready, így a `.18` IP soha nem rögzült.

**Fix**: mindkét NetworkPolicy `policyTypes: [Egress]`-re cserélve (ingress kivéve). LAN allowlist az `envoy-internal`-on az `envoy-internal-rfc1918` SecurityPolicy (listener-szintű) érvényesíti továbbra is.

**Eredmény**: pod-ok 2/2 Ready, Gateway-ek `Programmed=True`, `envoy-internal` ADDRESS=`192.168.1.18`.

Az `envoy-gateway` controller restart-jára szükség volt — status_updater loop-ban ragadt addig.

### Mai cluster állapot session végén

- ✅ **0 Failing KS**, **0 Failing HR**
- ✅ 18 default app pod 1/1 Running
- ✅ `cloudflare-tunnel` 1/1 Running, tunnel connections regisztrálva
- ✅ **Ingress stack él**:
  - Kívülről (Cloudflare tunnel): `https://dash.horvathzoltan.me/` → HTTP 200
  - LAN split-DNS: `dig dash.horvathzoltan.me @192.168.1.1` → `192.168.1.18`
  - Belül (envoy-internal `.18`): `https://dash.horvathzoltan.me/` → HTTP 200
  - Több route teszt: `docs/grafana` HTTP 302 (login redirect, normál); `plex` HTTP 404 (Plex token issue, task #9)
- 🟡 1 app-szintű follow-up: `plex-trakt-sync` 401 unauthorized — Plex API token elavult a friss DB-ben

## Session 2026-05-16 este — CiliumNetworkPolicy migráció + ingress hardening visszahozva

A délutáni `606fe6479` workaround a 3 K8s `NetworkPolicy`-t (`cloudflare-tunnel`, `envoy-external`, `envoy-internal`) `policyTypes: [Egress]`-re csökkentette, mert a Cilium stateless módon kezeli az UDP reply pakettokat ingress oldalon (random destination port nem matchel ingress rule-lal, CoreDNS-választ eldob). Ez **ingress hardening regressziót** okozott: a 3 pod ingress oldalán default-allow lett.

`CiliumNetworkPolicy` (CNP) **stateful conntrack-kal** működik — a kifelé menő DNS query alapján az UDP reply automatikusan engedélyezett, így a stateless-UDP probléma megszűnik. Migráció: 3 K8s NP → 3 CNP + 1 közös `CiliumCIDRGroup/cloudflare` (cluster-scoped, 22 Cloudflare CIDR, DRY).

### Manifestek (`4f4b76eec`)

- **Új**: `kubernetes/apps/networking/cloudflare-tunnel/app/ciliumcidrgroup.yaml` (cluster-scoped, `apiVersion: cilium.io/v2`).
- **Új**: `kubernetes/apps/networking/cloudflare-tunnel/app/ciliumnetworkpolicy.yaml` (ingress: Prometheus scrape; egress: kube-dns, envoy-external pod 10080/10443, Cloudflare CIDRGroup 443/80/7844 TCP+UDP).
- **Új**: `kubernetes/apps/networking/envoy-gateway/config/ciliumnetworkpolicy-{external,internal}.yaml` (ingress: 10080/10443 a megfelelő forrásból, 19001 Prometheus, 19003 host/remote-node; egress: kube-dns, `toEntities: [cluster, kube-apiserver, world]` 443 TCP-re).
- **Törölve**: a régi 3 K8s `NetworkPolicy` fájl.
- **Frissítve**: 2 `kustomization.yaml` resource lista.

### Eredmény

- `kubectl get ciliumnetworkpolicy -A` → 3/3 VALID=True
- `kubectl get networkpolicy -n networking` → üres (régiek prune-olva)
- Cilium endpoint policy state (`cilium endpoint list`): **mindhárom endpoint Enabled/Enabled** (ingress + egress enforcement aktív):
  - `619` cloudflare-tunnel: Enabled/Enabled
  - `2179` envoy-internal:   Enabled/Enabled
  - `3591` envoy-external:   Enabled/Enabled
- Pod-ok stabil (envoy-{external,internal} 2/2, cloudflare-tunnel 1/1, **0 új restart** a CNP apply óta).
- Gateway-ek `PROGRAMMED=True`, `envoy-internal ADDRESS=192.168.1.18`.
- Ingress smoke: external HTTPS `https://dash.horvathzoltan.me/` → HTTP 200, internal `https://192.168.1.18/` (SNI dash) → HTTP 200.
- Cloudflare tunnel log az apply óta **csendben** (az addigi hibák a 13:11–13:39 közötti envoy-restart-loopból maradtak).

### Megjegyzés

A `CiliumCIDRGroup` cluster-scoped, de a kustomization `namespace: networking` direktívája `metadata.namespace: networking`-et rárakott. **A Kubernetes API server cluster-scoped erőforrásokon ezt csendben ignorálja** (server-side dry-run megerősítette: `ciliumcidrgroup.cilium.io/cloudflare created`), tehát a manifest működik. Tisztább lenne kustomize patch-csel kiszedni a namespace mezőt (`op: remove, path: /metadata/namespace`), de a jelenlegi forma is helyes és Flux apply-on átmegy.

## Session 2026-05-16 este — PVC újratöltés helyes Kopia snapshotokból

Felhasználói visszajelzés: a délutáni „17 PVC restore" valójában egy üres, Talos-éra Kopia snapshot-ot húzott le, nem a K3s-éra adatokat. Az üres snapshot(ok) az OVH bucketről manuálisan törölve, futtatunk egy fresh restore-t.

### Procedúra (17 app)

`actual, backrest, bazarr, calibre-web-automated, isponsorblocktv, maintainerr, mealie, paperless, paperless-gpt, plex, plex-trakt-sync, prowlarr, qbittorrent, radarr, seerr, sonarr, wallos` — per app:

1. `flux suspend hr <app> -n default`
2. `kubectl scale deploy/<app> --replicas=0` (mind Deployment, nincs StatefulSet)
3. Pod terminálás bevárása
4. `kubectl delete pvc <app> -n default` — törli a PV-t is (Delete reclaim policy)
5. `kubectl delete replicationdestination <app>-bootstrap -n default` — **kritikus**, különben az új PVC `dataSourceRef`-en át a régi (üres) `VolumeSnapshot`-ot klónozta volna a populator
6. `flux resume hr <app>` + `flux reconcile ks <app> -n flux-system` — új RD `manual: restore-once` triggerrel + új PVC
7. `kubectl scale deploy/<app> --replicas=1` (Helm a meglévő `replicas` mezőt nem patcheli felül)

A `backrest` egy speciális eset: a Flux Kustomization-je `restic-gui` néven él a `flux-system`-ben (nem `backrest`), így a tömeges `flux reconcile ks backrest` time-out-olt; külön `flux reconcile ks restic-gui -n flux-system --timeout=60s` szükséges. A `restic-gui` `ks.yaml` második Kustomization-blokkja hordozza a volsync component-et `APP: backrest` substitution-nel.

Az RS-ek `NEXT SYNC` mezője `2026-05-17T02:00:00Z` volt — tehát a restore-ablakban nem volt verseny az újra-feltöltéssel.

### Eredmény

17/17 RD synced 11s–1m48s alatt (Plex 1m48s a legnagyobb, paperless 45s, sonarr 39s, többi 11-35s). Pod-ok mind 1/1 Running (paperless 2/2 a valkey sidecarral). PVC-ken validált tartalom: sonarr 373M (`sonarr.db` 74M), plex 964M (Library DB 48M + history 2026.05.05/08/11/14), radarr 313M, calibre-web 129M, qbittorrent 46M (549 BT_backup), prowlarr 22M, bazarr 7.3M (backup zip-ek), backrest 7.8M, actual 4.6M, mealie 1.4M, wallos sqlite present, paperless 445M (`/data/local/data/db.sqlite3` 57M, `/data/local/media` 281M, 3485 dokumentum-fájl).

### Ellenőrzési csapda — paperless path felülírás

A verifikáció során egy időre tévesen üresnek minősítettem a paperless restore-t, mert a paperless-ngx upstream image default path-jait (`/usr/src/paperless/{data,media,consume,export}`) néztem. A `helmrelease.yaml` env-blokkja viszont **felülírja** ezeket:

```yaml
PAPERLESS_DATA_DIR:     /data/local/data
PAPERLESS_MEDIA_ROOT:   /data/local/media
PAPERLESS_LOGGING_DIR:  /data/local/logs
PAPERLESS_EXPORT_DIR:   /data/nas/export    # NFS NAS
PAPERLESS_CONSUMPTION_DIR: /data/nas/inbox  # NFS NAS scanner
```

A PVC `/data/local` alá van mountolva (egyetlen mountpoint, nem subPath-okkal felszabdalva), a paperless onnan olvas/ír; az image-beli `/usr/src/paperless/{data,media,…}` üres stub könyvtárak. **Tanulság**: restore-verifikáció előtt minden alkalommal a manifest env-blokkját kell elolvasni, nem az upstream image default path-ait feltételezni. Egyszerűbb fallback: `kubectl exec -- du -sh /data/* /config/* 2>/dev/null` plusz `mount | grep -v overlay`.

### Tanulság

Az always-on `dataSourceRef` minta + `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` címke az RD-n azt jelenti, hogy egy RD egyszer fut le `manual: restore-once`-szal, utána statikus. Új Kopia-fetch indításához **mindkettőt** kell törölni: a PVC-t **és** az RD-t — különben az új PVC az RD `status.latestImage` mezőből populálódik a régi (immár üres) VolumeSnapshot-tal.

## Session 2026-05-16 este — orphan `metallb` HR runtime cleanup

Felhasználói visszajelzés: external irányból minden zöld, **belső irányból viszont a homepage akadozik, a `subscriptions.horvathzoltan.me` teljesen elérhetetlen**. SRE diagnose:

- `envoy-internal` Service `EXTERNAL-IP=<pending>`, Gateway `PROGRAMMED=False` (`AddressNotAssigned`).
- `k8s-gateway` (split DNS LB) szintén `<pending>`.
- `cilium-operator-lb-ipam` a `status.loadBalancer.ingress` mezőbe **beírja** a `192.168.1.18` / `192.168.1.19` IP-t — majd a következő reconcile-ban **üres lesz** (oszcillál).
- `metallb-controller` log: `failed to handle service` minden LoadBalancer Service-re, miközben felülírja a Cilium által beírt status mezőt. **MetalLB IPAddressPool / L2Advertisement nincs deklarálva** — a Cilium L2 announce csak akkor küld ARP-t a `.18`-ra, amíg a status megvan, innen az akadozás.

### Mi maradt benn

A reggeli session a Flux Kustomization-t `suspended` állapotba tette → suspended Kustomization **nem prune-ol**. A délutáni `478446aaf` commit a repo subtree-t törölte, a Kustomization is így „eltűnt" a görbe ablakon át. A `helm uninstall metallb` lefutott, **de a `HelmRelease/metallb -n networking` objektum nem lett törölve** — a helm-controller újra-installálta, ~2 órája pörgött ebben az állapotban a délutáni „minden zöld" pillanatfotó után.

Tüneti rejtőzködés: a Cilium reconcile pillanatokra visszahozta a `.18`-at, így a délutáni session-záró smoke teszt (HTTP 200 a `dash.horvathzoltan.me`-re) **véletlenül egy ilyen pillanatban futott**, és a probléma rejtve maradt.

### Cleanup

Mivel a repóban már nincs `metallb` referencia (`find kubernetes -iname '*metallb*'` üres), ez nem-deklarált runtime takarítás, nem repo-változás:

```bash
kubectl delete hr -n networking metallb
# helm-controller uninstall-olja → controller + speaker pod elmegy
helm ls -n networking | grep metallb       # üres
kubectl get deploy,ds -n networking | grep metallb  # üres
```

### Eredmény

- `kubectl get svc -n networking envoy-internal k8s-gateway` → `EXTERNAL-IP` **stabil** (`192.168.1.18` és `192.168.1.19`), két egymást követő olvasás között nincs flap.
- `envoy-internal` Gateway `PROGRAMMED=True`, `ADDRESS=192.168.1.18`.
- Belső ingress most már valóban él, nem csak race-window-ban.

### Tanulság — cutover előtt ellenőrizni

A Flux **Kustomization suspend → repo subtree delete** kombináció **orphan child HR-eket hagy maga után**. Cutover előtt érdemes a `networking` és `kube-system` namespace-ben `kubectl get hr -A` listát átfutni, és minden olyan HR-t törölni, amire `flux get ks -A` nem mutat parent-et. Vagy: suspend HELYETT a Kustomization-t törölni `prune: true` mellett, mert az automatikusan eltakarítja a managed objektumokat.

## Fázis tracker

| # | Fázis | Doc | Status | Megjegyzés |
|---|---|---|---|---|
| — | Tervezés (docs) | [README](./README.md) | ✅ done | 15 doc kész, lazán kapcsolódó struktúra |
| — | `talos` branch létrehozása | — | ✅ done | 2026-05-15 |
| 1 | Hardver, hálózat, IP plan | [01](./01-hardware-and-network.md) | ✅ done | HP fent, Talos installálva |
| 2 | Talos bootstrap | [02](./02-talos-bootstrap.md) | ✅ done | etcd Healthy, kubeconfig megvan, `cp0-k8s NotReady` (CNI várja) |
| 3 | Cilium CNI install + L2 announce | [03](./03-cilium-cni.md) | ✅ done | Cilium 1.19.4 fent + L2 announce egyedül felelős az LB IP-kért (MetalLB Helm release + HR runtime cleanup esti session-ben — orphan HR rejtett flap-et okozott), Hubble UI elérhető |
| 4 | Bootstrap helmfile chain | [04](./04-bootstrap-helmfile.md) | ✅ done | 7 release deployed; snapshot-controller magától visszaállt, kopia + external-dns helm uninstall + reinstall recovery után Ready |
| 5 | Flux Operator + FluxInstance | [05](./05-flux-operator.md) | ✅ done | FluxInstance Ready, 4 controller fut, 11 CRD apply-olva, `flux-system` GitRepository auto-created, `cluster-vars` + `cluster-apps` Ready |
| 6 | Repo refactor (apps struktúra) | [06](./06-repo-restructure.md) | ✅ done | bjw-s naming + layout refactor + onepassword bjw-s alignment + K3s-éra subtree-k repo-szintű törlése (tigera-operator/, networking/metallb/, system-upgrade-controller/) + Cilium LB-IPAM annotation csere |
| 7 | Components és shared resources | [07](./07-components-and-shared.md) | ✅ done | VolSync component **always-on** pattern engedélyezve (bjw-s minta): `replicationdestination.yaml` + `pvc.yaml dataSourceRef` aktív |
| 8 | Just migráció | [08](./08-just-migration.md) | 🟡 in-progress | foundation (mise+just+setup.sh) kész; `Taskfile.yml` törlés cutover-előtt |
| 9 | Renovate rewrite | [09](./09-renovate-rewrite.md) | ⏸ pending | `.renovaterc.json5` + fragmensek |
| 10 | OMV Ansible playbook | [10](./10-omv-ansible.md) | ⏸ pending | Csak cutover után |
| 11 | Data migration runbook | [11](./11-data-migration.md) | ✅ done | 17 PVC restore-olt OVH snapshotból 12–19s/db; always-on RD pattern miatt nem lesz külön "cutover" adatmigráció |
| 12 | Cutover runbook | [12](./12-cutover-runbook.md) | 🟡 in-progress | A `talos`→`main` branch merge + FluxInstance ref switch + régi K3s decom hátra van |
| 13 | Rollback és decommission | [13](./13-rollback-and-decom.md) | ⏸ pending | |
| 14 | Post-cutover megfigyelés | [14](./14-post-cutover.md) | ⏸ pending | 1-2 hét observation |
| 15 | Repo doc + AI-guide refresh | — | 🟡 in-progress | `docs/*.md` + `CLAUDE.md` lánc + `.claude/skills/*` audit + átírás a migráció eredménye alapján; cutover-előtt zárandó, hogy a `main` branch konzisztens legyen |

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

- **`main`** — a régi K3s cluster GitOps forrása (a K3s VM jelenleg lekapcsolva).
- **`talos`** — az új Talos cluster aktív GitOps forrása (FluxInstance `sync.ref: refs/heads/talos`).
- **Cutover-kor**: `talos` → merge `main`, FluxInstance `sync.ref` átáll `refs/heads/main`-re, a régi K3s VM nem indul újra (1-2 hét standby után decom).

## Munka állapota

- **Effektív munkaóra eddig**: ~30-35h (2026-05-15 → 2026-05-16). Tervezett ~25-40h cutover-ig **gyakorlatilag elköltve** — de adat-szinten a migráció már megtörtént (always-on VolSync RD), így a maradék "cutover" csak branch merge + FluxInstance ref switch + DNS-szintű ellenőrzés.
- **Hátralévő naptári idő cutover-ig**: ~1-3 nap (follow-up-ok kezelése + branch merge + observation window indítása).

## Open items / blocker

### Aktív blokkoló — nincs

A teljes GitOps reconcile zöld (0 failing KS, 0 failing HR).

### Follow-up — nem blocker, post-cutover ablakra rögzítve

- **`plex-trakt-sync` 401 unauthorized**: A pod CrashLoopBackOff-ban a Plex API tokenre `(401) unauthorized` választ kap. A friss Plex DB-ben (restore után) más token generálódott. Megoldás: 1Password-ben a Plex API token frissítése + ExternalSecret refresh. **App-szintű config, nem infrastruktúra blocker.**

- **`envoy-gateway` v1.9.0 GA → BackendTrafficPolicy visszakapcsolás**: A `rate-limit-external` BTP `kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml`-ben **kommentbe téve** az upstream v1.8.0 CRD regression miatt (PR `envoyproxy/gateway#8798`, kubebuilder `uint32` → `format: int32 + maximum: uint32_max`, K8s 1.36 strict OpenAPI elutasít). Renovate hozza a v1.9.0 GA-t, és a `git revert` egyszerű — a workaround commit a `gateway-policies.yaml`-ben megőrzi a manifestet kommentben.

- **Search domain `lan` cluster-szintű kezelés**: A Talos node `ResolverStatus` `SEARCH DOMAINS: []` üres. **FQDN-szintű `.lan` resolve cluster-en át jelenleg működik** (a CoreDNS `forward . /etc/resolv.conf` minden ismeretlen domain-t a router upstream-re küld; `dig nas.lan @10.245.0.10` válaszol). **Akkor szükséges, ha valaha rövid host neveket (pl. `nas`) hivatkoznánk app config-ban** — jelenleg minden manifest FQDN-t (`nas.lan`) vagy IP-t (`192.168.1.10`) használ. Ha kell:
    1. Talos machineconfig `machine.network.searchDomains: [lan]` (node `/etc/resolv.conf` `search lan`-t kap)
    2. Kubelet `--resolv-conf=/etc/resolv.conf` flag (`machine.kubelet.extraArgs`) — a pod-ok `dnsPolicy: ClusterFirst` esetén is örökli a node search-jét
    A két lépés csak együtt ér valamit (az egyik a másik nélkül nem hat). Egyik referencia repó (bjw-s/onedr0p/buroa) sem foglalkozik ezzel.

- ~~**CiliumNetworkPolicy migráció — ingress hardening stateful módon**~~: **✅ done** (commit `4f4b76eec`, 2026-05-16 este). A 3 K8s `NetworkPolicy` lecserélve `CiliumNetworkPolicy`-ra, közös `CiliumCIDRGroup/cloudflare` (22 CF CIDR) bevezetve. Cilium endpoint policy state mindhárom pod-on Enabled/Enabled (stateful conntrack), ingress smoke HTTP 200 mindkét irányból, 0 új pod-restart.

- **`Taskfile.yml` + `.taskfiles/` törlés**: Phase 8 záró feladat — cutover-előtt, hogy a `talos` branch tisztán Just-alapú legyen.

- **Phase 15 — Repo doc + AI-guide refresh** (cutover előtti zárás): a migráció gyökeresen átszabta a stacket (K3s → Talos, Task → Just, Calico/tigera-operator → Cilium + Cilium L2 announce, MetalLB → Cilium LB-IPAM, Traefik → Envoy Gateway + Gateway API, `system-upgrade-controller` → `tuppr` post-cutover, bjw-s repo layout, always-on VolSync `replicationdestination`). A migrációs `docs/migration/00–14` doc-ok ezt tükrözik, **de a többi repo-doksi és AI-guide nagyrészt még a K3s-éra valóságot írja le**. Audit + átírás szükséges.

  **Hatáskör — érintett fájlok:**

  *`docs/*.md` (13 fájl) — várhatóan többségben elavult vagy törlendő:*
  - `docs/k3s-readme.md` — elavult, vélhetően törlendő (Talos-specifikus alternatíva: nincs külön doc, `docs/migration/02-talos-bootstrap.md` lefedi)
  - `docs/k3s-system-upgrade.md` — elavult (Rancher SUC kivéve), `tuppr` post-cutover, addig nincs replacement
  - `docs/networking-readme.md` — átírás Traefik+MetalLB → Envoy Gateway+Cilium-ra
  - `docs/kubernetes-readme.md` — Talos + bjw-s layout
  - `docs/flux-readme.md` — Flux Operator + FluxInstance pattern
  - `docs/helm-readme.md`, `docs/cert-manager-readme.md`, `docs/sops-readme.md`, `docs/pluto-readme.md` — ellenőrzés, kis frissítések
  - `docs/host-configuration.md` — Talos machineconfig (1Password forrás), `provision/kubernetes` Ansible kivonás
  - `docs/backup-kubernetes-host.md` — felülvizsgálat (Talos host-szintű backup szükséges-e)
  - `docs/postgresql-backup-readme.md` — ellenőrzés (CNPG még él-e a cluster-ben)
  - `docs/ingress-basic-auth.md` — Envoy Gateway SecurityPolicy mintára átírás

  *Root + path-szintű `CLAUDE.md`-k (11 fájl, worktree-másolatok kihagyva):*
  - `CLAUDE.md` (root) — task domain lista (`an: es: fx: hm: ku: pc: so: tf: vs:`) Just-receptekre cserélendő; "Current Repository Shape" + "State To Assume Today" frissítés (a MetalLB már leszerelve, ingress stack él, bjw-s parity rögzítve)
  - `kubernetes/CLAUDE.md`, `kubernetes/apps/{default,external-secrets,networking,volsync-system}/CLAUDE.md` — bjw-s layout + új namespace + always-on VolSync minta
  - `provision/CLAUDE.md`, `provision/kubernetes/CLAUDE.md`, `provision/cloudflare/CLAUDE.md`, `provision/ovh/CLAUDE.md` — Talos Ansible scope szűkítés, Cloudflare/OVH változatlan
  - `.claude/CLAUDE.md` — Cluster Access Policy a `task fx:*` / `task vs:*` helyett Just receptekre

  *`.claude/skills/*/SKILL.md` + referenciák (12 skill):*
  - `taskfiles/` skill — Phase 8 lezárása után **törlendő vagy átírandó "just" skillé** (a workflow-rétegre a `just` lesz a belépés)
  - `versions-renovate/` skill — Phase 9 után átírás az új `.renovaterc.json5` + `.renovate/` fragmens-struktúrára
  - `provision-kubernetes/` skill — Talos-fókusz, K3s referenciák kivétele
  - `networking-platform/` skill — Envoy Gateway + Cilium LB-IPAM minta megerősítése (a Cilium L2 + LB-IPAM él, MetalLB referenciák ki); CiliumNetworkPolicy migráció után stateful CNP minta hozzáadása
  - `flux-gitops/` skill — Flux Operator + FluxInstance pattern + cluster-vars/cluster-secrets aktualizálás
  - `external-secrets/`, `sops-secrets/`, `volsync/`, `cloudflare-terraform/` — kisebb frissítések (always-on RD minta a `volsync/` skill-be)
  - `sre/`, `architecture-review/`, `security-review/`, `k8s-workloads/` — sample-ek frissítése Talos/Cilium kontextusra

  *Root `README.md`*: a globális szabály szerint **csak explicit kérésre módosítható**. Külön ASK kell rá; a magyar nyelvű, human-facing áttekintés a `talos` ágon még a K3s világot mutatja (várhatóan).

  **Megközelítés:**
  1. **Olvasási fázis** (~1h): a 13 `docs/*.md` átolvasása, megjelölés (delete / rewrite / minor edit / keep).
  2. **CLAUDE.md lánc audit** (~1-1.5h): top-down, a root → kubernetes → apps sorrendben, a "State To Assume Today" + "Repo-Wide Anti-Patterns" szakaszok aktualizálása.
  3. **Skill refresh** (~1-2h): a 12 skill `SKILL.md` + `references/*.md` átfutása; `taskfiles/` skill sorsa Phase 8-tól függ.
  4. **README.md** (~30 min, opcionális ASK után): a Hungarian human-facing változat.

  **Becsült összmunka**: ~4-6h, parallel-izálható (skill ↔ CLAUDE.md egymástól függetlenül).

  **Miért cutover-előtt**: a `main` branch a hosszú távú forrás; ha a migrációval érkező új repo-modellt a doksi nem tükrözi, minden új AI-session és minden új issue félreértésre épül.

### Tudnivalók / üzemeltetési reminderek

- HP ProDesk 600 G6 DM fent, Talos `v1.13.2` v1.36.1 K8s, `cp0-k8s Ready` (bond0 az aktív kernel device, eno1 a slave).
- PC801 + PC711 NVMe beszerelve és felismerve.
- ✅ 1Password `HomeOps/talos` + `HomeOps/homelab-age-key` (`privateKey` field) + `HomeOps/1password-connect-kubernetes` (`credentials` + `token`) item-ek mind verifikálva.
- ✅ Cilium runtime up + L2 announce egyedül felelős az LB IP-kért (CiliumLoadBalancerIPPool `.15-.25` 11 IP, default policy `^bond[0-9]+$`).
- ✅ ClusterSecretStore `onepassword-connect` Valid/Ready.
- ⚠️ **Talos reboot reminder**: Bármely Talos reboot/apply-node után `kubectl get nodes` → ha `SchedulingDisabled`, `kubectl uncordon cp0-k8s` (a bond0-reboot drain után nem uncordon-ol automatikusan, ez minden Pod Pending-jét okozza — időigényes diagnosztika; a mai session-ben az envoy-gateway certgen Job is ezen akadt el).
- ⚠️ **`safe-upgrades` VAP kihagyott bootstrap pattern**: A `00-crds.yaml` `yq` szűrője csak `CustomResourceDefinition`-t enged át, így a Gateway API `ValidatingAdmissionPolicy` és `ValidatingAdmissionPolicyBinding` **nem jut be a bootstrap apply-ba**. Egyezik a bjw-s/onedr0p/buroa mintával, de ha valaha az első Helm install újra timeout-ol (certgen Job-on), ugyanaz a recovery kell (`kubectl delete vap/vapb safe-upgrades.gateway.networking.k8s.io` + `flux reconcile hr envoy-gateway --force`).

## Frissítési konvenció

- Minden fázis végén frissül a fenti tracker tábla.
- A `README.md` "Status — élő tracker" szekciója és ez a doc szinkronban marad — ez a részletesebb, a README-ben rövidebb pillanatkép.
- Új sub-task / blocker → ide az "Open items" alá.
