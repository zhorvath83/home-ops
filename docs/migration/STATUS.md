# Migration status

Élő státusz a K3s → Talos migráció állapotáról. Ez a doc gyors pillanatkép — a részletes terv a [README.md](./README.md)-ben és a `00`–`14` doc-okban van.

**Utolsó frissítés:** 2026-05-17 — **Phase 8.6 Just hardening + confirm-gates** ✅: 4 destruktív Talos recipe-en `[confirm()]` attribútum (`apply-node`, `reset-node`, `shutdown-node`, `upgrade-node`) + szimmetriai bónusz `upgrade-k8s`-en is, 2 új cluster-wide wrapper (`apply-cluster`, `reset-cluster`), `browse-pvc` + `mount-pvc` egyetlen krew-mentes `browse-pvc claim ns mountpath` recipe-be konszolidálva (utolsó krew plugin dep — `kubectl-view-secret` — is kiváltva `kubectl get secret + jq`-val), `restart-failed-hrs` JSON-alapú detection-re átírva (immune a CLI output drift-re), `volsync state` `[arg]` pattern validation, `node-shell` cleanup trap-be (Ctrl-C-safe), `flux-reconcile` per-stage strukturált logging-gel (timing visibility), settings.json deny bővítve a cluster-wide wrapperekkel. — Korábban: Phase 1–9 + 11 + **15.a + 15.b** ✅, ingress stack stabil, CNP migráció kész, Task→Just teljes migráció lezárva, Renovate `.renovaterc.json5` + `.renovate/` fragmens-szerkezetre átírva, default ns ks.yaml lapítás kész (4 split + 2 KS rename), **K3s `system-upgrade-controller` orphan + `provision/kubernetes/` Ansible plane teljesen lebontva**, doc + AI-guide réteg (`docs/*.md` + 11 `CLAUDE.md` + 12 `.claude/skills/*` + `settings.json` + `README.md`) átírva a `talos`-éra realitásra, follow-up-ok rögzítve.

## TL;DR

**Hol tartunk:** Teljes GitOps reconcile zöld (**0 Failing KS, 0 Failing HR**). 17 VolSync PVC restore-olt OVH Kopia snapshotokból, 18 default app pod 1/1 Running, `cloudflare-tunnel` 1/1 Running. A `replicationdestination + dataSourceRef` mostantól **always-on** pattern (bjw-s minta). Ingress stack él kívülről (Cloudflare tunnel) és belülről (envoy-internal `192.168.1.18`), Cilium L2 announce egyedüli LB-IPAM. Stateful ingress hardening visszahozva 3 `CiliumNetworkPolicy`-val + közös `CiliumCIDRGroup/cloudflare`-rel. A régi K3s cluster áll.

**Ismert follow-up-ok** (egyik sem blocker): `envoy-gateway` v1.9.0 GA → BTP rate-limit visszakapcsolás, search domain `lan` cluster-szintű kezelés, **15.c** per-app CNP threat-model audit (15.a + 15.b kész).

## Sessions — 2026-05-17

### Phase 8.6 — Just hardening + confirm-gates (referencia repó parity-finomítás)

A `bjw-s-labs/home-ops`, `onedr0p/home-ops`, `buroa/k8s-gitops` Just-fájljainak részletes re-auditja után 10 érdemi finomítás. Egyik sem új feature — **kockázat-csökkentés**, **discoverability**, **konvenció-parity** és **operator observability**.

**1. `[confirm()]` attribútum 5 destruktív Talos recipe-en** (`kubernetes/talos/mod.just`). Az `apply-node`, `reset-node`, `shutdown-node`, `upgrade-node` recipe-ek onedr0p/buroa mintájára `[confirm('... [y|N] ?')]` gate-tel — interaktív futtatáskor prompt-ol, `just --yes ...`-szel bypass-olható. Szimmetriai bónusz: `upgrade-k8s`-en is felkerült (control-plane upgrade-state-mutáló). A `kubernetes/bootstrap/mod.just` `talos:` stage `just talos apply-node` hívása `just --yes talos apply-node`-re bővítve, hogy az automatizált `just cluster-bootstrap cluster` chain ne álljon meg a confirm-on. **Live verifikálva**: `echo n | just talos shutdown-node fakenode` → `error: recipe 'shutdown-node' was not confirmed` (a body nem fut), `just --yes ...` → bypass működik.

**2. 2 új cluster-wide wrapper recipe** (`talos apply-cluster`, `talos reset-cluster`). bjw-s minta szerint loopolnak a `kubernetes/talos/nodes/*.yaml.j2` fájlokon keresztül és delegálnak a per-node recipe-re (= per-node confirm prompt). Új `nodes := \`find ./nodes -maxdepth 1 -name '*.yaml.j2' -exec basename {} .yaml.j2 \\;\`` változó, filesystem-alapú (pre-bootstrap-ready). Single-node-on most no-op, multi-node-jövőre future-proof.

