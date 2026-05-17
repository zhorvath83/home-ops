# 16 — Repo refactor: ks.yaml flatten + doc + AI-guide refresh

## Cél

Cutover-előtti repo-tisztítás két szorosan kapcsolódó alfázisban:

- **16.a** — a `default` ns 4 multi-KS `ks.yaml`-jét kilapítjuk a bjw-s/onedr0p/buroa `apps/<ns>/<app>/` mintára (minden Kustomization önálló top-level mappát kap). Egy KS rename (`restic-gui` → `backrest`) ezzel együtt full bjw-s parity-t ad: a `<app> == KS == HR` egyezőség minden réteggben teljesül.
- **16.b** — a migráció eredménye (K3s → Talos, Task → Just, Calico → Cilium, MetalLB → Cilium LB-IPAM, Traefik → Envoy Gateway, bjw-s layout, always-on VolSync) átvezetése a `docs/*.md`, a `CLAUDE.md` lánc és a `.claude/skills/*` audit/átírás során. A `main` branch a hosszú távú forrás; ha a doksi nem tükrözi az új repo-modellt, minden új AI-session félreértésre épül.

A 16.a → 16.b sorrend kötött: a doc-átírás a lapos szerkezetre hivatkozhat, nem kell „flatten előtt / után" verziókat fenntartani.

## Inputs

- `talos` branch HEAD a Phase 1–8 + 11 ✅ állapotában, ingress stack stabil, CNP migráció kész, Task → Just teljes lezárás megvolt.
- `kubernetes/components/volsync/` `${APP}` substitution-réteg változatlan — a flatten **nem** érinti az RS/RD/PVC/ES nevezéktanát, csak a Flux Kustomization és a hozzá tartozó mappa nevét.
- `git grep` audit megerősítette: a 4 érintett KS-név (`restic-gui`, `paperless-gpt`, `plex-trakt-sync`, `qbittorrent-upgrade-p2pblocklist`) egyikére sem mutat `dependsOn:` referencia más KS-ből, tehát a rename nem lánc-tör.

## 16.a — App-szintű ks.yaml flatten

### Hatáskör (4 split + 1 KS rename)

| Jelenlegi | Cél | KS név |
|---|---|---|
| `default/paperless/{app,gpt}/` | `default/paperless/app/` + `default/paperless-gpt/app/` | változatlan (`paperless`, `paperless-gpt`) |
| `default/plex/{app,trakt-sync}/` | `default/plex/app/` + `default/plex-trakt-sync/app/` | változatlan (`plex`, `plex-trakt-sync`) |
| `default/qbittorrent/{app,upgrade-p2pblocklist}/` | `default/qbittorrent/app/` + `default/qbittorrent-upgrade-p2pblocklist/app/` | változatlan (`qbittorrent`, `qbittorrent-upgrade-p2pblocklist`) |
| `default/resticprofile/{app,gui}/` (KS `restic-gui`) | `default/resticprofile/app/` + `default/backrest/app/` | **rename**: `restic-gui` → `backrest` |

### Mit NEM érintünk

A platform-szintű multi-KS staging mintákat (mindegyik a bjw-s/onedr0p/buroa-ban is így van, `dependsOn` sorrenddel):

- `networking/envoy-gateway/{certificate,app,config}` — cert → operator → Gateway CRDs
- `cert-manager/{cert-manager,issuers}` — issuer-ek függnek a CRD-któl
- `kube-system/cilium/{app,config}` — `CiliumLoadBalancerIPPool` a Helm-install utánra kell
- `volsync-system/volsync/{app,maintenance}` — `KopiaMaintenance` saját ütemezésű
- `flux-system/addons/{alerts,webhooks}` — különböző reconcile-cadence

### Lépések (per app)

