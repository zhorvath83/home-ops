# Migration status

Élő státusz a K3s → Talos migráció állapotáról. Ez a doc gyors pillanatkép — a részletes terv a [README.md](./README.md)-ben és a `00`–`14` doc-okban van.

**Utolsó frissítés:** 2026-05-16 késő este — Phase 1–9 + 11 + **15.a** ✅, ingress stack stabil, CNP migráció kész, Task→Just teljes migráció lezárva, Renovate `.renovaterc.json5` + `.renovate/` fragmens-szerkezetre átírva, default ns ks.yaml lapítás kész (4 split + 2 KS rename), follow-up-ok rögzítve.

## TL;DR

**Hol tartunk:** Teljes GitOps reconcile zöld (**0 Failing KS, 0 Failing HR**). 17 VolSync PVC restore-olt OVH Kopia snapshotokból, 18 default app pod 1/1 Running, `cloudflare-tunnel` 1/1 Running. A `replicationdestination + dataSourceRef` mostantól **always-on** pattern (bjw-s minta). Ingress stack él kívülről (Cloudflare tunnel) és belülről (envoy-internal `192.168.1.18`), Cilium L2 announce egyedüli LB-IPAM. Stateful ingress hardening visszahozva 3 `CiliumNetworkPolicy`-val + közös `CiliumCIDRGroup/cloudflare`-rel. A régi K3s cluster áll.

**Ismert follow-up-ok** (egyik sem blocker): `envoy-gateway` v1.9.0 GA → BTP rate-limit visszakapcsolás, search domain `lan` cluster-szintű kezelés, **Phase 15.b** doc + AI-guide refresh és **15.c** per-app CNP threat-model audit (15.a kész).

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

### Este — Phase 9 Renovate rewrite

Doc 09 terv végrehajtva: `.github/renovate.json5` + `.github/renovate/*.json` (6 fragmens) törölve, helyettük `.renovaterc.json5` a repo gyökerében + `.renovate/` alatt 7 `.json5` fragmens (`allowedVersions`, `autoMerge`, `customManagers`, `disabledDatasources`, `groups`, `overrides`, `prBodyNotes`). A 3 referencia repó (`bjw-s-labs/home-ops`, `onedr0p/home-ops`, `buroa/k8s-gitops`) Renovate konfigjai átfutva — mindhárom ezt a layoutot használja, a `bjw-s-labs` `bjw-s/renovate-config` shared base-szel, `onedr0p`/`buroa` self-contained módon.

**3 pragmatic deviáció a doc 09 tervtől** a tényleges repo állapot alapján:
1. **`mise.toml` annotáció-fedés**: a doc 09 `customManagers` annotated-regex matcher file pattern (`/^kubernetes/.+\.yaml(?:\.j2)?$/`) nem fedte volna le a `mise.toml` `[env]` blokk `# renovate: datasource=github-releases depName=siderolabs/talos\nTALOS_VERSION = "v1.13.2"` annotációját. Hozzáadva: `/(^|/)mise\.toml$/` pattern. A `[tools]` szekciót (`talosctl`, `kubectl`, `helm` stb.) Renovate beépített `mise` managere natívan kezeli.
2. **`kubernetes/kubernetes` depName pin**: a mise.toml `KUBERNETES_VERSION = "v1.36.1"` annotációja `depName=kubernetes/kubernetes`-t használ (nem `/kube-apiserver/` formát) → felvéve az `allowedVersions.json5` K8s pin `matchPackageNames` listájába a doc 09 terv eredeti listája mellé.
3. **Talos factory image regex harmless**: a `kubernetes/talos/machineconfig.yaml.j2` `image: factory.talos.dev/metal-installer/{{ ENV.TALOS_SCHEMATIC_ID }}:{{ ENV.TALOS_VERSION }}` Jinja templated — literális verziót nem tartalmaz, így a doc 09 Talos image regex nem matchel rá. Megtartva forward-compat-nak (ha valaha hardcode-olt installer URL kerül a repóba, automatikusan elkapja); a tényleges Talos verzió-tracking a `mise.toml` annotáción át megy.

**Megőrzött live behavior**: minimumReleaseAge 3 nap, dependency dashboard, semantic commits, trusted publisher digest+minor+patch auto-merge (`home-operations`, `onedr0p`, `bjw-s`, `bjw-s-labs`, `coredns`), helm minor/patch auto-merge, plex/qbittorrent `loose` versioning, calibre-web-automated `V`/`v`-prefixed regex versioning, pre-commit hook auto-merge, Flux controller disable. **Új**: K8s 1.36.x pin (manuális `just talos upgrade-k8s` miatt), helmfile manager a bootstrap chart verziókhoz, OCI URI regex matcher, `.yaml.j2` Talos template pattern.

