# 00 — Architecture decisions

Minden architekturális döntés egy helyen, indoklással. Ez az "ADR-ek lite" — egy doc, nem külön fájlonként.

## AD-001: Talos Linux + bare metal HP-n (nem Talos VM Proxmox-on)

**Döntés:** Talos bare metalon fut a HP ProDesk 600 G6 DM-en, nem VM-ben Proxmox alatt.

**Indoklás:**
- Single-node setup → Proxmox plusz réteg nélkül egyszerűbb (egy patch-ciklus kevesebb).
- Nem terveződik melléje másik VM (router/HAOS/NAS) — a NAS marad külön M93p-n.
- 64 GB RAM bőven elég K8s-re, nincs Proxmox-pooling előny.
- Az `i7-10700T` 8 mag/16 thread komolyabb CPU, mint amit Talos VM workload kihasználhatna — kár pluszrétegre költeni.
- Talos immutable model természetes illeszkedés a meglévő Flux GitOps mintához.

**Tradeoff:**
- Nincs VM snapshot rollback — etcd snapshot + VolSync restore a recovery módja.
- Recovery kézi USB-t igényel (nincs IPMI/iLO ezen a hardveren).
- Ha jövőre OPNsense/HAOS VM kellene, refaktor: vagy KubeVirt, vagy migráció Proxmox-ra.

**Kapcsolódó:** [01-hardware-and-network.md](./01-hardware-and-network.md), [02-talos-bootstrap.md](./02-talos-bootstrap.md)

## AD-002: M93p marad bare metal OMV — fizikai szeparáció megőrzése

**Döntés:** A jelenlegi M93p Proxmox+OMV VM setupot bare metal OMV-re cseréljük, **nem** vonjuk össze a HP-val.

**Indoklás:**
- Fizikai szeparáció DR-érték — HP halálnál a NAS és a lokális backup target élve marad.
- VolSync OVH S3 backup mellett a lokális NFS mount + esetleges Kopia local repo érték.
- Az M93p ~12 W idle — éves többletköltség ~8 000 Ft, ami fedezi a DR-érték.
- A Proxmox plusz réteg az M93p-n is felesleges, ha csak OMV fut benne — bare metal egyszerűbb és patch-cikluson is takarít.

**Tradeoff:**
- M93p Proxmox tear-down + bare metal OMV install **plusz cutover lépés**.
- Az USB DAS passthrough konfig kiesik (jelenleg működik, de bare metalon nincs is szükség rá — direkt USB hozzáférés).

**Kapcsolódó:** [10-omv-ansible.md](./10-omv-ansible.md), [14-post-cutover.md](./14-post-cutover.md)

## AD-003: Cilium CNI kube-proxy replacement módban

**Döntés:** Calico → Cilium, kube-proxy disabled (Talos-szinten), Cilium veszi át.

**Indoklás:**
- Három referencia repó egyezően Cilium-ot használ.
- Performance: eBPF datapath, netkit, BBR — minőségi ugrás Calico-hoz képest single-node-on is mérhető.
- Cilium L2 announcement kiváltja a MetalLB-t — eggyel kevesebb komponens.
- Hubble UI observability single-node-on debug-érték.
- Gateway API native support (jövő-állókká teszi az ingresst).

**Tradeoff:**
- Friss install (nincs in-place migráció Calico→Cilium) — de a big-bang cutover modellel ez nem hátrány.
- Komplexebb konfig, mint Calico — több értéket kell érteni (BPF masq, DSR, hostfirewall).

**Kapcsolódó:** [03-cilium-cni.md](./03-cilium-cni.md)

## AD-004: L2 announcement BGP helyett

**Döntés:** Cilium L2 announcement policy, NEM BGP control plane.