**3. `.claude/settings.json` deny bővítés** — a 2 új wrapperrel egyidőben `Bash(just talos apply-cluster:*)` és `Bash(just talos reset-cluster:*)` is a deny listára került, közvetlenül az `apply-node` / `reset-node` mellé. Az agent-permission gate most egységes a per-node és cluster-wide variánsok közt.

**4. `browse-pvc` + `mount-pvc` konszolidálás → 1 általános recipe** (`kubernetes/mod.just`). A `browse-pvc` korábban `kubectl-browse-pvc` krew plugin függőséggel ment, a `mount-pvc` bjw-s-specifikus hardcode-olt `/data/config` mount path-szal. Új unified `browse-pvc claim ns="default" mountpath="/mnt"` recipe: onedr0p `kubectl run --overrides` inline-pod minta (krew-mentes), paraméterezett mount path (default `/mnt` unix konvenció szerint, ráhívható `/data/config`-gal app-template-style debugra), `mirror.gcr.io/alpine:latest` image (`registryAliases` Renovate-trackelt). `mount-pvc` recipe törölve, doc-hivatkozások (`docs/flux-readme.md`, `.claude/skills/just/references/catalog.md`) átvezetve.

**5. `view-secret` krew-mentesítés** (`kubernetes/mod.just`). Az utolsó kubectl krew plugin függőségünk (`kubectl-view-secret`) kiváltva `kubectl get secret -o json | jq -r '.data // {} | to_entries[] | "\(.key)=\(.value | @base64d)"'`-mal. Output-formátum változatlan (`KEY=value` soronként). **Külső kubectl plugin dep-ünk most már nulla** — egy `mise install` után fresh gépen minden Just recipe futtatható, semmilyen krew plugin nem kell. Settings.json policy-neutral: a `kubectl get secret` továbbra is deny-en van a felső szinten, a Just recipe belső shell-ben fut.

**6. `restart-failed-hrs` JSON-alapú detection** (`kubernetes/mod.just`). A régi `kubectl get hr -A | grep False | awk '{print $2, $1}'` text-output parser törékeny volt (oszlop-pozíció drift). Átírva `kubectl get hr -A -o json | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="False")) | "\(.metadata.namespace) \(.metadata.name)"' | while read -r ns name; do ...`-ra. Típushelyes, immune a flux/kubectl CLI output formátum-változásokra.

**7. `volsync state` arg pattern validation** (`kubernetes/volsync/mod.just`). onedr0p/buroa mintára `[arg('action', pattern='suspend|resume')]` attribútum felvéve. Élesben tesztelve: `just --dry-run volsync state pause` → `error: argument 'pause' passed to recipe 'state' parameter 'action' does not match pattern 'suspend|resume'`. Elgépelt értékre fail-fast hibát ad, többé nincs csendes no-op viselkedés.

**8. `node-shell` cleanup trap-be** (`kubernetes/mod.just`). A régi `kubectl debug` után-futtatott cleanup (`kubectl delete pod -l ...`) Ctrl-C esetén nem futott le, orphan debug pod-ot hagyva. onedr0p/buroa `trap '...' EXIT` minta átvéve, plusz `--field-selector spec.nodeName={{ node }}` szűkítéssel (nem írunk át más session debug pod-ját) és `--wait=false`-szal (background delete). Ctrl-C-safe.

**9. `controller_node` rename-figyelmeztető komment** (`kubernetes/talos/mod.just` + `kubernetes/bootstrap/mod.just`). Mindkét `controller`/`controller_node` változó-definíción `// "k8s-cp0"` hardcode-olt fallback szerepel. A recent `cp0-k8s → k8s-cp0` rename (8de1fa5cc / 19d5c9fe5) precedens miatt `# CHECK ON RENAME:` komment hozzáadva mindkét helyre — a fallback-okat szinkronban kell tartani jövőbeli rename esetén.

**10. `flux-reconcile` strukturált per-stage logging** (`kubernetes/mod.just`). A korábbi 3-soros recipe (source → cluster-vars → cluster-apps) bash-`SECONDS`-alapú per-stage timing-gel kibővítve, `just log info "Stage: ..." duration "Ns"` mintával, ami konzisztens a `kubernetes/bootstrap/mod.just` stage-szintű logging-jával. Fail-fast viselkedés változatlan (`[script]` + `bash -euo pipefail`): bármelyik stage rc=1-je → script abort, a következő stage NEM indul. Session-debug során most látható melyik stage húzza el az időt (tipikusan a cluster-apps a child KS-ek miatt).

**Verifikáció**: `just --list k8s`, `just --list talos`, `just --list volsync` parse zöld; `just --dry-run volsync state suspend` és `pause` runtime arg-pattern viselkedést mutat; `just --yes --dry-run talos shutdown-node fakenode` és `echo n | just --dry-run talos shutdown-node fakenode` a confirm-gate két útvonalát mutatja; `just --dry-run k8s flux-reconcile` a strukturált script-body-t mutatja `t0…t3` változókkal. `pre-commit run --all-files` zöld (13/13 hook Passed).