**Verifikáció**: node-os JSON5 parse-check mind a 8 fájlon zöld, `pre-commit run --files` zöld. Renovate CLI validator npm cache-corruption miatt nem futott (npm cache `sudo chown` user-intervenciót igényel — nem blocker, a cloud Renovate megfogja a `talos` branch push után). `.claude/skills/versions-renovate/SKILL.md` + `references/config-files.md` frissítve az új layouttal.

### Késő este — Phase 15.a lezárás (default ns ks.yaml flatten + 2 KS rename)

Doc 15 terv 15.a alfázisa végrehajtva, **a tervhez képest +1 scope-bővítés**: a `qbittorrent-upgrade-p2pblocklist` átnevezve `qbittorrent-p2pblocklist`-re (HR + OCIRepo + controllers/SA/RBAC ref-ek is — full bjw-s `app == KS == HR` parity, nem csak KS-rename). 4 split + 2 KS rename egyetlen commit-ban (`b6101942f`):

- **paperless-gpt** (path-only split, KS név változatlan): `paperless/gpt/` → `paperless-gpt/app/`
- **plex-trakt-sync** (path-only split, KS név változatlan): `plex/trakt-sync/` → `plex-trakt-sync/app/`
- **backrest** (split + KS rename `restic-gui` → `backrest`): `resticprofile/gui/` → `backrest/app/`, full bjw-s parity (a HR/OCIRepo/RS/RD/PVC/ES neve már korábban is `backrest` volt az `APP: backrest` substitution miatt)
- **qbittorrent-p2pblocklist** (full rename `qbittorrent-upgrade-p2pblocklist` → `qbittorrent-p2pblocklist`): mappa + KS + HR + OCIRepo + `controllers.<name>` + `serviceAccount.<name>` + RBAC `subjects.name` mind átnevezve

**Deploy procedúra — 2 KS prune-mitigáció**: A 2 KS-rename (`restic-gui` → `backrest` és `qbittorrent-upgrade-p2pblocklist` → `qbittorrent-p2pblocklist`) prune-kockázattal jár — a régi KS prune-ja le akarná törölni a HR-t a régi `kustomize.toolkit.fluxcd.io/name` labellel, mielőtt az új KS adoptálná. Mitigáció:

1. `flux suspend kustomization restic-gui -n flux-system` + `flux suspend kustomization qbittorrent-upgrade-p2pblocklist -n flux-system` (push **előtt**)
2. `git commit` + `git push`
3. `flux reconcile source git flux-system -n flux-system` + `flux reconcile kustomization cluster-apps -n flux-system`
4. `cluster-apps` parent prune **automatikusan eltávolítja** a régi KS objektumokat (mivel már nem szerepelnek a `default/kustomization.yaml`-ben). A suspend miatt a régi KS prune-jai nem futnak le, így a HR-eket NEM viszik el magukkal.
5. SSA ownership-transfer: az új KS reconcile-ja átveszi a HR-t új `kustomize.toolkit.fluxcd.io/name` labellel.

**Tanulság — orphan cleanup szükséges HR-rename esetén**: A `backrest` rename **adoptálta** a meglévő HR-t (HR neve már `backrest` volt — csak a label cserélődött, Helm release v2 upgrade-re ment). A `qbittorrent-p2pblocklist` viszont **új HR neve**, így a Helm a régi `qbittorrent-upgrade-p2pblocklist` release-t orphan-ben hagyta: a HR + OCIRepository + helm-managed SA/Role/RoleBinding/CronJob mind élt a clusteren. Manuális cleanup: `kubectl delete hr qbittorrent-upgrade-p2pblocklist -n default` (cascade-eli a helm uninstall-t és minden chart-managed resource-t) + `kubectl delete ocirepository qbittorrent-upgrade-p2pblocklist -n default` (külön Flux source). **Tanulság**: ha a HR neve is változik, a Helm release nem adoptálódik át (Helm a `metadata.name`-mel azonosít), ezért manuális helm-uninstall kell a régi release-re. KS-rename HR-name-megőrzéssel (mint a backrest) viszont tisztán SSA-ownership-transfer.