**Indoklás:**
- Single-node setup-ban a BGP overkill — nincs ECMP, nincs failover másik node-ra.
- Az OpenWRT router BGP-t tudna, de plusz konfig router-side és cluster-side, érdemi haszon nélkül.
- L2 announcement ARP/GARP broadcast — single 1 GbE NIC-en pontosan illik.
- onedr0p repo L2 announcement-et használ → kész minta van.

**Tradeoff:**
- Ha későbbi multi-node setup jön (worker node-ok), L2 announcement nem skálázódik szépen (csak egy node "owner"-je egy VIP-nek). Akkor BGP-re válthatunk — nem nagy refaktor.

**Kapcsolódó:** [03-cilium-cni.md](./03-cilium-cni.md)

## AD-005: Flux Operator + FluxInstance, klasszikus Flux helyett

**Döntés:** A `flux bootstrap` parancsot lecseréljük Flux Operator-ra (controlplane.io), a cluster állapotát FluxInstance CRD vezérli.

**Indoklás:**
- Mindhárom referencia ezt használja.
- Deklaratív Flux maga is — a controllerek frissítése a FluxInstance YAML-en keresztül megy.
- Cluster-szintű default patch-ek (CRD createReplace, retry, timeout) egyetlen helyen.
- Helmfile bootstrap-ban természetes lépés (`flux-operator` + `flux-instance` release).

**Tradeoff:**
- Klasszikus `flux install` workflow-tól eltér — kis tanulási görbe.
- Flux Operator önmaga is karban tartandó (Helm release).

**Kapcsolódó:** [05-flux-operator.md](./05-flux-operator.md)

## AD-006: Helmfile-alapú bootstrap, Ansible K3s install helyett

**Döntés:** A jelenlegi `provision/kubernetes` (Ansible + xanmanning.k3s role) **megszűnik**. Az új cluster bootstrap egy `kubernetes/bootstrap/helmfile.d/` chain-en keresztül megy.

**Indoklás:**
- Talos saját maga telepedik (talosctl apply-config + bootstrap), nincs szükség host-prep Ansible-re.
- A "post-Talos" Kubernetes setup (Cilium, CoreDNS, cert-manager, ESO, Flux) deklaratív helmfile-lal egyszerűbb és reprodukálhatóbb.
- A helmfile `needs:` lánc determinisztikus install sorrendet ad — Cilium → CoreDNS → cert-manager → ESO → onepassword-connect → Flux.
- CRD-k out-of-band install (`00-crds.yaml`) megszünteti a `dependsOn` pókhálót Flux oldalon.

**Tradeoff:**
- Az Ansible tudás egy része "elveszik" — de ez a K3s-specifikus rész, ami most már nem releváns.
- Helmfile + minijinja + op-inject tooling tanulása.

**Kapcsolódó:** [04-bootstrap-helmfile.md](./04-bootstrap-helmfile.md)

## AD-007: Just (justfile) Task helyett, redesign-elt parancsfelülettel

**Döntés:** Teljes Task → Just migráció, nincs együttélés. A jelenlegi `.taskfiles/` törlődik, helyébe `justfile` + `kubernetes/mod.just` + más mod fájlok jönnek.

**Indoklás:**
- A három referencia mind Just-ot használ — `mod` group struktúrával jól szervezett.
- A jelenlegi `an:/es:/fx:/hm:/ku:/pc:/so:/tf:/vs:` task namespace-ek fele értelmét veszti (Ansible K3s task-ok eltűnnek).
- Just script-blokkok strukturáltabbak (`#!/usr/bin/env bash` shebang), mint Task `cmds:` listák.
- `gum` integráció konzisztens logger output-hoz.

**Tradeoff:**
- Teljes parancsfelület újraépítés (~30+ recipe).
- Új tool a stack-ben (Just), de `mise`-on keresztül pinneit verzió.

**Kapcsolódó:** [08-just-migration.md](./08-just-migration.md)

## AD-008: mise tool manager bevezetése