**Followup nélkül**: nincs blocker. F1 (sync recipe `ns name` param-sorrend cseréje) tudatos halasztás — a 3 referencia parity-rés, de behavioral-equivalent, későbbi session-re hagyható.

## Sessions — 2026-05-16

A bootstrap és Phase 4–7 lezárása aznap történt; az ingress és adatmigráció több iteráción át tisztult ki estére. Részletes commit-történet `git log` alatt; alább csak a tartós tanulságok.

### Reggel — Phase 4 bootstrap

`just cluster-bootstrap cluster` végigfutott (7 release deployed), 8 bootstrap-időszaki javítás (`f67cb9db7..c1fc548d3` commit-tartomány), `FluxInstance Ready`, `ClusterSecretStore onepassword-connect Valid/Ready`. Egy session-záró blokker maradt: a `snapshot-controller` HR `failed-install` ragadt, ami minden PVC-igénylő appot Pending-ben tartott.

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

A Phase 8 foundation (mise + just + setup.sh + 6 mod) reggel kész volt, de a `Taskfile.yml` és `.taskfiles/` lemaradt mert pár domain nem volt teljes lefedettséggel migrálva. Lefedettségi audit után **minden releváns task** (`so:`, `hm:openwrt*`, `vs:status`, `vs:list`, `vs:maintenance`, `vs:last-backups`, `ku:mount`, `fx:reconcile`, `fx:verify`, `hm:openmediavault` SSH-flow) migrálva a Just oldalra. Eldobva mint elavult: `an:*` (K3s Ansible — Talos váltja), `hm:proxmox` + `hm:k8s-host` + `hm:all` (Proxmox-K3s láncolat), `tf:*` (már a `cloudflare`/`ovh` mod-okban), `fx:install` (`just cluster-bootstrap cluster` váltja), `fx:hr-restart` (= `just k8s restart-failed-hrs`), `fx:nodes/pods/list` (use `kubectl get` / `flux get` directly), `ku:kubeconfig` (Talos-éra: `just talos get-kubeconfig`), `pc:*` (a `pre-commit` CLI-t direkt használjuk), `es:sync` (= `just k8s sync-es` / `sync-all es`).

**Új modulok**: `provision/sops/mod.just` (4 recipe: re-encrypt, fix-mac, encrypt-file, decrypt-file) és `provision/openwrt/mod.just` (3 recipe: maintain, reinstall-packages, upgrade — eredeti ~400 sor bash interaktív sysupgrade flow Just `[script]` recipe-ekbe csomagolva). **`provision/openmediavault/mod.just`** kapott egy `update-host` recipe-et (SSH-alapú `omv-upgrade` + applyChanges + NAS share remount — az aktuális, pre-Phase-10 omv-maintenance út). **`kubernetes/mod.just`** kibővítve: `rs-status`, `kopia-maintenance`, `last-backups` (Python window overview), `mount-pvc`, `flux-reconcile`, `flux-check`; a meglevő `list-snapshots` rich tabular formátumra cserélve.

**Root `.justfile`** kapott `mod sops "provision/sops"` és `mod openwrt "provision/openwrt"` import-okat — most 8 mod-csoport listázódik (`k8s`, `cluster-bootstrap`, `talos`, `omv`, `cloudflare`, `ovh`, `sops`, `openwrt`). **Root `CLAUDE.md`** „Taskfile And Renovate Model" szekciója „Just And Renovate Model"-re cserélve, „Current Repository Shape" `.taskfiles/` hivatkozása `.justfile + **/mod.just`-ra. **Törölve**: `Taskfile.yml` + a teljes `.taskfiles/` (9 mappa, 13 fájl).

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

**Verifikáció**: a Plex pod uptime **változatlan** (5h28m a deploy előtt és után — SSA no-op, byte-identical HR spec). 8 érintett KS mind Ready=True az új revision-on (`b6101942`). HR labels megerősítve: `backrest` és `qbittorrent-p2pblocklist` HR-ek új `kustomize.toolkit.fluxcd.io/name` címkével. OVH Kopia repo binding változatlan (a `${APP}` substitution értékek nem cserélődtek), K3s-éra adatok továbbra is elérhetők. `just volsync restore-into` recipe doc-stringjéből a `ks=restic-gui` override-említés eltávolítva — `just volsync restore-into default backrest 0` mostantól override nélkül megy. A teljes `ks` paraméter is törölve (`6d0f390ef`), mert 15.a után nincs olyan app, ami divergens KS-szel jönne.