**Verifikáció**: a Plex pod uptime **változatlan** (5h28m a deploy előtt és után — SSA no-op, byte-identical HR spec). 8 érintett KS mind Ready=True az új revision-on (`b6101942`). HR labels megerősítve: `backrest` és `qbittorrent-p2pblocklist` HR-ek új `kustomize.toolkit.fluxcd.io/name` címkével. OVH Kopia repo binding változatlan (a `${APP}` substitution értékek nem cserélődtek), K3s-éra adatok továbbra is elérhetők. `just volsync restore-into` recipe doc-stringjéből a `ks=restic-gui` override-említés eltávolítva — `just volsync restore-into default backrest 0` mostantól override nélkül megy.

### Este — Phase 9 finomítás (4 referencia-repo közelítés)

Az első körös Phase 9 lezárás után második iteráció a 3 referencia repó (`bjw-s-labs`, `onedr0p`, `buroa`) mintáira támaszkodva — 4 konkrét failure-mode-záró / zaj-csökkentő deviáció a doc 09 tervtől, 2 új fragmenssel (`semanticCommits.json5`, `talosFactory.json5`).

**1. `registryAliases: { "mirror.gcr.io": "docker.io" }`** a `.renovaterc.json5`-ben. A `kubernetes/bootstrap/helmfile.d/00-crds.yaml` `oci://mirror.gcr.io/envoyproxy/gateway-helm` chartja erre a proxyra mutat, ami csak Docker Hub read-only mirror. Az alias nélkül a Renovate a proxyt query-zi, ami időnként outdated választ ad — alias-szal a `docker.io` source-of-truth ellen megy.

**2. `custom.talos-factory` datasource** a `talosFactory.json5`-ben. A `https://factory.talos.dev/versions` JSON endpoint csak a factory által ténylegesen buildelhető verziókat listázza. Az eredeti `github-releases` minden `siderolabs/talos` release-t tartalmazott, beleértve azokat is, amiket a factory image-build még nem ért utol — Renovate PR-t nyithatott egy nem-buildelhető verzióra, ami `just talos apply-node`-nál `image pull failed`-del bukott volna. A regex és az ehhez tartozó `addLabels: ["renovate/talos"]` packageRule együtt kiköltözött a `customManagers.json5`-ből egy önálló `talosFactory.json5` fragmensbe (onedr0p/buroa pattern).

**3. `:automergeBranch` preset + globális `automergeType: "branch"`** az `autoMerge.json5`-ben minden szabálynál. A digest/minor/patch auto-merge most direkt branch-push, nem PR-create-then-merge — kevesebb dashboard-zaj, ugyanazok a checkek futnak.

**4. Külön `semanticCommits.json5` fragmens** (onedr0p mintára adaptálva). Az alapértelmezett `:semanticCommits` preset general `chore(deps): update X` formát ad; ezt finomítja per-update-type (`feat` major/minor, `fix` patch, `chore` digest) + per-datasource scope (`container`/`helm`/`github-action`/`github-release`/`talos`) + helmfile + pre-commit topic. Példa: `feat(container): image ghcr.io/foo/bar ( v1.2.3 ➔ v1.3.0 )`. A korábbi `overrides.json5`-beli redundáns docker commit-üzenet szabály eltávolítva, hogy ne ütközzön.

**Verifikáció**: node-os JSON5 parse-check mind a 10 fájlon zöld, `pre-commit run --files` zöld. `references/config-files.md` frissítve az új fragmens-listával és viselkedéssel. Cloud Renovate a `talos` branch push után detektálja az új konfigot.

### Késő este — Phase 9 hotfix CNP regresszió + bjw-s-labs CCNP baseline + paperless CNP

A `4f4b76eec` CNP-migráció (K8s NetworkPolicy → CiliumNetworkPolicy) **3 órás regressziót** okozott a `cloudflare-tunnel` → `envoy-external` és az `envoy-external` xDS pályán. A 3 régi CNP (`cloudflare-tunnel`, `envoy-external`, `envoy-internal`) ingress-allowlist-jén default-deny modellben volt — a kimenő flow-k return SYN-ACK csomagjait a Cilium stateful CT nem találta meg, drop-pal mentek. A `dial tcp 10.245.194.164:443: i/o timeout` + `gRPC config stream to xds_cluster closed since 11225s ago` evidence.

Két lépés rendezte a regressziót:

**1. bjw-s-labs CCNP baseline + Cloudflare SecurityPolicy** (`fd6dcf362`). 2 cluster-wide CCNP `kubernetes/apps/kube-system/cilium/netpols/` alá:
- `allow-cluster-egress` — minden pod-ra hat opt-out label (`egress.home.arpa/custom-egress: DoesNotExist`) hiányában; `toEndpoints: [{}]` + `toEntities: [cluster, world]` széles egress engedély
- `allow-dns-egress` — minden pod-ra (`endpointSelector: {}`); UDP/53 + **TCP/53** kube-dns-re L7 DNS proxy-val (`rules.dns.matchPattern: "*"`) — Hubble flow event minden DNS query-re

Plus `cilium-netpols` Flux Kustomization `dependsOn: cilium`, `paperless` per-app ingress CNP (Tier I minta, opt-out label nélkül), és **`SecurityPolicy/envoy-external-cloudflare`** L7 source-CIDR allowlist a 22 Cloudflare CIDR-re (`gateway-policies.yaml`-ben). Az `update_cloudflare_networks.py` workflow script bővítve `update_securitypolicy()` függvénnyel: multi-doc YAML round-trip `yaml.load_all`/`yaml.dump_all`-lal, kommentár-megőrzéssel; a daily cron most mind a `CiliumCIDRGroup`-ot, mind a `SecurityPolicy` `clientCIDRs` listáját szinkronban tartja.

**2. socketLB.hostNamespaceOnly fix + envoy CNP egyszerűsítés** (`16cb5bf87`, `c587a288c`). A baseline CCNP applikálás után smoke-test bizonyította, hogy a regresszió **MÉG MINDIG** él. Cilium drop monitor evidence:
```
xx drop (Policy denied) flow ... 10.245.66.4:18000 -> 10.244.0.189:44022 tcp SYN, ACK
```
A SYN-ACK source-ja a `envoy-gateway` **SERVICE IP** (nem a backend pod IP) — a Cilium CT entry a Service IP-vel rögzült, és a reply nem matchelt vissza. Root cause: `socketLB.hostNamespaceOnly: true` + `bpf.datapathMode: netkit` interakció. A `true` setting (régi Talos/Istio bootstrap minta-másolásból, NEM Istio-szükségletből — bjw-s-labs is `true`-n megy, de **veth datapathon**, ahol a tc-LB CT-handling robust) a netkit datapath-ban a service-IP translation-t a per-packet tc-LB BPF prog-ra kényszeríti, ami a Service IP-t rögzíti CT-be. A chart default `false` — `connect()`/`sendmsg()` cgroup BPF hook a kernel socket-et a backend pod IP-re köti, CT pod-to-pod-ot tárol, return flow tisztán matchel.

Cilium kutatás megerősítette: a fix `hostNamespaceOnly: false` (kommentár a HR-ben miért volt félrevezető a `true` mindkét repóban). Plus **Cél 1** az envoy CNP-kre — a teljes `egress:` szekciót törölve (DNS, cluster, world 443 mind a CCNP baseline-on fedett; `kube-apiserver` nem hívott az envoy proxy oldaláról, csak a controller hívja). Az ingress allowlistek változatlanok, mert az adja a valódi védelmi értéket (lateral move blokk a TCP handshake-en, a Gateway L7 előtt).

**Verifikáció**:
- `bpf-lb-sock-hostns-only: "false"` a cilium-config ConfigMap-ben ✓
- envoy-external xDS stream stabil az új pod-on (`cds: 22 cluster(s)` + 4 listener init, nincs új `connection timeout`) ✓
- cloudflare-tunnel 4 QUIC connection Registered, nincs új `Unable to reach the origin service` ✓
- `curl -I https://docs.${PUBLIC_DOMAIN}` → `HTTP/2 302` (paperless), `curl -I https://dash.${PUBLIC_DOMAIN}` → `HTTP/2 200` (homepage) ✓
- Cilium drop monitor 10s window → 0 valódi network drop ✓
- envoy CNP-k egress szekciója üres (`kubectl get cnp -n networking envoy-external -o jsonpath='{.spec.egress}'` → empty) ✓

**Talos-quirk reminder élesedett**: a Cilium HelmRelease upgrade hook drain-elte a node-ot (`Ready,SchedulingDisabled`), a friss `envoy-external` és `cloudflare-tunnel` pod-ok FailedScheduling-ba kerültek (`0/1 nodes are available: 1 node(s) were unschedulable`). Mitigáció: `kubectl uncordon cp0-k8s` — a STATUS.md "Talos reboot reminder" pontja most már a **Cilium HR upgrade-re is érvényes**.