**Döntés:** Tool verziókat `.mise.toml`-ban pinneljük. Tool-ok: `talosctl`, `helmfile`, `kubectl`, `flux`, `just`, `op`, `minijinja-cli`, `yq`, `gum`, `sops`, `age`, `pre-commit`, `terraform`.

**Indoklás:**
- A három referencia mindegyike mise-t használ.
- Renovate kompatibilis — `.mise.toml`-t a renovate `regexManagers` követni tudja.
- Lokális reprodukálhatóság: bárki a repón egységes tool-verziókat fut.

**Tradeoff:**
- mise install önmaga is plusz lépés (egyszeri).

**Kapcsolódó:** [08-just-migration.md](./08-just-migration.md)

## AD-009: Bootstrap secrets `op inject`, runtime secrets ExternalSecret + SOPS

**Döntés:** Hibrid secret pattern, három forrással.

- **Bootstrap időben** (`resources.yaml.j2` minijinja + `op inject`): három Secret jön létre lokálisan generált manifest-ből, 1Password lookup-pal:
  - `onepassword-connect-credentials-secret` (Connect server creds)
  - `onepassword-connect-vault-secret` (Connect vault token)
  - **`sops-age`** (age private key SOPS dekripcióhoz)
- **Runtime — Flux reconcile**:
  - **`cluster-secrets.sops.yaml`** SOPS-szal titkosítva a git-ben, a Flux `cluster-vars` Kustomization dekódolja a `sops-age` Secret-tel reconcile időben. Tartalmaz: `PUBLIC_DOMAIN`, `SECRET_QBITTORRENT_PW` — substituteFrom-mal használtak.
  - **`homepage/secret.sops.yaml`** szintén SOPS-szal titkosítva (nagy YAML, könnyű szerkesztés `sops edit`-tel).
  - **App-szintű ExternalSecret-ek** ESO + 1Password Connect ClusterSecretStore-on át (mealie, paperless, plex, resticprofile stb.) — változatlan a jelenlegihez.

**Indoklás:**
- A 1Password Connect maga is fut a clusterben → chicken-and-egg, ezért a Connect init creds-et `op inject`-tel kell biztosítani.
- A SOPS pattern **megőrzött** a cluster-secrets-re és a Homepage config-ra (utóbbinál `sops edit` UX miatt).
- App-szintű runtime secret-ek 1Password ExternalSecret-en mennek.

**Tradeoff:**
- Két különböző secret bevitel mód a bootstrap időben (op-inject + Flux SOPS reconcile) — elfogadható komplexitás.
- `op` CLI lokális használathoz kell (bárhonnan, ahonnan bootstrap-elünk).
- A `cluster-secrets` esetleges 1Password ESO migrációja külön post-cutover feladat (phase 2).

**Kapcsolódó:** [04-bootstrap-helmfile.md](./04-bootstrap-helmfile.md), [05-flux-operator.md](./05-flux-operator.md), [07-components-and-shared.md](./07-components-and-shared.md)

## AD-010: Talos config jinja2 templating, NEM talhelper

**Döntés:** A Talos `machineconfig.yaml.j2` minijinja2 template-tel készül, `op inject`-tel injektált secret értékekkel. NEM talhelper.

**Indoklás:**
- A három referencia mind jinja2 + op inject mintát használ, talhelper-t nem.
- Talhelper plusz tool a stack-ben, fél-deklaratív, az `op inject` mintával nem keveredik tisztán.
- Egyetlen node esetén a jinja2 template + node-onkénti patch overkill, de a minta jövő-álló (1 node-ra is, többre is skálázódik).

**Tradeoff:**
- Talhelper néha kényelmesebb (deklaratív cluster config). Ezt elengedjük a konzisztencia kedvéért.

**Kapcsolódó:** [02-talos-bootstrap.md](./02-talos-bootstrap.md)

## AD-011: Storage változatlan — democratic-csi local-hostpath

**Döntés:** A jelenlegi `democratic-csi-local-hostpath` storage class változatlanul marad az új clusteren is.

