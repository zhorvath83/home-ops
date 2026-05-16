# 15 — Repo refactor: ks.yaml flatten + doc + AI-guide refresh

## Cél

Cutover-előtti repo-tisztítás két szorosan kapcsolódó alfázisban:

- **15.a** — a `default` ns 4 multi-KS `ks.yaml`-jét kilapítjuk a bjw-s/onedr0p/buroa `apps/<ns>/<app>/` mintára (minden Kustomization önálló top-level mappát kap). Egy KS rename (`restic-gui` → `backrest`) ezzel együtt full bjw-s parity-t ad: a `<app> == KS == HR` egyezőség minden réteggben teljesül.
- **15.b** — a migráció eredménye (K3s → Talos, Task → Just, Calico → Cilium, MetalLB → Cilium LB-IPAM, Traefik → Envoy Gateway, bjw-s layout, always-on VolSync) átvezetése a `docs/*.md`, a `CLAUDE.md` lánc és a `.claude/skills/*` audit/átírás során. A `main` branch a hosszú távú forrás; ha a doksi nem tükrözi az új repo-modellt, minden új AI-session félreértésre épül.

A 15.a → 15.b sorrend kötött: a doc-átírás a lapos szerkezetre hivatkozhat, nem kell „flatten előtt / után" verziókat fenntartani.

## Inputs

- `talos` branch HEAD a Phase 1–8 + 11 ✅ állapotában, ingress stack stabil, CNP migráció kész, Task → Just teljes lezárás megvolt.
- `kubernetes/components/volsync/` `${APP}` substitution-réteg változatlan — a flatten **nem** érinti az RS/RD/PVC/ES nevezéktanát, csak a Flux Kustomization és a hozzá tartozó mappa nevét.
- `git grep` audit megerősítette: a 4 érintett KS-név (`restic-gui`, `paperless-gpt`, `plex-trakt-sync`, `qbittorrent-upgrade-p2pblocklist`) egyikére sem mutat `dependsOn:` referencia más KS-ből, tehát a rename nem lánc-tör.

## 15.a — App-szintű ks.yaml flatten

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

### 15.a verifikáció

- `flux get ks -n flux-system | grep -E 'paperless-gpt|plex-trakt-sync|qbittorrent-upgrade-p2pblocklist|backrest'` → mind a 4 új KS Ready=True.
- `flux get ks -n flux-system | grep restic-gui` → üres (törölve).
- `kubectl get hr -n default backrest` → még mindig megvan, új label-lel.
- `kubectl get replicationdestination -n default backrest-bootstrap` → változatlan.
- `just volsync restore-into default backrest 0` — `ks=` override nélkül **működnie kell** (a recipe `ks` default-ja `app`, ami most `backrest` és a KS neve is `backrest`).

## 15.b — Doc + AI-guide refresh

### Hatáskör

**`docs/*.md` (13 fájl)** — várhatóan többségben elavult vagy törlendő:

- **Törölni** (K3s-éra, Talos-ra nincs külön doc — a `02-talos-bootstrap.md` lefedi): `docs/k3s-readme.md`, `docs/k3s-system-upgrade.md`
- **Átírni** (Talos + bjw-s + Cilium + Envoy realityre): `docs/networking-readme.md` (Traefik+MetalLB → Envoy Gateway+Cilium), `docs/kubernetes-readme.md`, `docs/flux-readme.md` (Flux Operator + FluxInstance pattern), `docs/host-configuration.md` (Talos machineconfig, `provision/kubernetes/` Ansible kivonás), `docs/ingress-basic-auth.md` (Envoy Gateway SecurityPolicy mintára)
- **Ellenőrzés + kis frissítések**: `docs/helm-readme.md`, `docs/cert-manager-readme.md`, `docs/sops-readme.md`, `docs/pluto-readme.md`, `docs/backup-kubernetes-host.md` (Talos host-szintű backup szükséges-e), `docs/postgresql-backup-readme.md` (CNPG még él-e a cluster-ben)

**Path-szintű `CLAUDE.md`-k (11 fájl, worktree-másolatok kihagyva)**:

- `CLAUDE.md` (root) — már Phase 8-ban átírva Just-ra, de a 15.a után a `Current Repository Shape` és példák frissítendők
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

### Hol feltételezünk `app == KS == HR` egyezőséget — a 15.a után automatikusan stimmel

Audit (`git grep` + recipe-átfutás) eredménye, kivetítve a 15.a utáni állapotra:

- **`kubernetes/components/volsync/*.yaml` `${APP}` substitution**: a `replicationsource.yaml` (`name: ${APP}`, `sourcePVC: ${VOLSYNC_CLAIM:=${APP}}`, `repository: ${APP}-volsync-secret`), `replicationdestination.yaml` (`name: ${APP}-bootstrap`, `repository: ${APP}-volsync-secret`, `sourceIdentity.sourceName: ${APP}`), `pvc.yaml` (`name: ${VOLSYNC_CLAIM:=${APP}}`, `dataSourceRef.name: ${APP}-bootstrap`), `externalsecret.yaml` (`name: ${APP}-volsync`, `target.name: ${APP}-volsync-secret`). Az `APP` érték a `ks.yaml` `postBuild.substitute`-jából jön — ma a `restic-gui` KS-ben `APP: backrest`, ezért a generált RS/RD/PVC/ES nevek `backrest`-ek, **csak a Flux Kustomization neve és `commonMetadata` címkéje (`restic-gui`) divergál**. A 15.a után a KS is `backrest` lesz, minden réteg azonos nevet kap.
- **`just volsync restore-into ns app [previous] [ks]`**: a `ks` paraméter default `app`, de a backrest-hez ma `ks=restic-gui` override kell. 15.a után az override **fölöslegessé válik**, lehet törölni a recipe doc-stringjéből és a STATUS.md példáiból.
- **`just volsync restore app`**: az `${app}-bootstrap` RD-t patcheli — a név a `${APP}` substitutionból jön, a flatten után is `backrest-bootstrap` marad, **változás nincs**.
- **`just volsync list-snapshots / rs-status / snapshot / wait-rd`**: ezek nyersen pozicionálisan veszik a RS/RD nevét, **nem feltételeznek KS-egyezőséget** — változás nincs.
- **`dependsOn` lánc**: `git grep -E "name:\s+(restic-gui|paperless-gpt|plex-trakt-sync|qbittorrent-upgrade-p2pblocklist)" -- 'kubernetes/**/ks.yaml'` jelenleg **nem ad találatot a `dependsOn` blokkban**. A rename nem lánc-tör.
- **`kubernetes/apps/default/kustomization.yaml`** — 4 új `./<app>/ks.yaml` referencia.
- **Path-szintű `CLAUDE.md`-k és `.claude/skills/*`** — a 15.b-ben átírjuk mind a `paperless/gpt`, `plex/trakt-sync`, `qbittorrent/upgrade-p2pblocklist`, `resticprofile/gui` hivatkozást a lapos szerkezetre.

### Megközelítés

1. **Olvasási fázis** (~1h): a 13 `docs/*.md` átolvasása, megjelölés (delete / rewrite / minor edit / keep).
2. **CLAUDE.md lánc audit** (~1-1.5h): top-down, a root → kubernetes → apps sorrendben, a „State To Assume Today" + „Repo-Wide Anti-Patterns" szakaszok aktualizálása.
3. **Skill refresh** (~1-2h): a 12 skill `SKILL.md` + `references/*.md` átfutása; `taskfiles/` skill sorsa Phase 8 lezárása után már most is „törlendő vagy átírandó".
4. **README.md** (~30 min, opcionális ASK után): a Hungarian human-facing változat.

### 15.b verifikáció

- `git grep -lE 'Taskfile|\.taskfiles'` repo-szerte → üres (a `docs/migration/00-14` és `STATUS.md` történelmi említései elfogadhatók).
- `git grep -lE 'metallb\.io/loadBalancerIPs|traefik|k3s-system-upgrade'` → üres.
- A root `CLAUDE.md` „Current Repository Shape" + „State To Assume Today" frissítve a Talos-éra realitásra.
- Az érintett 12 skill leírása konzisztens a `.claude/skills/CLAUDE.md` szabályaival.

## Exit criteria

- **15.a**: `flux get ks -A` ad 4 új top-level KS-t (paperless-gpt, plex-trakt-sync, qbittorrent-upgrade-p2pblocklist, backrest), `restic-gui` KS törölve, `kubectl get hr -A` mind Ready, RS/RD/PVC nevezéktan változatlan.
- **15.b**: minden K3s/Task/MetalLB/Traefik/Calico referencia eltűnt a `docs/*.md` + `CLAUDE.md` + `.claude/skills/*` fájlokból (kivéve a `docs/migration/` történelmi narratíváját), és a doc-réteg a `talos` ág realitását tükrözi.

## Becsült munka

- 15.a: ~30-45 perc
- 15.b: ~4-6 óra, parallel-izálható (skill ↔ CLAUDE.md egymástól függetlenül)
- Összesen: ~5-7 óra, célszerű Phase 9 (Renovate rewrite) után, Phase 12 (cutover) előtt