**Restore recipe egységesítés**: a régi két recipe (`restore` bootstrap-RD-triggerrel + `restore-into` Direct copyMethod-tal) ugyanazon szemantikai irányba mutatott, de fragmentáltan. Cseréltük egyetlen `restore` recipe-re a `kubernetes/volsync/mod.just`-ban — `wipe + Direct-restore` flow: suspend Flux/HR → scale 0 → apply egy `<app>-wipe` Job (Alpine, root, `find /data -mindepth 1 -delete`) → apply ad-hoc `<app>-manual` RD `copyMethod: Direct` + `previous: N`-szel → wait → cleanup → resume Flux + reconcile HR + wait pod ready. **A wipe-step a lényeg**: a Kopia Direct mover egyébként csak felülírja a snapshot-ban szereplő fájlokat, a leftover-fájlokat NEM törli — silent corruption-kockázat, ha a live PVC tartalma eltért a snapshot-ban szereplő fájl-szettől. A wipe előzetes futtatása garantálja, hogy a restore eredménye **pontosan** a választott snapshot. A megszüntetett `wait-rd` recipe sehol nem volt callolva ezután. `.claude/CLAUDE.md` Cluster Access Policy frissítve (csak `just volsync restore` szerepel a mutating-listán); `.claude/skills/volsync/references/operations.md` "Unified Restore Flow" szekcióval kicserélve a régi két-recipe-leírást.

### Hajnal — K3s system-upgrade-controller orphan cleanup

15.a follow-up cluster-szintű takarítás: a Lens-ben két failed `apply-server-on-cp0-k8s-...` Job jelent meg a `system-upgrade` ns-ben. Diagnose: Phase 6 záró cleanup a `system-upgrade/system-upgrade-controller/` repo-subtree-t törölte, de a `system-upgrade` namespace-t **szándékosan megőrizte** `kustomize.toolkit.fluxcd.io/prune: disabled` címkével — feltehetően egy későbbi Tuppr migráció elővételezéseként. A `prune: disabled` viszont megakadályozta, hogy a Flux a HR-t és kapcsolódó child resource-okat is elvigye, így a Rancher `system-upgrade-controller` HR + Deployment + Plan-ek (`agent` completed, `server` fail-loop a `rancher/k3s-upgrade` image-zsel egy Talos host-on) az új clusterre is átöröklődtek. A `server` Plan minden ~30 másodpercben új Job-ot indított, ami `K3S_PID=` üres → `fatal 'No K3s pids found'` → exit 1-gyel halt meg. Ugyanaz a "Flux Kustomization suspend → repo subtree delete" örökség-minta, mint a Phase 6 esti `metallb` orphan tanulság (sor 37) — csak itt a `prune: disabled` címke explicit, nem suspend implicit.

A teljes K3s-éra Rancher SUC stack lebontva:

**Cluster cleanup**: `kubectl delete plan -n system-upgrade --all` → `delete hr system-upgrade-controller` (cascade helm-uninstall) → maradék Job + Pod cleanup → `delete ocirepository` → `delete crd plans.upgrade.cattle.io` → `delete ns system-upgrade`.

**Repo cleanup 1** (`25c290a5e`): `kubernetes/apps/system-upgrade/` mappa törlése, `kubernetes/apps/kustomization.yaml`-ből a `./system-upgrade` resource-referencia kivétele, `kubernetes/talos/machineconfig.yaml.j2`-ből a `kubernetesTalosAPIAccess` blokk **teljes törlése** (az egyetlen `allowedKubernetesNamespaces` entry-je a `system-upgrade` volt — Tuppr telepítésekor a Tuppr-specifikus ns-szel visszakerül).

**Repo cleanup 2** (`582ddda8e`): `provision/kubernetes/` teljes mappa törlése — K3s-specifikus Ansible plane (`xanmanning.k3s` role, Debian host-prep playbook-ok, Calico CNI template), nincs Talos-applicable része. `.claude/skills/provision-kubernetes/` skill törlése (a workflow-i a most törölt Ansible plane-t és a már törölt `.taskfiles/` wrapperokat hivatkozták). Root `CLAUDE.md` "Current Repository Shape" + `provision/CLAUDE.md` "Structure" / "Subtree Guides" / "Validation skill links" frissítése a túlélő `cloudflare/`, `ovh/`, `openmediavault/` (most még csak `mod.just`, Phase 10 hozza az Ansible-t) listára.

**Tuppr döntés — alapos felmérés után NEM telepítjük**: a README "Cél állapot" táblázat sora ("system-upgrade-controller → Tuppr (bjw-s minta)") elejtve.