**Indoklás:**
- Single-node setup-on a Longhorn replikáció értelmetlen (max 1 replica), Rook-Ceph antipattern.
- A democratic-csi local-hostpath driver bevett, működik Talos `extraMounts`-szal.
- A meglévő VolSync + Kopia + OVH S3 backup pipeline storage-osztály-agnosztikus.

**Tradeoff:**
- Single point of disk failure → a backup pipeline kritikus (de ez már most is így van).

**Kapcsolódó:** [02-talos-bootstrap.md](./02-talos-bootstrap.md), [06-repo-restructure.md](./06-repo-restructure.md)

## AD-012: Két NVMe szétosztás — gyorsabb az OS+etcd-re, lassabb a PVC-re

**Döntés:** A két SK hynix NVMe közül a **P41 (P801, "Gen4")** lesz a **Talos OS install disk** (ami egyben az etcd és EPHEMERAL volume helye), a **P31 (P711, "Gen3")** a democratic-csi data disk (`/var/mnt/extra-disk`).

**Indoklás:**
- A HP ProDesk 600 G6 DM **mindkét M.2 slotja PCIe Gen3** — a P41 Gen4-es előnye sequential throughput-ban NEM realizálódik.
- **De**: az etcd fsync latency érzékeny a random write IOPS-ra és a kontroller minőségére. Az **etcd a cluster kritikus írási útvonala** — a lassú etcd disk az egész cluster reconcile-t lassítja, és heavy load esetén "request timeout" hibákat okoz.
- A P41 (Aries kontroller, 1.3M IOPS random write) **érdemibb előnyt ad az etcd workloadnak**, mint a P31-nek a media PVC-ket.
- A democratic-csi PVC-k (Plex DB, Paperless, Sonarr config) **kisebb write throughput-ot** generálnak átlagosan, mint amit a P31 (570K IOPS, 1 GB DRAM cache) kiszolgál.
- Talos `EPHEMERAL` volume (container image-ek, runtime state) szintén az OS disken él — a gyorsabb image pull + container start előny.

**Tradeoff:**
- A sebességkülönbség gyakorlatban marginális (Gen3 fal mindkettőn), de a kontroller-szintű különbség (Aries vs Cepheus) etcd-re mérhető.
- Ha a jövőben heavy write PVC kell (pl. PG database 1000+ TPS), érdemes átgondolni a P41-re átmigrálni a data disket — most ez nem szükséges.

**Kapcsolódó:** [01-hardware-and-network.md](./01-hardware-and-network.md), [02-talos-bootstrap.md](./02-talos-bootstrap.md)

## AD-013: Single-node, nincs VIP

**Döntés:** A Talos `controlPlane.endpoint` közvetlenül a node IP-jére mutat (`https://192.168.1.11:6443`), nincs VIP.

**Indoklás:**
- Egyetlen control plane → VIP overhead haszon nélkül.
- Talos beépített VIP (Equinix-féle) csak 2+ node esetén ad értéket.
- Future-proofing nem indok: ha worker node-ot adunk hozzá, a control plane akkor is single. Ha 3 control plane-re skálázunk, akkor VIP-et utólag is be tudunk dobni egy `machineconfig` patch-csel.

**Tradeoff:**
- Ha a node IP-je változik (hálózati reorganizáció), kubeconfig + Talos config update kell. Statikus IP a routeren mitigálja.

**Kapcsolódó:** [01-hardware-and-network.md](./01-hardware-and-network.md)

## AD-014: Cluster név = `main`

**Döntés:** Az új cluster neve `main`, egyezve a referenciák többségével.

**Indoklás:**
- bjw-s és onedr0p is `main` cluster nevet használ.
- A `home-ops` a repo neve, nem a cluster nevének része.
- Multi-cluster jövő (dev/staging) kompatibilis nevezés.

**Tradeoff:** semmilyen.

**Kapcsolódó:** [02-talos-bootstrap.md](./02-talos-bootstrap.md)

