# Migration status

Élő státusz a K3s → Talos migráció állapotáról. Ez a doc gyors pillanatkép — a részletes terv a [README.md](./README.md)-ben és a `00`–`14` doc-okban van.

**Utolsó frissítés:** 2026-05-16 este — Phase 1–8 + 11 ✅, ingress stack stabil, CNP migráció kész, Task→Just teljes migráció lezárva, follow-up-ok rögzítve.

## TL;DR

**Hol tartunk:** Teljes GitOps reconcile zöld (**0 Failing KS, 0 Failing HR**). 17 VolSync PVC restore-olt OVH Kopia snapshotokból, 18 default app pod 1/1 Running, `cloudflare-tunnel` 1/1 Running. A `replicationdestination + dataSourceRef` mostantól **always-on** pattern (bjw-s minta). Ingress stack él kívülről (Cloudflare tunnel) és belülről (envoy-internal `192.168.1.18`), Cilium L2 announce egyedüli LB-IPAM. Stateful ingress hardening visszahozva 3 `CiliumNetworkPolicy`-val + közös `CiliumCIDRGroup/cloudflare`-rel. A régi K3s cluster áll.

**Ismert follow-up-ok** (egyik sem blocker): `envoy-gateway` v1.9.0 GA → BTP rate-limit visszakapcsolás, search domain `lan` cluster-szintű kezelés, **Phase 8.6** app-szintű nested ks.yaml flatten (4 split + 1 KS rename), **Phase 9** Renovate rewrite, **Phase 15** repo doc + AI-guide refresh.

## Sessions — 2026-05-16

A bootstrap és Phase 4–7 lezárása aznap történt; az ingress és adatmigráció több iteráción át tisztult ki estére. Részletes commit-történet `git log` alatt; alább csak a tartós tanulságok.

### Reggel — Phase 4 bootstrap

`just k8s-bootstrap cluster` végigfutott (7 release deployed), 8 bootstrap-időszaki javítás (`f67cb9db7..c1fc548d3` commit-tartomány), `FluxInstance Ready`, `ClusterSecretStore onepassword-connect Valid/Ready`. Egy session-záró blokker maradt: a `snapshot-controller` HR `failed-install` ragadt, ami minden PVC-igénylő appot Pending-ben tartott.

### Délután — Phase 6 záró + adatmigráció

- A `snapshot-controller` magától visszaállt (Flux retry-loop), innen folytattuk.
- **Phase 6 záró cleanup** (`478446aaf`): K3s-éra subtree-k (`tigera-operator/`, `networking/metallb/`, `system-upgrade/system-upgrade-controller/`) repo-szintű törlése.
- **Cilium LB-IPAM annotáció csere** (`e90d92ca0`): `metallb.io/loadBalancerIPs` → `lbipam.cilium.io/ips` minden érintett Service-en.
- **Új komponens verziók** (`d094085d5`): `external-secrets` 2.5.0 + `kube-prometheus-stack` 85.1.1 bjw-s parityre.
- **BTP regression** (`778571544`): a `rate-limit-external` BackendTrafficPolicy K8s 1.36 strict OpenAPI alatt elbukik (upstream Envoy Gateway v1.8.0 hiba, `envoyproxy/gateway#8798` — `uint32` Go-type → `format: int32 + maximum: uint32_max` CRD ellentmondás). Manifest kommentbe téve, visszakapcsolás envoy-gateway v1.9.0 GA-kor. Cloudflare WAF amúgy is fedez.
- **safe-upgrades VAP recovery**: az első Helm install timeout-olt a `certgen` Job-on (node `SchedulingDisabled` volt Talos reboot drain miatt) — recovery: `kubectl uncordon`, `kubectl delete vap/vapb safe-upgrades.gateway.networking.k8s.io`, `flux reconcile hr envoy-gateway --force`.
- **Kopia + external-dns HR recovery**: mindkettő `MissingRollbackTarget`-tel ragadt — `helm uninstall` + `flux reconcile hr --force` (KS reconcile NEM elég).
- **Always-on VolSync component** (`a9d5a5f79`): a `replicationdestination.yaml` + `pvc.yaml dataSourceRef` engedélyezve a komponensben, mostantól minden PVC `${APP}-bootstrap` RD-ből populálódik.
- **Adatmigráció**: 17 PVC újrakreálás (`dataSourceRef` immutable, így a régi üres PVC-ket törölni kellett). Egy ideiglenes NetworkPolicy `policyTypes: [Egress]`-only workaround zárta le a délutánt — ezt este a CNP migráció váltotta fel véglegesen.