Tuppr forráskód-szintű felmérés (`internal/controller/talosupgrade/jobs.go` + `internal/controller/kubernetesupgrade/jobs.go`) megerősítette:
- **`KubernetesUpgrade` CR**: Job indít a Tuppr ns-ében, ami `talosctl upgrade-k8s --endpoints=<ctrl-ip> --to=<ver>` parancsot futtat. NINCS drain, NINCS reboot. Single-node-on **működik**, csak a kube-apiserver static-pod rövid restart-blip-jét okozza.
- **`TalosUpgrade` CR**: Job indít `nodeAffinity: NotIn(<targetNode>)` selectorral. `placement: soft` (default) → single-node-on a Job mégis a saját node-ra esik (preferred-only), drain elindul, controller pod meghal a drain alatt → upgrade megreked. `placement: hard` → Job soha nem schedule-ödik → CR Pending-ben marad. Single-node-on **architecturálisan instabil**, semmi módon nem ad új értéket a `just talos upgrade-node` manuális parancshoz képest.

3 referencia repó (bjw-s-labs/home-ops, onedr0p/home-ops, buroa/k8s-gitops) **mind multi-node** és teljes `TalosUpgrade + KubernetesUpgrade` páros — single-node Tuppr deployment nincs az ökoszisztémában.

Tényleges single-node ROI: csak a `KubernetesUpgrade` ér valamit (~6-12 patch/év × ~30 sec parancs = évi 3-6 perc megtakarítás), Talos node-upgrade-et továbbra is `just talos upgrade-node`-tal kell csinálni. Plusz a Tuppr telepítése egy új subsystem-et, security surface-t (`kubernetesTalosAPIAccess` + `os:admin` SA token), és Renovate-zajt visz be — a megtakarítás nem indokolja.

A `just talos upgrade-k8s` recipe inkonzisztencia kijavítva: korábban kötelező pozicionális `version` arg-ot vett, most a `mise.toml`-ban definiált `KUBERNETES_VERSION` env-változót olvassa (`upgrade-node`-mintájára). Tehát a Renovate-driven K8s upgrade folyamat:
1. Renovate PR a `mise.toml KUBERNETES_VERSION`-re (jelenleg `kubernetes/kubernetes` GH release datasource)
2. Review + merge
3. `just talos upgrade-k8s` (paraméter nélkül, single source of truth a `mise.toml`)

Ugyanúgy a Talos-upgrade flow:
1. Renovate PR a `mise.toml TALOS_VERSION`-re (`custom.talos-factory` datasource, Phase 9 talosFactory.json5)
2. Review + merge
3. `just talos upgrade-node` (paraméter nélkül, env-vál)

Akkor érdemes visszanyúlni Tuppr-hoz, ha valaha multi-node Talos jönne.

**Tanulság — `prune: disabled` névtér öröksége**: a Phase 6 esti orphan-tanulság ugyanúgy aktuális marad: ha egy ns-t `prune: disabled`-szel hagyunk meg "tervezett későbbi migrációhoz", **a benne lévő HR + child resources tovább reconcile-olnak** akár hetekig, és későbbi cluster-bootstrapokba is átöröklődnek. Helyesebb a lebontás idejére hagyni a ns-t és a tartalmat is törölni, és a későbbi migráció időpontjában frissen telepíteni — ahogy itt is most a Tuppr-döntéssel végül "ne telepítsük" lett a kimenet.

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

**Talos-quirk reminder élesedett**: a Cilium HelmRelease upgrade hook drain-elte a node-ot (`Ready,SchedulingDisabled`), a friss `envoy-external` és `cloudflare-tunnel` pod-ok FailedScheduling-ba kerültek (`0/1 nodes are available: 1 node(s) were unschedulable`). Mitigáció: `kubectl uncordon k8s-cp0` — a STATUS.md "Talos reboot reminder" pontja most már a **Cilium HR upgrade-re is érvényes**.

**Phase 15.c plan-update** (`52c607120`): a per-app CNP audit szekció kibővítve a **B-csapdával** (opt-out label custom egress nélkül = csak DNS marad, pod indul fail). Két szint formalizálva: **Tier I** (ingress-only, no label, baseline egress — paperless minta) és **Tier II** (ingress + strict egress + opt-out label — pl. magas threat-modelű app-okhoz). A 4f4b76eec-ből megmaradó CNP-k Tier I-re átírva ma — a 3 érintett CNP közül `cloudflare-tunnel` még nem volt egyszerűsítve, az a következő session-re marad (15.c-ben).

### Phase 15.b — Doc + AI-guide refresh

Cutover-előtti repo-doksi és AI-guide tisztítás. 10-fázisú audit + szerkesztés sorozat: a `talos`-éra realitás (Talos + Cilium LB-IPAM + L2 announce + Envoy Gateway + Flux Operator + FluxInstance + always-on VolSync + Just + mise + bjw-s lapos layout + CCNP baseline) átvezetve a `docs/*.md` + `CLAUDE.md` lánc + `.claude/skills/*` + `.claude/settings.json` + `README.md` rétegeken.