## AD-015: Pod CIDR `10.244.0.0/16`, service CIDR `10.245.0.0/16`

**Döntés:** Pod CIDR `10.244.0.0/16`, service CIDR `10.245.0.0/16`. Mindkettő különbözik a jelenlegitől (`10.42`/`10.43`).

**Indoklás:**
- Az új cluster IP terve nem ütközhet a régivel **cutover ablakban**, amikor mindkettő él (router-en mindkettő látható).
- bjw-s és buroa is `10.244.0.0/16` pod CIDR-t használ — közmegegyezés.
- A service CIDR-t `10.245`-re emeljük, hogy `pod=244, svc=245` mnemonikus legyen.

**Tradeoff:**
- A `cluster-settings.yaml` `CLUSTER_POD_CIDR` és `CLUSTER_SVC_CIDR` változókat módosítani kell — kicsi munka.

**Kapcsolódó:** [02-talos-bootstrap.md](./02-talos-bootstrap.md), [03-cilium-cni.md](./03-cilium-cni.md)

## AD-016: Cluster LB IP range — `192.168.1.15-25`

**Döntés:** Az új cluster L2 announcement IP poolja `192.168.1.15-25` (11 IP). A jelenlegi MetalLB szolgáltatás IP-i (`.18`, `.19`, `.20`) ebbe a tartományba esnek, így változatlanok maradnak.

**Indoklás:**
- A teszt során a régi K3s clustert **lekapcsoljuk** — IP-konfliktus nincs.
- DNS rekordok és router/dnsmasq config-ok **érintetlenül maradnak** (`LB_K8S_GATEWAY_IP=192.168.1.19` stb.).
- Ha a teszt nem sikerül: HP cluster powerdown → K3s VM újra-indítás → IP-k automatikusan visszaállnak.

**Tradeoff:**
- A két cluster nem futhat egyszerre LAN-on (IP-ütközés). Ezt a "shut down K3s during testing" workflow megoldja.
- Cloudflare tunnel **NEM tud** mindkét clusterhez egyszerre csatlakozni a tunnel-token egyetlen pod-ja miatt — de mivel a régi cluster shutdown, ez nem probléma.

**Kapcsolódó:** [01-hardware-and-network.md](./01-hardware-and-network.md), [03-cilium-cni.md](./03-cilium-cni.md), [12-cutover-runbook.md](./12-cutover-runbook.md)

## AD-017: Big-bang cutover, "shut down K3s during testing"

**Döntés:** Big-bang cutover, az új cluster tesztelése alatt a régi K3s VM **lekapcsolva**. NEM párhuzamosan futnak.

**Indoklás:**
- A két cluster LAN-on egyszerre nem futhat (IP-pool ütközés, Cloudflare tunnel single connector).
- "Shut down K3s during testing" workflow: snapshot → K3s VM shutdown → új cluster boot → restore + validation → ha OK: marad; ha nem: HP powerdown + K3s power on.
- A VolSync restore single-app szinten történik, de mind a 17 PVC párhuzamosan trigger-elhető.

**Tradeoff:**
- A NAS NFS share változatlan (M93p marad fenn), de az app-ok 1-3 órán át nem elérhetők a switchover alatt.
- Rollback = HP powerdown + K3s VM power on (~5-10 perc).

**Kapcsolódó:** [12-cutover-runbook.md](./12-cutover-runbook.md), [13-rollback-and-decom.md](./13-rollback-and-decom.md)

## AD-018: VolSync OVH S3 round-trip minden PVC-re

**Döntés:** Adatmigráció a meglévő VolSync OVH S3 backup ÚJ Kopia repó-pointtel. Régi cluster utolsó snapshot → új cluster ReplicationDestination restore.