1. Új top-level mappa: `mv kubernetes/apps/default/<parent>/<child>/ kubernetes/apps/default/<new-app>/app/` (ahol `<new-app>` = paperless-gpt / plex-trakt-sync / qbittorrent-upgrade-p2pblocklist / backrest).
2. Új `ks.yaml` a `<new-app>/` alatt: a régi `<parent>/ks.yaml` második Kustomization-blokkját kiemelni, a `path:` mezőt az új mappára átírni, `metadata.name` ugyanaz (a backrest esetén `restic-gui` → `backrest`).
3. Régi `<parent>/ks.yaml`-ban csak a parent Kustomization marad (a `paperless` / `plex` / `qbittorrent` / `resticprofile` blokk).
4. `kubernetes/apps/default/kustomization.yaml`: új `./<new-app>/ks.yaml` resource hozzáadása.
5. `git status` + helyi `kustomize build` ellenőrzés.

### Kockázat — `restic-gui` → `backrest` KS rename

A 3 path-only split (paperless-gpt, plex-trakt-sync, qbittorrent-upgrade-p2pblocklist) **alacsony kockázatú**: a KS neve változatlan, Flux a `kustomize.toolkit.fluxcd.io/name` label alapján észleli a path-váltást, nincs ownership-transfer és nincs prune.

A `restic-gui` → `backrest` rename viszont valós prune-kockázattal jár: a régi `restic-gui` KS pruneja megpróbálná törölni a HR-t és a hozzá tartozó volsync-resource-okat a régi `kustomize.toolkit.fluxcd.io/name: restic-gui` label alapján.

**Mitigáció — biztonságos kéthozós átállás**:

1. A régi `restic-gui` Kustomization-t `flux suspend kustomization restic-gui -n flux-system`-szel suspended-be tenni — ez megelőzi az automatikus pruneot.
2. Új `backrest` KS-t bekommit-olni a repo-ba (a régi `restic-gui` KS-t és mappát NEM törölve még).
3. `flux reconcile ks backrest -n flux-system` → a `backrest` KS apply-olja a HR-t és a volsync resource-okat új `kustomize.toolkit.fluxcd.io/name: backrest` labellel (SSA conflict-resolution kezeli az ownership-transfert).
4. `kubectl get hr backrest -o jsonpath='{.metadata.labels}'` → ellenőrizni hogy az új label van rajta.
5. `kubectl delete kustomization restic-gui -n flux-system` → a régi KS objekt törlődik, **prune nem fut le** mert suspended (de a `kubectl delete` magát az erőforrást nem prune-olja, csak a manifestet veszi le).
6. Régi `restic-gui` mappát és ks.yaml-t kommit-olni törölve a repo-ba.

### 16.a verifikáció

- `flux get ks -n flux-system | grep -E 'paperless-gpt|plex-trakt-sync|qbittorrent-upgrade-p2pblocklist|backrest'` → mind a 4 új KS Ready=True.
- `flux get ks -n flux-system | grep restic-gui` → üres (törölve).
- `kubectl get hr -n default backrest` → még mindig megvan, új label-lel.
- `kubectl get replicationdestination -n default backrest-bootstrap` → változatlan.
- `just volsync restore-into default backrest 0` — `ks=` override nélkül **működnie kell** (a recipe `ks` default-ja `app`, ami most `backrest` és a KS neve is `backrest`).

## 16.b — Doc + AI-guide refresh

### Hatáskör

**`docs/*.md` (13 fájl)** — várhatóan többségben elavult vagy törlendő:

- **Törölni** (K3s-éra, Talos-ra nincs külön doc — a `02-talos-bootstrap.md` lefedi): `docs/k3s-readme.md`, `docs/k3s-system-upgrade.md`
- **Átírni** (Talos + bjw-s + Cilium + Envoy realityre): `docs/networking-readme.md` (Traefik+MetalLB → Envoy Gateway+Cilium), `docs/kubernetes-readme.md`, `docs/flux-readme.md` (Flux Operator + FluxInstance pattern), `docs/host-configuration.md` (Talos machineconfig, `provision/kubernetes/` Ansible kivonás), `docs/ingress-basic-auth.md` (Envoy Gateway SecurityPolicy mintára)
- **Ellenőrzés + kis frissítések**: `docs/helm-readme.md`, `docs/cert-manager-readme.md`, `docs/sops-readme.md`, `docs/pluto-readme.md`, `docs/backup-kubernetes-host.md` (Talos host-szintű backup szükséges-e), `docs/postgresql-backup-readme.md` (CNPG még él-e a cluster-ben)