**Phase 15.c plan-update** (`52c607120`): a per-app CNP audit szekció kibővítve a **B-csapdával** (opt-out label custom egress nélkül = csak DNS marad, pod indul fail). Két szint formalizálva: **Tier I** (ingress-only, no label, baseline egress — paperless minta) és **Tier II** (ingress + strict egress + opt-out label — pl. magas threat-modelű app-okhoz). A 4f4b76eec-ből megmaradó CNP-k Tier I-re átírva ma — a 3 érintett CNP közül `cloudflare-tunnel` még nem volt egyszerűsítve, az a következő session-re marad (15.c-ben).

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
| 9 | Renovate rewrite | [09](./09-renovate-rewrite.md) | ✅ done | `.renovaterc.json5` + 9 fragmens a `.renovate/` alatt; `.github/renovate*` törölve; `mise.toml` annotáció-fedés, K8s pin `1.36.x`, `mirror.gcr.io → docker.io` alias, `custom.talos-factory` datasource, `:automergeBranch`, külön `semanticCommits.json5` |
| 10 | OMV Ansible | [10](./10-omv-ansible.md) | ⏸ pending | Csak cutover után |
| 11 | Data migration | [11](./11-data-migration.md) | ✅ done | 17 PVC restore-olt (always-on RD) |
| 12 | Cutover runbook | [12](./12-cutover-runbook.md) | 🟡 in-progress | `talos`→`main` merge + FluxInstance ref switch |
| 13 | Rollback / decom | [13](./13-rollback-and-decom.md) | ⏸ pending | |
| 14 | Post-cutover | [14](./14-post-cutover.md) | ⏸ pending | 1-2 hét observation |
| 15 | Repo refactor (ks.yaml flatten + doc + AI-guide refresh) | [15](./15-repo-refactor.md) | 🟡 in-progress | **15.a kész** (4 split + 2 KS rename: `restic-gui`→`backrest`, `qbittorrent-upgrade-p2pblocklist`→`qbittorrent-p2pblocklist`); 15.b doc + AI-guide refresh és 15.c per-app CNP threat-model audit hátra |

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