**1. Pure deletes (8 doc + 1 skill)**: K3s-éra vagy duplikált / vendor-cseré doc-ok törölve — `docs/{backup-kubernetes-host,host-configuration,ingress-basic-auth,k3s-readme,k3s-system-upgrade,kubernetes-readme,postgresql-backup-readme,sops-readme}.md`. A `.claude/skills/taskfiles/` skill (4 fájl) is törölve — funkcióját az új `just` skill veszi át.

**2. Új `just` skill**: `.claude/skills/just/{SKILL.md,references/{catalog,authoring,validation}.md}`. Frontmatter: "Work on the Just-based operational entry points…". Catalog felsorolja a 9 mod-csoportot (`k8s`, `cluster-bootstrap`, `talos`, `volsync`, `omv`, `cloudflare`, `ovh`, `sops`, `openwrt`) és a kritikus per-csoport recipe-eket (`cluster-bootstrap cluster`, `k8s flux-reconcile/flux-check/sync-hr/sync-ks/sync-es/sync/list-failed-hrs/restart-failed-hrs/apply-ks/delete-ks`, `talos {apply-node,upgrade-node,upgrade-k8s,get-kubeconfig,gen-secrets,bootstrap,reset-*,reboot-node,shutdown-node,diag,status}`, `volsync {restore,restore-into,snapshot,snapshot-all,list-snapshots,rs-status,wait-rd,last-backups,state,kopia-maintenance}`, `{cloudflare,ovh} {init|plan|apply|unlock}`, `sops {re-encrypt,fix-mac,encrypt-file,decrypt-file}`, `omv {install,check,update,update-host}`, `openwrt {maintain,upgrade,reinstall-packages}`). Authoring: positional-only argumentumok, `[group:]` label, env a `.mise.toml`-ból. Validation: `just --list`, `--dry-run`, pre-commit CLI (nincs Just wrapper).

**3. `docs/flux-readme.md` REWRITE + `docs/networking-readme.md` REWRITE**:
- `flux-readme.md`: klasszikus `flux install/bootstrap` install rész lecserélve Flux Operator + `FluxInstance` topológiára (`kubernetes/apps/flux-system/flux-{operator,instance}/` + `kubernetes/flux/cluster/ks.yaml`). Cheatsheet rész `just k8s flux-reconcile/flux-check/sync-hr/sync-ks/sync-es/sync`, `list-failed-hrs/restart-failed-hrs`, `apply-ks/delete-ks`, `browse-pvc/mount-pvc/node-shell/prune-pods/view-secret`. Direkt `flux get/events/logs` upstream CLI említve.
- `networking-readme.md`: MetalLB → Cilium L2 announcement / LB-IPAM. `envoy-internal` `lbipam.cilium.io/ips` annotáció, `CiliumLoadBalancerIPPool/default` (`192.168.1.15-25`), `LB_ENVOY_INTERNAL_IP` / `LB_K8S_GATEWAY_IP` `cluster-settings.yaml`-ből. Új szekció: cluster-wide CCNP baseline (`allow-cluster-egress` + `allow-dns-egress` L7 DNS proxy) + per-app Tier I / Tier II döntésmodell utalás Phase 15.c-re.

**4. `kubernetes/bootstrap/readme.md` REWRITE**: prerequisite-okból Task drop, `mise install` add (`.mise.toml` pinneli a `talosctl`/`kubectl`/`helm`/`helmfile`/`flux2`/`just`/`sops`/`age`/`1password-cli`/`minijinja`/`yq`/`jq`/`gum`-ot). A 9-stage bootstrap chain részletesen: `talos → kubernetes → kubeconfig(node) → wait → namespaces → resources → crds → apps → kubeconfig(cilium)`. Recovery utal a STATUS.md Phase 6 `helm uninstall + flux reconcile hr --force` és `safe-upgrades VAP` mintákra.

**5. CLAUDE.md lánc (8 fájl)**:
- `.claude/CLAUDE.md` Cluster Access Policy `task fx:*` / `task vs:*` → read-only `just k8s` / `just volsync`; deny lista a cluster-mutáló `just cluster-bootstrap cluster`, `just talos {get-kubeconfig,apply-node,upgrade-*,reset-*,reboot-node}`, `just volsync {restore,restore-into}`-re bővítve.
- `.claude/skills/CLAUDE.md` line 66 `task pc:run` → `pre-commit run --all-files`.
- `kubernetes/CLAUDE.md` line 36 `task fx:reconcile` → `just k8s flux-reconcile`.
- `kubernetes/apps/external-secrets/CLAUDE.md` line 44 "Taskfile bootstrap flow" → `kubernetes/bootstrap/resources.yaml.j2 + op inject`.
- `kubernetes/apps/networking/CLAUDE.md` 3× MetalLB → Cilium L2 announcement + LB-IPAM. `metallb/` subtree említés törölve (mappa Phase 6-ban már törölve volt). `envoy-external` ClusterIP-only Service felemlítve a CF Tunnel architektúra fényében.
- `kubernetes/apps/volsync-system/CLAUDE.md` `vs:` task → `just volsync` recept-nevek; always-on RD pattern (`<app>-bootstrap` + `dataSourceRef`, `IfNotPresent` SSA label fresh-fetch kockázat) magyarázat hozzáadva.
- `provision/CLAUDE.md` + `provision/cloudflare/CLAUDE.md` + `provision/ovh/CLAUDE.md` Task wrapper konvenció → `.justfile` / `mod.just`; `task tf:*` → `just cloudflare/ovh init/plan/apply/unlock`; `taskfiles` skill ref → `just` skill ref.