### Este — több iteráció

Az esti session 4 különálló problémát zárt le, mindegyik más-más tüneten csapott le ugyanarra az alap-okra. Sorrend, ahogy bukkantak elő:

**1. Orphan `metallb` HR runtime cleanup**. Tünet: external irányból minden zöld, belülről homepage akadozik, `subscriptions.${PUBLIC_DOMAIN}` teljesen elérhetetlen. Diagnose: a `cilium-operator-lb-ipam` beírta a `192.168.1.18`-at a Service `status.loadBalancer.ingress` mezőbe, majd a `metallb-controller` (amelynek nincs `IPAddressPool`-ja) **letörölte** — két LB-IPAM versenyzett. A reggeli `flux suspend` + délutáni repo subtree delete kombináció hagyott egy **árva** `HelmRelease/metallb`-t a `networking` namespace-ben, amit a helm-controller újra-installált 2 órája. Fix: `kubectl delete hr -n networking metallb`. Eredmény: `envoy-internal` és `k8s-gateway` stabil `192.168.1.18` / `.19`. **Tanulság**: a Flux **Kustomization suspend → repo subtree delete** kombináció árva child HR-eket hagy. Cutover előtt `kubectl get hr -A` futtatás és parent-elhúzott HR-ek törlése javasolt; vagy `prune: true` mellett a Kustomization direkt törlése.

**2. PVC újratöltés helyes Kopia snapshotokból**. Tünet: a délutáni „17/17 RD synced" valójában egy üres, Talos-éra Kopia snapshot-ot húzott le. Az üres snapshot(ok) az OVH bucketről manuálisan törölve, fresh restore futott. Procedúra app-onként: `flux suspend hr` → `kubectl scale deploy --replicas=0` → `kubectl delete pvc <app>` **és** `kubectl delete rd <app>-bootstrap` (mindkettő kritikus, lásd Tanulság) → `flux resume hr` + `flux reconcile ks <app>` → új PVC + új RD `manual: restore-once` triggerrel → `kubectl scale deploy --replicas=1`. A `backrest` egy speciális eset: Flux Kustomization-je `restic-gui` néven él (nem `backrest`), külön reconcile kell. Eredmény: 17/17 RD synced 11s–1m48s alatt, validált tartalom (sonarr 373M, plex 964M, radarr 313M, paperless 445M / 3485 doc-fájl, stb.). **Tanulság 1 — always-on RD**: az `IfNotPresent` SSA címke miatt az RD egyszer fut le `restore-once`-szal és statikus marad. Új Kopia-fetch indításához a PVC-t **és** a `<app>-bootstrap` RD-t **mindkettőt** törölni kell, különben az új PVC az RD `status.latestImage`-ből populálódik a régi VolumeSnapshot-tal. **Tanulság 2 — paperless path felülírás**: a paperless `helmrelease.yaml` `PAPERLESS_DATA_DIR=/data/local/data` és `PAPERLESS_MEDIA_ROOT=/data/local/media` env-blokkja **felülírja** az upstream image default `/usr/src/paperless/...` path-jait. Restore-verifikációkor a manifest env-blokkját kell olvasni, nem az upstream defaultot feltételezni. **Tanulság 3 — várt zaj**: minden `dataSourceRef`-alapú restore generál 1-app `Warning ClaimMisbound: Two claims are bound to the same volume` event-et a `vs-prime-<uuid>` PVC-n. Ez a SIG-storage volume-populator framework átmeneti staging PVC-je, a transzfer végén törlődik. Nem hiba, expected noise minden home-ops repóban (bjw-s, onedr0p, buroa).