**Path-szintű `CLAUDE.md`-k (11 fájl, worktree-másolatok kihagyva)**:

- `CLAUDE.md` (root) — már Phase 8-ban átírva Just-ra, de a 16.a után a `Current Repository Shape` és példák frissítendők
- `kubernetes/CLAUDE.md`, `kubernetes/apps/{default,external-secrets,networking,volsync-system}/CLAUDE.md` — bjw-s lapos layout, új namespace, always-on VolSync minta
- `provision/CLAUDE.md`, `provision/kubernetes/CLAUDE.md`, `provision/cloudflare/CLAUDE.md`, `provision/ovh/CLAUDE.md` — Talos Ansible scope szűkítés (csak host-prep marad), Cloudflare/OVH változatlan
- `.claude/CLAUDE.md` — Cluster Access Policy a `task fx:*` / `task vs:*` helyett Just receptekre (`just k8s ...`, `just volsync ...`)

**`.claude/skills/*/SKILL.md` + referenciák (12 skill)**:

- `taskfiles/` skill — **törlendő vagy átírandó „just" skillé**; a workflow-rétegre a `just` lett a belépés
- `versions-renovate/` skill — Phase 9 után átírás az új `.renovaterc.json5` + `.renovate/` fragmens-struktúrára
- `provision-kubernetes/` skill — Talos-fókusz, K3s referenciák kivétele
- `networking-platform/` skill — Envoy Gateway + Cilium LB-IPAM minta megerősítése, MetalLB referenciák ki; CiliumNetworkPolicy migráció után stateful CNP minta hozzáadása
- `flux-gitops/` skill — Flux Operator + FluxInstance pattern + cluster-vars/cluster-apps aktualizálás
- `external-secrets/`, `sops-secrets/`, `volsync/`, `cloudflare-terraform/` — kisebb frissítések (always-on RD minta a `volsync/` skill-be, `restore-into` recipe doc)
- `sre/`, `architecture-review/`, `security-review/`, `k8s-workloads/` — sample-ek frissítése Talos/Cilium kontextusra

**Root `README.md`** — a globális szabály szerint **csak explicit ASK után** módosítható.

### Hol feltételezünk `app == KS == HR` egyezőséget — a 16.a után automatikusan stimmel

Audit (`git grep` + recipe-átfutás) eredménye, kivetítve a 16.a utáni állapotra:

- **`kubernetes/components/volsync/*.yaml` `${APP}` substitution**: a `replicationsource.yaml` (`name: ${APP}`, `sourcePVC: ${VOLSYNC_CLAIM:=${APP}}`, `repository: ${APP}-volsync-secret`), `replicationdestination.yaml` (`name: ${APP}-bootstrap`, `repository: ${APP}-volsync-secret`, `sourceIdentity.sourceName: ${APP}`), `pvc.yaml` (`name: ${VOLSYNC_CLAIM:=${APP}}`, `dataSourceRef.name: ${APP}-bootstrap`), `externalsecret.yaml` (`name: ${APP}-volsync`, `target.name: ${APP}-volsync-secret`). Az `APP` érték a `ks.yaml` `postBuild.substitute`-jából jön — ma a `restic-gui` KS-ben `APP: backrest`, ezért a generált RS/RD/PVC/ES nevek `backrest`-ek, **csak a Flux Kustomization neve és `commonMetadata` címkéje (`restic-gui`) divergál**. A 16.a után a KS is `backrest` lesz, minden réteg azonos nevet kap.
- **`just volsync restore-into ns app [previous] [ks]`**: a `ks` paraméter default `app`, de a backrest-hez ma `ks=restic-gui` override kell. 16.a után az override **fölöslegessé válik**, lehet törölni a recipe doc-stringjéből és a STATUS.md példáiból.
- **`just volsync restore app`**: az `${app}-bootstrap` RD-t patcheli — a név a `${APP}` substitutionból jön, a flatten után is `backrest-bootstrap` marad, **változás nincs**.
- **`just volsync list-snapshots / rs-status / snapshot / wait-rd`**: ezek nyersen pozicionálisan veszik a RS/RD nevét, **nem feltételeznek KS-egyezőséget** — változás nincs.
- **`dependsOn` lánc**: `git grep -E "name:\s+(restic-gui|paperless-gpt|plex-trakt-sync|qbittorrent-upgrade-p2pblocklist)" -- 'kubernetes/**/ks.yaml'` jelenleg **nem ad találatot a `dependsOn` blokkban**. A rename nem lánc-tör.
- **`kubernetes/apps/default/kustomization.yaml`** — 4 új `./<app>/ks.yaml` referencia.
- **Path-szintű `CLAUDE.md`-k és `.claude/skills/*`** — a 16.b-ben átírjuk mind a `paperless/gpt`, `plex/trakt-sync`, `qbittorrent/upgrade-p2pblocklist`, `resticprofile/gui` hivatkozást a lapos szerkezetre.