- **Phase 15 — Repo refactor: ks.yaml flatten + doc + AI-guide refresh** (cutover előtti zárás): két, szorosan kapcsolódó repo-szintű refactor egyetlen fázisba sűrítve.

  **15.a — App-szintű nested `ks.yaml` flatten** (4 split + 1 KS rename). 4 multi-KS `ks.yaml` a `default` ns-ben jelenleg szülő-gyermek mappastruktúrában tart funkcionálisan független KS-eket. A bjw-s/onedr0p/buroa lapos `apps/<ns>/<app>/` mintára kilapítva minden Kustomization egy önálló top-level mappát kap — repo-átláthatóság + `restore-into <app>` ks-override nélkül megy.

  | Jelenlegi | Cél | Megjegyzés |
  |---|---|---|
  | `default/paperless/{app,gpt}/` | `default/paperless/app/` + `default/paperless-gpt/app/` | KS-név változatlan, csak path |
  | `default/plex/{app,trakt-sync}/` | `default/plex/app/` + `default/plex-trakt-sync/app/` | KS-név változatlan, csak path |
  | `default/qbittorrent/{app,upgrade-p2pblocklist}/` | `default/qbittorrent/app/` + `default/qbittorrent-upgrade-p2pblocklist/app/` | KS-név változatlan, csak path |
  | `default/resticprofile/{app,gui}/` (KS `restic-gui`) | `default/resticprofile/app/` + `default/backrest/app/` (KS **`backrest`**, HR-rel megegyező) | **KS rename** — full bjw-s parity, `restore-into backrest` ks-override nélkül |

  Platform-szintű multi-KS-eket (`networking/envoy-gateway/{certificate,app,config}`, `cert-manager/{cert-manager,issuers}`, `kube-system/cilium/{app,config}`, `volsync-system/volsync/{app,maintenance}`, `flux-system/addons/{alerts,webhooks}`) **nem érintjük** — ezek a referencia repokban is multi-KS staging mintázattal élnek (szigorú `dependsOn` sorrend).

  Kockázat: 3 path-only split alacsony (Flux a `kustomize.toolkit.fluxcd.io/name` label alapján észleli a path-váltást, nincs ownership transfer). **A `restic-gui` → `backrest` KS rename** valós prune-kockázattal jár: a régi KS prune-ja megpróbálná törölni a HR-t a régi labellel. Mitigáció: előbb a régi KS-t `prune: false`-ra vagy `flux suspend`-be, csak utána a forrás-fájlokat törölni. Becsült munka: ~30-45 perc.

  **Hol feltételezünk `app == KS == HR` egyezőséget a repo-ban** (audit eredménye — mindegyik a 15.a után stimmelni fog automatikusan):

  - **`kubernetes/components/volsync/*.yaml` `${APP}` substitution**: a `replicationsource.yaml` (`name: ${APP}`, `sourcePVC: ${VOLSYNC_CLAIM:=${APP}}`, `repository: ${APP}-volsync-secret`), `replicationdestination.yaml` (`name: ${APP}-bootstrap`, `repository: ${APP}-volsync-secret`, `sourceIdentity.sourceName: ${APP}`), `pvc.yaml` (`name: ${VOLSYNC_CLAIM:=${APP}}`, `dataSourceRef.name: ${APP}-bootstrap`), `externalsecret.yaml` (`name: ${APP}-volsync`, `target.name: ${APP}-volsync-secret`). Az `APP` érték a `ks.yaml` `postBuild.substitute`-jából jön — ma a `restic-gui` KS-ben `APP: backrest`, ezért a generált RS/RD/PVC/ES nevek `backrest`-ek, **csak a Flux Kustomization neve és `commonMetadata` címkéje (`restic-gui`) divergál**. A 15.a után a KS is `backrest` lesz, minden réteg azonos nevet kap.
  - **`just volsync restore-into ns app [previous] [ks]`**: a `ks` paraméter default `app`, de a backrest-hez ma `ks=restic-gui` override kell. 15.a után az override **fölöslegessé válik**, lehet törölni a recipe doc-stringjéből és a STATUS.md példáiból.
  - **`just volsync restore app`**: az `${app}-bootstrap` RD-t patcheli — a név a `${APP}` substitutionból jön, a flatten után is `backrest-bootstrap` marad, **változás nincs**.
  - **`just volsync list-snapshots/rs-status/snapshot/wait-rd`**: ezek nyersen pozicionálisan veszik a RS/RD nevét, **nem feltételeznek KS-egyezőséget** — változás nincs.
  - **`dependsOn` referenciák**: `git grep -E "name:\s+(restic-gui|paperless-gpt|plex-trakt-sync|qbittorrent-upgrade-p2pblocklist)" -- 'kubernetes/**/ks.yaml'` jelenleg **nem ad találatot a `dependsOn`-on belül** (csak a saját `metadata.name`-ben). Tehát a rename nem lánc-tör.
  - **`kubernetes/apps/default/kustomization.yaml`**: 4 új `./<app>/ks.yaml` referencia kell. A flatten lépés része.
  - **Path-szintű `CLAUDE.md`-k és `.claude/skills/*`**: a 15.b-ben átírjuk mind a `paperless/gpt`, `plex/trakt-sync`, `qbittorrent/upgrade-p2pblocklist`, `resticprofile/gui` hivatkozást a lapos szerkezetre — egyúttal a `taskfiles` skill törlés/átírás mellett.

  Ezért is **15.a előbb** sorrend: utána a 15.b dokumentáció-átírások már a lapos struktúrára hivatkozhatnak, nem kell „flatten előtt / után" verziókat tartani.

  **15.b — Doc + AI-guide refresh**. A migráció átszabta a stacket (K3s → Talos, Task → Just, Calico → Cilium, MetalLB → Cilium LB-IPAM, Traefik → Envoy Gateway, bjw-s layout, always-on VolSync). A `docs/migration/00–14` doc-ok ezt tükrözik, de a többi repo-doksi és AI-guide nagyrészt még a K3s-éra valóságot írja le.

  Hatáskör: 13 `docs/*.md` (több törlendő — `k3s-readme.md`, `k3s-system-upgrade.md` — vagy átírandó — `networking-readme.md`, `kubernetes-readme.md`, `flux-readme.md`, `host-configuration.md`), 11 path-szintű `CLAUDE.md` (root task-domain lista Just-ra, „Current Repository Shape" + „State To Assume Today" frissítés), 12 `.claude/skills/*` (`taskfiles/` „just" skillé, `versions-renovate/` Phase 9 után fragmens-struktúrára, `networking-platform/` Cilium LB-IPAM + CNP megerősítés, többi kisebb update). Root `README.md` csak explicit ASK után. Becsült munka: ~4-6h, parallel-izálható.

  **Sorrend**: 15.a előbb — a flatten után a CLAUDE.md / skill leírások már lapos szerkezetre hivatkozhatnak, nem kell kétszer írni.

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