**3. CiliumNetworkPolicy migráció — ingress hardening visszahozva** (`4f4b76eec`). A délutáni workaround a 3 K8s `NetworkPolicy`-t `policyTypes: [Egress]`-re csökkentette, mert a Cilium az ingress oldalon statelessül kezeli az UDP reply pakettokat (a CoreDNS válasz random destination porton érkezik, nem matchel ingress rule-lal → drop). Ez ingress hardening regressziót okozott. A `CiliumNetworkPolicy` stateful conntrack-kal megoldja: 3 K8s NP → 3 CNP + 1 közös `CiliumCIDRGroup/cloudflare` (cluster-scoped, 22 CF CIDR, DRY). Cilium endpoint policy state mindhárom pod-on Enabled/Enabled, ingress smoke HTTP 200 kívül-belül, 0 új pod-restart. A `CiliumCIDRGroup` namespace-mezővel rendelkezik a kustomization `namespace: networking` direktívája miatt — az API server cluster-scoped erőforrásokon ezt csendben ignorálja, tisztább megoldás lenne kustomize patch-csel kivenni.

**4. Cloudflare CIDR auto-update workflow retarget** (`4d5d93035`). A `.github/workflows/update-cloudflare-networks.yaml` (napi cron) a most törölt `networkpolicy.yaml`-t targetelte; a python script `spec.externalCIDRs`-t frissít a `CiliumCIDRGroup`-on. Env var: `NETWORKPOLICY_FILE` → `CIDRGROUP_FILE`. Lokálisan venv-ben stubbolt API-val validálva (formátum-megőrzés, diff-detekció OK). **Mellék-megerősítés**: a `https://api.cloudflare.com/client/v4/ips` aktuális listája byte-azonos a commitolt 22 CIDR-rel (etag `38f79d050aa027e3be3865e495dcc9bc`).

### Este — Phase 8.5 upstream Just parity audit

A `bjw-s-labs/home-ops`, `onedr0p/home-ops`, `buroa/k8s-gitops` Just-fájljainak átfutása után 6 minta adoptálva — érdemi rés vagy quick win, ami nálunk hiányzott. Új vagy módosult recipe-ek a `kubernetes/mod.just`-ban: `view-secret ns secret` (krew plugin wrapper), `volsync-state state` (globális VolSync suspend/resume, kustomization + helmrelease + deployment scale Just conditional expression-nel), `restore-into ns app previous="0"` (onedr0p-style point-in-time rollback: `copyMethod: Direct`, snapshot-offset, írás a meglevő PVC-be — ad-hoc rollback-hoz lényegesen jobb a mostani always-on `restore`-nál, ami csak fresh cluster-bootstraphoz való), `sync resource` (polimorf, validált `hr|ks|gitrepo|ocirepo|es` pattern, 3-annotation push — a régi `sync-all type` ezzel kiváltva, a per-resource `sync-hr/sync-ks/sync-es` megmarad). A `kubernetes/talos/mod.just` kapott `machine-controller node` és `machine-image node` diagnosztikai recipe-eket (rendered machineconfig + yq). A `kubernetes/bootstrap/mod.just` `kubeconfig` recipe kibővítve `lb="cilium"` (default) / `"node"` argumentummal, a `cluster:` chain végén egy második `kubeconfig` futás re-pulleli a Cilium-LB-helyes endpoint-tal (single-node-on most no-op, multi-node-jövőre future-proof).

### Este — Phase 8 zárás (Task → Just teljes migráció)

A Phase 8 foundation (mise + just + setup.sh + 6 mod) reggel kész volt, de a `Taskfile.yml` és `.taskfiles/` lemaradt mert pár domain nem volt teljes lefedettséggel migrálva. Lefedettségi audit után **minden releváns task** (`so:`, `hm:openwrt*`, `vs:status`, `vs:list`, `vs:maintenance`, `vs:last-backups`, `ku:mount`, `fx:reconcile`, `fx:verify`, `hm:openmediavault` SSH-flow) migrálva a Just oldalra. Eldobva mint elavult: `an:*` (K3s Ansible — Talos váltja), `hm:proxmox` + `hm:k8s-host` + `hm:all` (Proxmox-K3s láncolat), `tf:*` (már a `cloudflare`/`ovh` mod-okban), `fx:install` (`just k8s-bootstrap cluster` váltja), `fx:hr-restart` (= `just k8s restart-failed-hrs`), `fx:nodes/pods/list` (use `kubectl get` / `flux get` directly), `ku:kubeconfig` (Talos-éra: `just talos get-kubeconfig`), `pc:*` (a `pre-commit` CLI-t direkt használjuk), `es:sync` (= `just k8s sync-es` / `sync-all es`).