### Megközelítés

1. **Olvasási fázis** (~1h): a 13 `docs/*.md` átolvasása, megjelölés (delete / rewrite / minor edit / keep).
2. **CLAUDE.md lánc audit** (~1-1.5h): top-down, a root → kubernetes → apps sorrendben, a „State To Assume Today" + „Repo-Wide Anti-Patterns" szakaszok aktualizálása.
3. **Skill refresh** (~1-2h): a 12 skill `SKILL.md` + `references/*.md` átfutása; `taskfiles/` skill sorsa Phase 8 lezárása után már most is „törlendő vagy átírandó".
4. **README.md** (~30 min, opcionális ASK után): a Hungarian human-facing változat.

### 16.b verifikáció

- `git grep -lE 'Taskfile|\.taskfiles'` repo-szerte → üres (a `docs/migration/00-14` és `STATUS.md` történelmi említései elfogadhatók).
- `git grep -lE 'metallb\.io/loadBalancerIPs|traefik|k3s-system-upgrade'` → üres.
- A root `CLAUDE.md` „Current Repository Shape" + „State To Assume Today" frissítve a Talos-éra realitásra.
- Az érintett 12 skill leírása konzisztens a `.claude/skills/CLAUDE.md` szabályaival.

## 16.c — Per-app CiliumNetworkPolicy threat-model audit

A `4f4b76eec` commit (CNP migration) tanulsága: a per-app default-deny minden poddal mindenre overengineering single-tenant single-node home-lab-on, és valós konnektivitási regressziót okozott (UDP CT, stateful reply bizonytalanság). A bjw-s-labs minta cluster-wide baseline CCNP-it Phase 9 utáni hotfix-ben bevezettük (`kubernetes/apps/kube-system/cilium/netpols/{allow-cluster-egress,allow-dns-egress}.yaml` + új `cilium-netpols` Flux Kustomization).

Ezt követően egy **targetált, threat-model-alapú** per-app CNP-felmérés esedékes — nem default-deny minden poddal mindenre, hanem **kifejezetten azokra az app-okra**, ahol a támadási felület és a kompromittáció utáni mozgástér konkrét védelmi nyereséget indokol.

### Cél

Listázni a futtatott alkalmazásokat, mindegyikhez besorolni egy **támadási felület + blast radius** kategóriába, és csak a magas-érték kategóriából csinálni per-app CNP-t. A többi pod a cluster-wide baseline-on marad (DNS L7 proxy + open egress + open ingress) — az ingress oldali védelmet a Gateway L7 `SecurityPolicy` adja, nem a CNP.

### Hatáskör — felmérendő alkalmazások

A `kubernetes/apps/` alatt élő összes app. Várható kategóriák:

| Kategória | Példa app-ok | CNP indokoltság |
|---|---|---|
| **Magas támadási felület + magas blast radius** | qbittorrent (torrent magnet parser, WebUI bug-history), plex (transcode-stack, plugin-system), paperless (dokumentum-upload + OCR), grafana (plugin), 3rd-party image-ek | per-app egress allowlist + opt-out label |
| **Magas-érték secret-szolgáltatók** (kompromittáció = teljes vault feltárás) | 1password-connect, external-secrets-operator | per-app **ingress** allowlist (csak engedett kliensek) |
| **Cluster-control surface** | flux-system controllers, cert-manager, snapshot-controller, reloader | per-app `kube-apiserver` egress allowlist (más pod ne tudjon ServiceAccount token-nel apiservert hívni) |
| **Egyszerű olvasói felület, kicsi felület** | homepage, echo, maintainerr, seerr | nem indokolt — baseline elég |
| **Belső utility** | k8s-gateway, external-dns | nem indokolt — baseline + Gateway-policy elég |

### Per-app CNP minta — két szint, szándékos választás

A per-app CNP-ket **két szigorúsági szintre** osztjuk. A választás threat-model-alapú, nem default. **Az opt-out label használata önmagában nem extra védelem — pontosan ellenkezőleg, custom egress nélkül törést okoz** (lásd a kockázati szekciót lent).

**Szint I — Ingress-only restrikció (bjw-s-labs paperless minta, alacsony karbantartási költség)**:

- Per-app `CiliumNetworkPolicy` csak `ingress` szekcióval, opt-out label NÉLKÜL.
- Egress oldalon a baseline `allow-cluster-egress` + `allow-dns-egress` fedez mindent — DNS L7 proxy, cluster pod-okhoz forgalom, `world` HTTPS, minden megy.
- Védelmi nyereség: a pod-on belüli kompromittáció után **kelet-nyugati lateral move-ot a támadó nem indíthat egy másik pod felé**, ami nem szerepel az ingress allowlist-en — pl. egy kompromittált `qbittorrent`-ből `paperless:8000`-re tett HTTP-kérés drop-pal megy.
- Karbantartási költség: minimális. A pod minden új egress-szükségletet automatikusan kap a baseline-ból, chart-upgrade nem tör.

**Szint II — Ingress + szigorú egress (magas threat-model, magas karbantartás)**:

- Per-app CNP `ingress` ÉS `egress` szekcióval, **plusz** `egress.home.arpa/custom-egress: ""` label a workload-on (chart `controllers.<name>.labels` vagy kustomization `commonLabels` szinten).
- A label kiveszi a pod-ot a `allow-cluster-egress`-ből; a `allow-dns-egress` továbbra is hat (minden pod-ra).
- Effektív egress = DNS L7-proxy ∪ amit a CNP explicit felsorol.
- Védelmi nyereség: a kompromittált pod **nem tud kifelé kapcsolódni** C2-re, nem tud cluster-belső scant indítani, nem éri el a `kube-apiserver`-t, nem nyúl bele másik app DB-jébe.
- Karbantartási költség: minden egress-szükségletet (DB pod label, Redis pod label, NFS host-mount, upstream FQDN-ek update-check-hez, image registry) konkrétan fel kell sorolni; chart-frissítés után újra-audit. Deploy-time fail-mode: ha hiányzik egy reális egress-szükséglet, a pod megfekszik.

### Lépések