**Indoklás:**
- A Kopia repó ugyanaz marad — OVH bucket változatlan, password változatlan, csak `purpose`/`hostname` változik clusterről clusterre.
- A `kubernetes/components/volsync/replicationdestination.yaml` template már megvan a repóban (jelenleg ki van kommentelve "új cluster recreate-hez").
- App-level export (pl. Plex DB dump) **csak ott szükséges**, ahol az adat nem PVC-n él, vagy a PVC tartalom nem önmagában konzisztens (pl. SQLite WAL nyitva).

**Tradeoff:**
- 17 PVC restore = ~17 RD job. Idő: PVC-mérettől függ, de OVH ↔ HP letöltés 1 GbE-n cca. 100 MB/s.
- Network forgalom a snapshotok mennyiségétől függ (Plex DB nagy lehet).

**Kapcsolódó:** [11-data-migration.md](./11-data-migration.md), [07-components-and-shared.md](./07-components-and-shared.md)

## AD-019: System upgrade — Tuppr (bjw-s minta)

**Döntés:** A jelenlegi `system-upgrade-controller` lecserélődik [bjw-s tuppr](https://github.com/bjw-s-labs/home-ops/tree/main/kubernetes/apps/system-upgrade/tuppr) mintára.

**Indoklás:**
- Tuppr Talos-natív: a Talos `MachineConfigPatch` és Talos API-n keresztül kezeli a node frissítést.
- A `system-upgrade-controller` SUSE-féle, jellemzően K3s-hez tervezve, Talos-szal nem natív (lehet Talos-szal is, de tuppr jobb illeszkedés).

**Tradeoff:**
- A jelenlegi SUC `Plan` resource-ok nem migrálnak át 1:1 — új Tuppr `Plan` resource-okat kell írni.

**Kapcsolódó:** [06-repo-restructure.md](./06-repo-restructure.md)

## AD-020: Renovate cloud-based, refaktorált config

**Döntés:** A Renovate továbbra is cloud-based (Mend Renovate vagy GitHub App), NEM self-hosted. A config refaktorálódik bjw-s/onedr0p mintára: `.renovaterc.json5` a root-on, `.renovate/*.json5` fragmensek.

**Indoklás:**
- A self-hosted Renovate plusz cluster workload, semmi értéke single-developer projektnek.
- Cloud Renovate ingyenes a public repokra, megbízható.
- A fragmensek (`autoMerge.json5`, `groupPackages.json5`, `packageRules.json5`) jobban szervezett, mint egy 500 soros monolith.

**Tradeoff:**
- Cloud Renovate ütemezés nem testre szabható ennyire (de a `schedule` kulcsszó a fragmensekben elég).

**Kapcsolódó:** [09-renovate-rewrite.md](./09-renovate-rewrite.md)

## AD-022: Flux root — `cluster-vars` + `cluster-apps` Kustomization split

**Döntés:** A `kubernetes/flux/cluster/ks.yaml` **két Kustomization-t** tartalmaz:
1. `cluster-vars` — a `./kubernetes/flux/vars/` mappát reconcile-álja, SOPS dekripcióval (a `sops-age` Secret-tel). Létrehozza a `cluster-settings` ConfigMap-et és a `cluster-secrets` Secret-et.
2. `cluster-apps` — a `./kubernetes/apps/` tree-t reconcile-álja, `dependsOn: cluster-vars`, és a `substituteFrom: [cluster-settings, cluster-secrets]` használja a fent létrehozott resource-okat.

**Indoklás:**
- A `cluster-apps` `substituteFrom` forrásai (ConfigMap + Secret) csak akkor használhatók, ha mind a kettő létezik a clusterben. A `dependsOn` garantálja a sorrendet.
- A `cluster-vars` `decryption: { provider: sops, secretRef: { name: sops-age } }`-tel dekódolja a `cluster-secrets.sops.yaml`-t.
- A jelenlegi setup (`kubernetes/flux/config/cluster.yaml` egyetlen Kustomization-nel és kézi `flux/vars/` apply-jal a bootstrap task-ban) **megszűnik** — Flux maga kezeli mindkettőt GitOps-natívan.

**Tradeoff:**
- Az egyetlen cluster-apps Kustomization helyett kettőt kell debug-olni — minimális komplexitás.
- A `cluster-vars` Kustomization **NEM része** a `./kubernetes/apps/` tree-nek (sibling, nem child), így a refactor nem kavarja össze az apps tree szervezést.

**Kapcsolódó:** [05-flux-operator.md](./05-flux-operator.md), [04-bootstrap-helmfile.md](./04-bootstrap-helmfile.md)

## AD-021: Megőrzött komponensek — változatlan elemek listája

A migráció ELLENÉRE az alábbi komponensek **változatlanul** átkerülnek:
- **Envoy Gateway** + dual-stack (`envoy-external` + `envoy-internal`)
- **k8s-gateway** (split-DNS LAN-on)
- **cert-manager** + OVH DNS-01 webhook
- **external-secrets** + 1Password Connect ClusterSecretStore (`onepassword`)
- **VolSync + Kopia + OVH S3** backup pipeline
- **resticprofile / Backrest** file-szintű backup plane
- **kube-prometheus-stack + Grafana + Speedtest exporter** observability
- **Cloudflare tunnel + ExternalDNS** ingress külső irány
- **Provision: Cloudflare Terraform + OVH Terraform** változatlan (Terraform Cloud workspaces)

**Indoklás:** Ezek mind működő, érett komponensek — nincs ok cserélni őket.

**Kapcsolódó:** [06-repo-restructure.md](./06-repo-restructure.md)

## Döntés-mátrix átfogó

| # | Téma | Most | Új | Indok |
|---|---|---|---|---|
| 001 | OS+platform | K3s+Debian VM | Talos bare metal | Single-node egyszerűség |
| 002 | NAS | OMV VM | OMV bare metal | DR-szeparáció |
| 003 | CNI | Calico | Cilium | eBPF, kube-proxy replacement |
| 004 | LB announcement | MetalLB | Cilium L2 | Egy komponens kevesebb |
| 005 | GitOps | flux bootstrap | Flux Operator | Deklaratív Flux maga |
| 006 | Bootstrap | Ansible K3s | Helmfile chain | Talos saját install |
| 007 | Task runner | Task | Just | Référence konvenció |
| 008 | Tool versioning | nincs | mise | Reprodukálható env |
| 009 | Secrets | SOPS+ExternalSecrets | + op-inject `sops-age` + `op-connect-creds` bootstrap | Chicken-and-egg fix |
| 010 | Talos config | n/a | jinja2 + op inject | Egyetlen templating layer |
| 011 | Storage | democratic-csi | democratic-csi | Változatlan |
| 012 | NVMe szétosztás | n/a | P41 → OS+etcd, P31 → data PVC | etcd fsync prioritás |
| 013 | VIP | n/a | nincs | Single-node |
| 014 | Cluster név | nincs | `main` | Référence konvenció |
| 015 | Pod CIDR | 10.42/16 | 10.244/16 | Cutover izoláció |
| 016 | LB IP pool | 192.168.1.18-20 | 192.168.1.15-25 | Bővítési mozgástér + meglévő VIP-ek megőrizve |
| 017 | Cutover modell | n/a | Big-bang | DNS egyszerűség |
| 018 | Adatmigráció | n/a | VolSync OVH round-trip | Eszköz adott |
| 019 | System upgrade | system-upgrade-controller | Tuppr | Talos-natív |
| 020 | Renovate | cloud, monolith config | cloud, fragmensek | Karbantarthatóság |
| 021 | Megőrzött | — | Envoy, k8s-gateway, ESO stb. | Érett komponensek |
| 022 | Flux root struktúra | egyetlen `cluster-apps` Kustomization | `cluster-vars` + `cluster-apps` (dependsOn) | GitOps-natív `flux/vars/` reconcile |

Minden döntés a megfelelő fázis-docban részletezve.