**Új modulok**: `provision/sops/mod.just` (4 recipe: re-encrypt, fix-mac, encrypt-file, decrypt-file) és `provision/openwrt/mod.just` (3 recipe: maintain, reinstall-packages, upgrade — eredeti ~400 sor bash interaktív sysupgrade flow Just `[script]` recipe-ekbe csomagolva). **`provision/openmediavault/mod.just`** kapott egy `update-host` recipe-et (SSH-alapú `omv-upgrade` + applyChanges + NAS share remount — az aktuális, pre-Phase-10 omv-maintenance út). **`kubernetes/mod.just`** kibővítve: `rs-status`, `kopia-maintenance`, `last-backups` (Python window overview), `mount-pvc`, `flux-reconcile`, `flux-check`; a meglevő `list-snapshots` rich tabular formátumra cserélve.

**Root `.justfile`** kapott `mod sops "provision/sops"` és `mod openwrt "provision/openwrt"` import-okat — most 8 mod-csoport listázódik (`k8s`, `k8s-bootstrap`, `talos`, `omv`, `cloudflare`, `ovh`, `sops`, `openwrt`). **Root `CLAUDE.md`** „Taskfile And Renovate Model" szekciója „Just And Renovate Model"-re cserélve, „Current Repository Shape" `.taskfiles/` hivatkozása `.justfile + **/mod.just`-ra. **Törölve**: `Taskfile.yml` + a teljes `.taskfiles/` (9 mappa, 13 fájl).

**Verifikáció**: `just --list` 8 csoportot mutat, `just sops/openwrt/omv/k8s --list` mind parse-ol és listáz. Egy parse-hiba a Python f-string `{{:<{w}}}` format-spec miatt javítva `str.ljust()`-tal (Just `{{ ... }}` template-szintaxissal ütközött a literal Python escape). A subtree `CLAUDE.md`-k (`provision/CLAUDE.md`, `kubernetes/apps/*/CLAUDE.md` stb.) még tartalmaznak `Taskfile`/`.taskfiles` hivatkozást — ezek Phase 15 hatáskörébe esnek.

## Fázis tracker

| # | Fázis | Doc | Status | Megjegyzés |
|---|---|---|---|---|
| — | Tervezés (docs) | [README](./README.md) | ✅ done | 15 doc kész |
| — | `talos` branch | — | ✅ done | 2026-05-15 |
| 1 | Hardver, hálózat | [01](./01-hardware-and-network.md) | ✅ done | HP + Talos installálva |
| 2 | Talos bootstrap | [02](./02-talos-bootstrap.md) | ✅ done | etcd Healthy |
| 3 | Cilium CNI + L2 announce | [03](./03-cilium-cni.md) | ✅ done | 1.19.4 + Cilium LB-IPAM egyedül felelős |
| 4 | Bootstrap helmfile | [04](./04-bootstrap-helmfile.md) | ✅ done | 7 release deployed |
| 5 | Flux Operator + FluxInstance | [05](./05-flux-operator.md) | ✅ done | 4 controller, 11 CRD |
| 6 | Repo refactor | [06](./06-repo-restructure.md) | ✅ done | bjw-s layout + K3s subtree törlés + LB-IPAM annotáció csere |
| 7 | Components / shared | [07](./07-components-and-shared.md) | ✅ done | Always-on VolSync RD aktív |
| 8 | Just migráció | [08](./08-just-migration.md) | ✅ done | `Taskfile.yml` + `.taskfiles/` törölve, 2 új mod (sops, openwrt), 4 új k8s recipe (rs-status, kopia-maintenance, last-backups, mount-pvc + flux-reconcile/check), root `CLAUDE.md` átírva |
| 9 | Renovate rewrite | [09](./09-renovate-rewrite.md) | ⏸ pending | `.renovaterc.json5` + fragmensek |
| 10 | OMV Ansible | [10](./10-omv-ansible.md) | ⏸ pending | Csak cutover után |
| 11 | Data migration | [11](./11-data-migration.md) | ✅ done | 17 PVC restore-olt (always-on RD) |
| 12 | Cutover runbook | [12](./12-cutover-runbook.md) | 🟡 in-progress | `talos`→`main` merge + FluxInstance ref switch |
| 13 | Rollback / decom | [13](./13-rollback-and-decom.md) | ⏸ pending | |
| 14 | Post-cutover | [14](./14-post-cutover.md) | ⏸ pending | 1-2 hét observation |
| 15 | Repo doc + AI-guide refresh | — | 🟡 in-progress | `docs/*.md` + `CLAUDE.md` lánc + `.claude/skills/*` átírás migráció eredménye alapján; cutover-előtt zárandó |