**6. `.claude/skills/*` refresh (10 skill)**:
- `cloudflare-terraform/SKILL.md` frontmatter "task-backed Terraform workflows" → `just cloudflare` recipes; `references/validation.md` 3× `task tf:*:cloudflare` → `just cloudflare init/plan/apply/unlock`.
- `external-secrets/references/validation.md` `task es:sync` → `just k8s sync-es <ns> <name>`.
- `flux-gitops/SKILL.md` + `references/operations.md` (rewrite) + `references/validation.md`: 7× `task fx:*` → `just k8s flux-{reconcile,check}/sync-{hr,ks,es}/sync`; `flux/config/` → `flux/cluster/`; `task fx:install` → `just cluster-bootstrap cluster`.
- `k8s-workloads/references/{validation,publication-and-jobs}.md`: `Taskfile.yml` → `.justfile + mod.just`; Traefik warning sor törölve (user: "minden nginx és traefik szar mehet").
- `networking-platform/SKILL.md` + `references/topology.md` rewrite: frontmatter MetalLB → "Cilium LB-IPAM / L2 announcement, cluster-wide CiliumNetworkPolicy baseline"; topology szekció új CCNP baseline blokk Phase 15.c utalással.
- `sops-secrets/references/{validation,bootstrap-and-app-secrets}.md`: `task fx:install` → `just cluster-bootstrap cluster` + `resources.yaml.j2` magyarázat; 4× `task so:*` → `just sops re-encrypt/fix-mac/encrypt-file/decrypt-file`.
- `sre/references/investigation.md` `vs:` task → `just volsync` recipes.
- `versions-renovate/references/annotations.md` `v1.35.2+k3s1` deprecated példa → `.mise.toml` `TALOS_VERSION` / `KUBERNETES_VERSION` annotációk + `.renovate/{customManagers,talosFactory}.json5` jelenlegi struktúra.
- `references/role-bundles.md` Implementer bundle: `taskfiles` → `just`.
- `volsync/SKILL.md` `taskfiles` skill-ref → `just` skill-ref.

**7. `.claude/settings.json` permissions refresh**:
- 11 `task fx:*` + `task vs:*` allow → 4 `just`-recept: `just k8s flux-check`, `just volsync list-snapshots/rs-status/last-backups`. A többi `task fx:nodes/pods/kustomizations/...` allow drop — a meglévő `kubectl get:*` és `flux get:*` permission már lefedi őket.
- 2 régi deny (`task fx:install`, `task ku:kubeconfig`) → 15 deny: `just cluster-bootstrap cluster`, `just talos {get-kubeconfig,apply-node,upgrade-node,upgrade-k8s,reset-node,reboot-node,shutdown-node,bootstrap,gen-secrets}`, `just volsync {restore,restore-into,state}`, `just k8s {restart-failed-hrs,delete-ks}`. A 4 `kubectl get/describe secret(s)` deny változatlan.

**8. Kód-comment cleanup**:
- `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml:153` comment `"single-node K3s"` → `"single-node Talos"`. A disabled component lista (kubeApiServer/kubeControllerManager/kubeScheduler/kubeProxy/kubeEtcd/coreDns/kubeDns) változatlan (bjw-s parity, single-node Talos kontextusban is helyes).
- `kubernetes/apps/default/homepage/app/helmrelease.yaml` 9 sor commented-out `traefik.io` / `traefik.ingress.kubernetes.io/router.middlewares` rész teljes törlése.
- `.gitignore:16` `xanmanning.k3s*` orphan ignore-bejegyzés törölve (`provision/kubernetes/` Ansible plane már Phase 6-ban törölve volt, `582ddda8e`). Az általános Ansible role ignore-ok (`mrlesmithjr.zfs`, `geerlingguy.docker`, `geerlingguy.pip`) megmaradnak — esetlegesen használhatók a Phase 10 OMV Ansible-ben.
- Root `CLAUDE.md:79` `"Envoy Gateway with Gateway API, not Traefik"` → `"Envoy Gateway with Gateway API"` (negation törlése — Traefik már nem létezett a `talos` branchen).