1. **App-inventory**: `kubectl get hr -A -o name | wc -l` + `find kubernetes/apps -name ks.yaml | wc -l` egyezősége. Lista exportja egy ideiglenes `audit/app-inventory.md`-be (vagy közvetlenül a Phase 16.c session jegyzőkönyvbe).
2. **Kategorizálás**: minden app-hoz egy sor a fenti táblázat-szerű besorolással + 1-2 mondatos indok.
3. **Threat-model rögzítés**: a magas-érték kategóriákba sorolt app-okhoz konkrét fenyegetési modell (mi a támadási felület, mit nyer egy támadó a kompromittációval, milyen lateral move-okat akarhat).
4. **Szint-választás per app**: a fenti **Szint I** vagy **Szint II** explicit döntés a kategória + threat-model alapján. Default Szint I. A Szint II-re lépés csak akkor, ha a threat-model **konkrét** lateral-move / C2 / exfil vektort azonosít, amit a baseline nem fed.
5. **Per-app CNP design**: a `bjw-s-labs/kubernetes/apps/.../ciliumnetworkpolicy.yaml` mintákat referenciának véve. Szint II esetén a label és az egress szekció **ugyanabban a commit-ban** kerül be — soha nem külön (B-csapda elkerülése).
6. **Régi `4f4b76eec` CNP-k újragondolása**:
   - `cloudflare-tunnel` CNP — **törlés** (outbound-only pod, ingress restriction soha nem volt indokolt; bjw-s-labs/onedr0p/buroa egyike sem korlátozza).
   - `envoy-external`/`envoy-internal` config CNP-k — **törlés vagy egyszerűsítés**: a Gateway-rétegen `SecurityPolicy/envoy-internal-rfc1918` + `SecurityPolicy/envoy-external-cloudflare` (Phase 9 utáni hotfix) pontosabb védelmet ad L7-en, és a CNP L4 IP-szűrés redundáns.
   - `CiliumCIDRGroup/cloudflare` — **megmarad** önállóan (a `SecurityPolicy/envoy-external-cloudflare` inline tükrözi a CIDR-listát, a daily workflow mindkettőt szinkronban tartja).
7. **Verifikáció**: per-app, kompromittáció-szimuláció (`kubectl exec` a kérdéses pod-ba, próba-egress nem-engedett cél felé, megfigyelni a Hubble drop event-et). Hubble flow log példák a per-app threat-model jegyzőkönyvbe.

### Aktuális állapot a 16.c szempontjából (Phase 9 utáni hotfix)

A Phase 9 utáni hotfix-ben már bekerült:

- **`kubernetes/apps/kube-system/cilium/netpols/`** — 2 CCNP (`allow-cluster-egress` opt-out + `allow-dns-egress` L7 DNS proxy) + saját Flux `Kustomization` `cilium-netpols` `dependsOn: cilium`-mal.
- **`kubernetes/apps/default/paperless/app/ciliumnetworkpolicy.yaml`** — első per-app CNP **Szint I** szerint (csak ingress, mindkét Gateway-ből engedve TCP/8000-re). Opt-out label szándékosan **nincs**, a paperless egress oldalon a baseline-on marad.
- **`envoy-external` / `envoy-internal` CNP-k egress szekciójának törlése** — a baseline `allow-cluster-egress` + `allow-dns-egress` átveszi az egress vezérlést, az ingress allowlistek változatlanok (Cél 1 a Phase 9 utáni Hubble drop-evidence alapján).
- **`bpf.datapathMode: netkit` + `socketLB.hostNamespaceOnly: false`** Cilium helmrelease fix — a netkit + tc-LB CT-mismatch okozta SYN-ACK drop-ot megszünteti a per-app strict ingress CNP-ken (a return flow CT-bejegyzése pod-IP-pel rögzül, nem Service IP-vel).
- **`SecurityPolicy/envoy-external-cloudflare` törlés** — a `principal.clientCIDRs` CF-CIDR allowlist nem tud illeszteni a CF tunnel architektúrában (lásd a következő szekciót); helyén a CNP ingress allowlist + ClusterIP-only Service + CF tunnel mTLS adja a védelmet.

A 16.c döntési pont a paperless-re: marad Szint I, vagy felemeljük Szint II-re? A paperless threat-modelje (OCR/PDF parser CVE history Tesseract + Ghostscript + ImageMagick miatt; publikus dokumentum-upload endpoint `docs.${PUBLIC_DOMAIN}` route-on át; kompromittáció utáni érték = más app-ok adatainak elérése) **indokolja** a Szint II-t. Audit-szükségletek a Szint II-höz a paperless-re:

- Postgres pod (a paperless saját PG sidecarja vagy külön deployment-je a `default` namespace-ben, az aktuális label-ek és port `5432`)
- Redis pod (paperless task queue, port `6379`)
- NFS host-mount a `nas-export` sidecarhoz (`/backups/paperless` → host filesystem) — `toEntities: [host]` vagy konkrét NFS server IP
- Esetleges upstream FQDN-ek (paperless update check, ha aktív)
- Esetleges Tika / Gotenberg sidecar (ha külön pod-ban fut)

Ez a Szint II-felmérés a 16.c session jegyzőkönyv egyik konkrét tételes munkája.

### Tanulság — `SecurityPolicy.principal.clientCIDRs` nem fog menni az `envoy-external`-en

A Phase 9 hotfix első iterációjában bekerült egy `SecurityPolicy/envoy-external-cloudflare` 22 CF CIDR-rel `principal.clientCIDRs`-ben, defense-in-depth gondolattal a `envoy-internal-rfc1918` LAN-only allowlist analógiájára. **Élesben HTTP 403 "RBAC: access denied"-et adott minden kérésre**, ezért törölve lett.

Az ok: a Cloudflare Tunnel architektúrában a CF edge POP IP **soha nem szerepel** az envoy által látható forrás-hop-okban. A flow:

```
internet client (88.x.x.x)
  → Cloudflare edge POP
  → CF Tunnel (mutual TLS QUIC, persistent)
  → cloudflared pod (10.244.0.x, in-cluster)
  → envoy-external pod
```

A `cloudflared` agent **overwrite-olja** az `X-Forwarded-For`-t a valós kliens IP-re (88.x.x.x). A `ClientTrafficPolicy/envoy` `numTrustedHops: 1` setting alapján envoy a (1+1) = 2. entry-t keresi jobbról az XFF-ben; csak 1 entry van, így fallback-el a remote address-re (cloudflared pod IP, `10.244.0.x`), ami **nem** illeszti egyik CF CIDR-t sem → `defaultAction: Deny` érvénybe lép.

Mit ad ez a tanulság a 16.c-nek:

1. **Az `envoy-internal-rfc1918` SecurityPolicy működik** — más architektúrában, LAN kliensből közvetlenül a Cilium-L2-announce VIP-jére (`192.168.1.18`), így a `clientCIDRs` valós LAN forrás-IP-t illeszti.
2. **Az `envoy-external`-en nincs analóg lehetőség** `clientCIDRs`-szel. A védelmet **architektúra-szinten** kell garantálni:
   - ClusterIP-only Service (nincs LB IP / NodePort)
   - CNP ingress allowlist (csak `cloudflare-tunnel` pod 10080/10443-on, plusz Prometheus scrape és kubelet readiness probe)
   - CF Tunnel mTLS az edge ↔ cloudflared agent között
3. **Ha valódi L7 defense-in-depth kell az `envoy-external`-en, az ATP a megoldás**: **Cloudflare Authenticated Origin Pull** mTLS-szel autentikálja a CF edge-t az origin (envoy) felé. Cert-alapú, nem IP-alapú, így immunis az XFF-fordítási problémára. Konfiguráció:
   - Cloudflare zóna szintjén: AOP cert generálás (auto-rotating CF-issued cert vagy custom CA)
   - Envoy oldalon: `ClientTrafficPolicy.tls.verify.caCertificateRefs` a CF root CA bundle-jével, és kötelező kliens cert validation (`requireClientCertificate: true`)
   - Test: AOP cert nélküli kérés → TLS handshake fail; CF-tunnel kérés → cert validation pass

Az AOP **csak akkor érdemes** ha a fenti 3-lépéses architektúra-szintű védelmet **kiegészíteni** szeretnénk egy ténylegesen működő L7 réteggel. Single-node home-lab kontextusban marginális, de **doc-elt option** marad — a `clientCIDRs`-alapú workaround **soha nem fog működni** ebben az architektúrában.

### Kockázat