Legend: ✅ done · 🟡 in-progress · ⏸ pending · ❌ blocked · ⏭ skipped

## Branch model

- **`main`** — a régi K3s cluster GitOps forrása (a K3s VM jelenleg lekapcsolva).
- **`talos`** — az új Talos cluster aktív GitOps forrása (FluxInstance `sync.ref: refs/heads/talos`).
- **Cutover-kor**: `talos` → merge `main`, FluxInstance `sync.ref` átáll `refs/heads/main`-re, a régi K3s VM nem indul újra (1-2 hét standby után decom).

## Open items / blocker

### Aktív blokkoló — nincs

A teljes GitOps reconcile zöld (0 failing KS, 0 failing HR).

### Follow-up — nem blocker

- **`envoy-gateway` v1.9.0 GA → BackendTrafficPolicy visszakapcsolás**: A `rate-limit-external` BTP `kubernetes/apps/networking/envoy-gateway/config/gateway-policies.yaml`-ben kommentbe téve az upstream v1.8.0 CRD regression miatt. Renovate hozza a v1.9.0 GA-t, `git revert` egyszerű.

- **Search domain `lan` cluster-szintű kezelés**: A Talos node `ResolverStatus SEARCH DOMAINS: []` üres. FQDN-szintű `.lan` resolve cluster-en át jelenleg működik (CoreDNS `forward . /etc/resolv.conf`). Akkor szükséges, ha valaha rövid host neveket (`nas`) hivatkoznánk app config-ban — jelenleg minden manifest FQDN-t vagy IP-t használ. Megoldás (csak együtt): Talos machineconfig `machine.network.searchDomains: [lan]` + kubelet `--resolv-conf=/etc/resolv.conf`. Egyik referencia repó sem foglalkozik vele.


- **Phase 8.6 — App-szintű nested ks.yaml flatten** (cutover-előtti repo-tisztítás): 4 multi-KS `ks.yaml` a `default` ns-ben jelenleg szülő-gyermek mappastruktúrában tart funkcionálisan független KS-eket. A bjw-s/onedr0p/buroa lapos `apps/<ns>/<app>/` mintára kilapítva minden Kustomization egy önálló top-level mappát kap — repo-átláthatóság + `restore-into <app>` ks-override nélkül megy.

  **Hatáskör (4 split + 1 KS rename)**:

  | Jelenlegi | Cél | Megjegyzés |
  |---|---|---|
  | `default/paperless/{app,gpt}/` | `default/paperless/app/` + `default/paperless-gpt/app/` | KS-név változatlan, csak path |
  | `default/plex/{app,trakt-sync}/` | `default/plex/app/` + `default/plex-trakt-sync/app/` | KS-név változatlan, csak path |
  | `default/qbittorrent/{app,upgrade-p2pblocklist}/` | `default/qbittorrent/app/` + `default/qbittorrent-upgrade-p2pblocklist/app/` | KS-név változatlan, csak path |
  | `default/resticprofile/{app,gui}/` (KS `restic-gui`) | `default/resticprofile/app/` + `default/backrest/app/` (KS **`backrest`**, HR-rel megegyező) | **KS rename** — full bjw-s parity, `restore-into backrest` ks-override nélkül |

  **Mit NEM érintünk**: a platform-szintű multi-KS-ek (`networking/envoy-gateway/{certificate,app,config}`, `cert-manager/{cert-manager,issuers}`, `kube-system/cilium/{app,config}`, `volsync-system/volsync/{app,maintenance}`, `flux-system/addons/{alerts,webhooks}`) — ezek a referencia repokban is multi-KS staging mintázattal élnek (szigorú `dependsOn` sorrend), nem szervezeti kompromisszumok.

  **Kockázat**: a 3 path-only split (paperless-gpt, plex-trakt-sync, qbittorrent-upgrade-p2pblocklist) alacsony — Flux a `kustomize.toolkit.fluxcd.io/name` label alapján észleli a path-váltást, nincs ownership transfer. **A `restic-gui` → `backrest` KS rename** viszont valós prune-kockázattal jár: a régi KS prune-ja megpróbálná törölni a HR-t a régi labellel. Mitigáció előbb a régi KS-t `prune: false`-ra vagy `flux suspend`-be, csak utána a forrás-fájlokat törölni; a `dependsOn` referenciákat is át kell írni minden helyen.

  **Becsült munka**: ~30-45 perc. Logikus elvégezni Phase 9 (Renovate) vagy Phase 15 (Doc refresh) előtt — utóbbi a megírandó CLAUDE.md-kben már lapos szerkezetet feltételezhet.