**9. Root `README.md` rewrite**: Phase 9 — user-facing human doc, angolul (nyelvi átírást a 15.b nem érintette).
- Hardware section: K3s VM sor törölve; HP ProDesk 600 G6 DM (Talos, NVMe PC801 OS + PC711 data, 64GB) hozzáadva; Lenovo M93p szerepe "Proxmox + OMV VM (transitional)"-re átírva azzal a megjegyzéssel, hogy Phase 10-ben bare-metal OMV váltja.
- Tooling lead bővítve: Talos Linux, Helmfile, Just, mise.
- GitOps Workflow / Flux: FluxInstance pattern leírás (`kubernetes/flux/cluster/` + `cluster-vars` + `cluster-apps`); `just cluster-bootstrap cluster` reference.
- Repository Structure: új mappák (`components`, `talos`, `volsync` + `provision/{sops,openwrt}`).
- Core Components: új **Operating System & Cluster** szekció (Talos Linux + Cilium + Flux Operator + FluxInstance). Networking szekciónál Calico/MetalLB cseréje Cilium-ra. Storage: VolSync always-on RD + resticprofile/Backrest emphasis. Configuration Management: SOPS Age + mise + Just + minijinja-cli + `op inject`.
- Ingress Model szekció finomítva: `envoy-external` ClusterIP-only, `envoy-internal` Cilium L2-announced VIP.
- Renovate szekció `.github/renovate.json5` → `.renovaterc.json5` + `.renovate/` fragmens-szerkezetre.

**10. Verifikáció**:
- `git grep` ellenőrzés `K3s|MetalLB|Traefik|nginx|Calico|tigera|Taskfile|.taskfiles|task fx:/vs:/...` mintákra a `docs/migration/` historikus narratívát kivéve: csak 3 szándékos historizáló ref maradt (`README.md:9` "K3s → Talos migration" transitional note, `.claude/skills/just/SKILL.md:10` "no Task / Taskfile is present", `.claude/skills/just/references/catalog.md:32` "Replaces the historical task fx:install flow").
- `pre-commit run --all-files` zöld (yamllint, trim trailing whitespace, fix end of files, mixed line ending, CRLF/Tabs/smartquote remover, Kubernetes secret check, hardcoded secret detect mind PASS).

**Phase 15.b exit criteria teljesítve**: a `docs/*.md` + `CLAUDE.md` lánc + `.claude/skills/*` réteg konzisztens a `talos`-éra realitással. A `taskfiles` skill helyét az új `just` skill veszi át. A `provision/openmediavault/CLAUDE.md` stub szándékosan Phase 10-re halasztva (user 8. döntés).

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
| 15 | Repo refactor (ks.yaml flatten + doc + AI-guide refresh) | [15](./15-repo-refactor.md) | 🟡 in-progress | **15.a + 15.b kész** (15.a: 4 split + 2 KS rename; 15.b: 8 doc delete + új `just` skill + flux/networking-readme rewrite + bootstrap readme rewrite + CLAUDE.md lánc + 10 skill refresh + settings.json permissions + code comments + README.md); 15.c per-app CNP threat-model audit hátra |

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

- HP ProDesk 600 G6 DM fent, Talos `v1.13.2` v1.36.1 K8s, `k8s-cp0 Ready` (bond0 aktív kernel device, eno1 slave).
- 1Password `HomeOps/talos` + `HomeOps/homelab-age-key` (`privateKey`) + `HomeOps/1password-connect-kubernetes` (`credentials` + `token`) item-ek verifikálva.
- Cilium runtime + L2 announce egyedül felelős az LB IP-kért (CiliumLoadBalancerIPPool `.15–.25`, default policy `^bond[0-9]+$`).
- ClusterSecretStore `onepassword-connect` Valid/Ready.
- ⚠️ **Talos reboot reminder**: bármely Talos reboot/apply-node után `kubectl get nodes` → ha `SchedulingDisabled`, `kubectl uncordon k8s-cp0`. A bond0-reboot drain után nem uncordon-ol automatikusan, ez minden Pod Pending-jét okozza.
- ⚠️ **`safe-upgrades` VAP kihagyott bootstrap pattern**: a `00-crds.yaml` `yq` szűrője csak `CustomResourceDefinition`-t enged át, így a Gateway API `ValidatingAdmissionPolicy` és `ValidatingAdmissionPolicyBinding` nem jut be a bootstrap apply-ba. Egyezik a bjw-s/onedr0p/buroa mintával. Ha az első Helm install újra timeout-ol certgen Job-on: `kubectl delete vap/vapb safe-upgrades.gateway.networking.k8s.io` + `flux reconcile hr envoy-gateway --force`.

## Frissítési konvenció

- Minden fázis végén frissül a Fázis tracker tábla.
- A `README.md` „Status — élő tracker" szekciója és ez a doc szinkronban marad — ez a részletesebb, a README-ben rövidebb pillanatkép.
- Új sub-task / blocker → ide az „Open items" alá.
- Hardcoded `${PUBLIC_DOMAIN}` érték **TILOS** session-jegyzőkönyvekben és smoke teszt példákban — placeholdert kell használni.