- **B-csapda — opt-out label custom egress nélkül**: a `egress.home.arpa/custom-egress: ""` label önmagában (Szint II egress szekció nélkül) a pod-ot **csak DNS-szel** engedi kifelé, mert a `allow-dns-egress` továbbra is hat, de a `allow-cluster-egress` már nem. Postgres/Redis/upstream HTTPS → DROP, app indulás közben megfekszik. Mitigáció: a label és az egress szekció **mindig ugyanabban a commit-ban** kerül be; pre-commit hook ötlet a `git grep -l 'egress.home.arpa/custom-egress' kubernetes/apps/ | xargs -I{} ...` ellenőrzéshez, hogy ha label-t lát, akkor a hozzátartozó CNP-ben legyen `egress:` szekció (ezt majd a 16.c session ötletként felvetheti).
- **Túl szigorú egress** új app-ok deploy-jánál (Szint II-n): minden új app-nak első deploy-kor verifikálni kell, hogy az egress szekciója lefedi-e a tényleges szükségleteket. Hubble drop-event monitor + chart-doc átolvasás kötelező.
- **Hubble flow-log volume**: cluster-wide DNS proxy (`allow-dns-egress`) minden DNS query-ről event-et generál. Single-node home-lab-on várhatóan elhanyagolható, de érdemes a `cilium-agent` resource-okat monitorozni az első hét után.
- **`envoy-internal`/`envoy-external` config Kustomization** törlése — a config KS `dependsOn` lánc tagja, érdemes a Flux Kustomization-listát is felülvizsgálni (lásd 8.5/8.6 alatti `restore-into <app>` follow-up).

### 16.c verifikáció

- `kubectl get ccnp` ad 2-t: `allow-cluster-egress`, `allow-dns-egress` (már most teljesül, Phase 9 utáni hotfix-ben bevezetve).
- `kubectl get cnp -A` per-app szám a 16.c döntés alapján — várhatóan 5-8 közötti, nem 3.
- `kubectl get cnp -n networking` cloudflare-tunnel CNP eltűnik.
- Minden `egress.home.arpa/custom-egress: ""` label-lel jelölt workload-hoz tartozik CNP `egress:` szekcióval (B-csapda nem fordul elő). Ellenőrzés: `kubectl get pods -A -l egress.home.arpa/custom-egress` listát ad, mindegyikre a saját namespace-ben CNP-vel `spec.egress` szekcióval.
- Hubble (`cilium hubble observe --verdict DENIED`) zéró tartós denial a normál cluster-forgalomban.
- A `audit/app-inventory.md` (vagy session jegyzőkönyv) átfutva minden app-hoz egy kategória + Szint I/II döntés + indok van.

## Exit criteria

- **16.a**: `flux get ks -A` ad 4 új top-level KS-t (paperless-gpt, plex-trakt-sync, qbittorrent-upgrade-p2pblocklist, backrest), `restic-gui` KS törölve, `kubectl get hr -A` mind Ready, RS/RD/PVC nevezéktan változatlan.
- **16.b**: minden K3s/Task/MetalLB/Traefik/Calico referencia eltűnt a `docs/*.md` + `CLAUDE.md` + `.claude/skills/*` fájlokból (kivéve a `docs/migration/` történelmi narratíváját), és a doc-réteg a `talos` ág realitását tükrözi.
- **16.c**: az app-inventory táblázat 100%-ban kitöltve, magas-érték app-okhoz konkrét per-app CNP, a `4f4b76eec` overengineered CNP-k vagy törölve vagy threat-model-alapra cserélve, Hubble denial-rate stabil.

## Becsült munka

- 16.a: ~30-45 perc
- 16.b: ~4-6 óra, parallel-izálható (skill ↔ CLAUDE.md egymástól függetlenül)
- 16.c: ~2-3 óra (inventory + kategorizálás + 5-8 per-app CNP + szimuláció)
- Összesen: ~7-10 óra, célszerű Phase 9 (Renovate rewrite) után, Phase 12 (cutover) előtt