- **Phase 15 — Repo doc + AI-guide refresh** (cutover előtti zárás): a migráció átszabta a stacket (K3s → Talos, Task → Just, Calico → Cilium, MetalLB → Cilium LB-IPAM, Traefik → Envoy Gateway, bjw-s layout, always-on VolSync). A `docs/migration/00–14` doc-ok ezt tükrözik, de a többi repo-doksi és AI-guide nagyrészt még a K3s-éra valóságot írja le.

  **Hatáskör**: 13 `docs/*.md` (több törlendő — `k3s-readme.md`, `k3s-system-upgrade.md` — vagy átírandó — `networking-readme.md`, `kubernetes-readme.md`, `flux-readme.md`, `host-configuration.md`), 11 path-szintű `CLAUDE.md` (root task-domain lista Just-ra, „Current Repository Shape" + „State To Assume Today" frissítés), 12 `.claude/skills/*` (`taskfiles/` Phase 8 után „just" skillé, `versions-renovate/` Phase 9 után fragmens-struktúrára, `networking-platform/` Cilium LB-IPAM + CNP megerősítés, többi kisebb update). Root `README.md` csak explicit ASK után.

  **Becsült munka**: ~4-6h, parallel-izálható. Phase 8 + 9 után érdemes belefogni, hogy a doksi-átírás az új struktúrára hivatkozhasson.

## Tudnivalók / üzemeltetési reminderek

- HP ProDesk 600 G6 DM fent, Talos `v1.13.2` v1.36.1 K8s, `cp0-k8s Ready` (bond0 aktív kernel device, eno1 slave).
- 1Password `HomeOps/talos` + `HomeOps/homelab-age-key` (`privateKey`) + `HomeOps/1password-connect-kubernetes` (`credentials` + `token`) item-ek verifikálva.
- Cilium runtime + L2 announce egyedül felelős az LB IP-kért (CiliumLoadBalancerIPPool `.15–.25`, default policy `^bond[0-9]+$`).
- ClusterSecretStore `onepassword-connect` Valid/Ready.
- ⚠️ **Talos reboot reminder**: bármely Talos reboot/apply-node után `kubectl get nodes` → ha `SchedulingDisabled`, `kubectl uncordon cp0-k8s`. A bond0-reboot drain után nem uncordon-ol automatikusan, ez minden Pod Pending-jét okozza.
- ⚠️ **`safe-upgrades` VAP kihagyott bootstrap pattern**: a `00-crds.yaml` `yq` szűrője csak `CustomResourceDefinition`-t enged át, így a Gateway API `ValidatingAdmissionPolicy` és `ValidatingAdmissionPolicyBinding` nem jut be a bootstrap apply-ba. Egyezik a bjw-s/onedr0p/buroa mintával. Ha az első Helm install újra timeout-ol certgen Job-on: `kubectl delete vap/vapb safe-upgrades.gateway.networking.k8s.io` + `flux reconcile hr envoy-gateway --force`.

## Frissítési konvenció

- Minden fázis végén frissül a Fázis tracker tábla.
- A `README.md` „Status — élő tracker" szekciója és ez a doc szinkronban marad — ez a részletesebb, a README-ben rövidebb pillanatkép.
- Új sub-task / blocker → ide az „Open items" alá.
- Hardcoded `${PUBLIC_DOMAIN}` érték **TILOS** session-jegyzőkönyvekben és smoke teszt példákban — placeholdert kell használni.
