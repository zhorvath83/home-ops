# 08 — Task → Just migráció

## Cél

A teljes Task (`.taskfiles/` + `Taskfile.yml`) bázist lecseréljük Just-ra (`.justfile` + `mod.just` per terület). Hard cutover, nincs együttélés.

## Inputs

- Tooling: `just`, `mise`, `gum`, `jq`, `yq` lokálisan elérhető (mise telepíti).
- A `kubernetes/bootstrap/mod.just`, `kubernetes/talos/mod.just`, `kubernetes/mod.just` szerkezet a bjw-s referenciából átvéve (lásd [04](./04-bootstrap-helmfile.md) bootstrap mod.just).

## Tervezett fájl-layout

```
home-ops/
├── .justfile                                   # root — group mod-ok importja
├── .mise.toml                                  # tool verziók
├── .minijinja.toml                             # minijinja-cli config
├── kubernetes/
│   ├── mod.just                                # k8s műveletek (apply-ks, sync-hr, prune-pods, ...)
│   ├── bootstrap/
│   │   └── mod.just                            # bootstrap stages (talos, k8s, kubeconfig, apps, ...)
│   └── talos/
│       └── mod.just                            # talos műveletek (apply-node, upgrade, reset, ...)
├── provision/
│   ├── openmediavault/
│   │   └── mod.just                            # OMV Ansible entry points
│   ├── cloudflare/
│   │   └── mod.just                            # Terraform Cloudflare
│   └── ovh/
│       └── mod.just                            # Terraform OVH
```

A `.taskfiles/` mappa teljesen **törlődik**.

## Root `.justfile`

**Fájl:** `.justfile`

```just
#!/usr/bin/env -S just --justfile

set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[group: 'k8s-bootstrap']
mod k8s-bootstrap "kubernetes/bootstrap"

[group: 'k8s']
mod k8s "kubernetes"

[group: 'talos']
mod talos "kubernetes/talos"

[group: 'omv']
mod omv "provision/openmediavault"

[group: 'cloudflare']
mod cloudflare "provision/cloudflare"

[group: 'ovh']
mod ovh "provision/ovh"

[private]
[script]
default:
    just -l

[private]
[script]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[private]
[script]
template file *args:
    minijinja-cli "{{ file }}" {{ args }} | op inject
```

Két helper recipe (`log`, `template`) — az összes mod használhatja.

A `just -l` (vagy csak `just`) megmutatja a top-level mod-ok és group-ok listáját:
```
Available recipes:

  [k8s-bootstrap]
    just k8s-bootstrap <recipe>

  [k8s]
    just k8s <recipe>

  [talos]
    just talos <recipe>
  ...
```

## `.mise.toml`

**Fájl:** `.mise.toml`

```toml
[env]
JUST_UNSTABLE = "1"
KUBECONFIG = '{{config_root}}/kubeconfig'
TALOSCONFIG = '{{config_root}}/talosconfig'
MINIJINJA_CONFIG_FILE = "{{config_root}}/.minijinja.toml"

[settings]
pipx.uvx = true

[tools]
# Core CLI tooling
talosctl = "1.10.6"
kubectl = "1.36.1"
helm = "3.18.2"
helmfile = "1.1.0"
flux2 = "2.7.2"                                 # mise registry name; installed binary is `flux`
just = "1.51.0"                                 # 1.48+ required for `set lazy`
mise = "2025.1.0"

# Templating + secrets
"aqua:mitsuhiko/minijinja" = "2.13.0"          # installed binary is `minijinja-cli`
sops = "3.10.2"
age = "1.2.1"
"1password-cli" = "2.32.0"                      # op

# YAML/JSON tooling
yq = "4.47.2"
jq = "1.7.1"

# UX
gum = "0.16.0"

# Hooks
pre-commit = "4.0.1"

# Terraform
terraform = "1.10.5"

# Linters / formatters (aqua backend, bjw-s parity)
"aqua:google/yamlfmt" = "latest"
"aqua:rhysd/actionlint" = "latest"

# Python tooling (pipx backend)
"pipx:flux-local" = "latest"                    # used by `just k8s apply-ks` (render-local-ks recipe)
"pipx:ansible" = "latest"                       # OMV deploy (10-omv-ansible.md)
"pipx:ansible-core" = "latest"

[hooks]
# Enable only AFTER provision/openmediavault/requirements.yaml exists
# (created in 10-omv-ansible.md phase). Until then keep the [hooks] block
# commented out — otherwise every `mise install` will fail.
# postinstall = "ansible-galaxy install -r {{config_root}}/provision/openmediavault/requirements.yaml"
```

**Megjegyzés:** A `JUST_UNSTABLE=1` engedélyezi a `mod` keyword-öt (jelenleg unstable feature). A verziók a bjw-s repo aktuális verzióit követik — Renovate frissíteni fogja.

**Mise registry nevek figyelmeztető lista** (nem mindig az, ami a binary neve):
- `flux2` → installált binary: `flux` (a `flux` név foglalt a registry-ben más csomagra).
- `aqua:mitsuhiko/minijinja` → installált binary: `minijinja-cli` (a `minijinja-cli` név nincs a registry-ben).
- A többi tool (kubectl, talosctl, helm, helmfile, just, sops, age, yq, jq, gum, terraform, pre-commit, 1password-cli) registry- és binary-neve egyezik.
- Ha `mise install` "not found in mise tool registry" hibát ad, először `mise registry | grep <name>` paranccsal nézz utána.

## `.minijinja.toml`

**Fájl:** `.minijinja.toml`

```toml
trim-blocks = true
lstrip-blocks = true
autoescape = "none"
```

A minijinja-cli ezeket a default-okat alkalmazza minden render-nél.

## `kubernetes/mod.just`

A bjw-s teljes `kubernetes/mod.just`-ot átemeljük, kis adaptációval:

**Fájl:** `kubernetes/mod.just`

```just
set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'

[private]
[script]
default:
    just -l k8s

[doc('Browse a PVC')]
[script]
browse-pvc namespace claim:
    kubectl browse-pvc -n {{ namespace }} -i mirror.gcr.io/alpine:latest {{ claim }}

[doc('Open a shell on a node')]
[script]
node-shell node:
    kubectl debug node/{{ node }} -n default -it --image='mirror.gcr.io/alpine:latest' --profile sysadmin
    kubectl delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug

[doc('Prune pods in Failed, Pending, or Succeeded state')]
[script]
prune-pods:
    for phase in Failed Pending Succeeded; do
      kubectl delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true
    done

[doc('Apply local Flux Kustomization')]
[script]
apply-ks ns ks:
    just k8s render-local-ks "{{ ns }}" "{{ ks }}" \
      | kubectl apply --server-side --force-conflicts --field-manager=kustomize-controller -f -

[doc('Delete local Flux Kustomization')]
[script]
delete-ks ns ks:
    just k8s render-local-ks "{{ ns }}" "{{ ks }}" | kubectl delete -f -

[doc('Sync single Flux HelmRelease')]
[script]
sync-hr ns name:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite hr "{{ name }}" \
      reconcile.fluxcd.io/requestedAt="$(date +%s)" \
      reconcile.fluxcd.io/forceAt="$(date +%s)"

[doc('Sync single Flux Kustomizations')]
[script]
sync-ks ns name:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite ks "{{ name }}" \
      reconcile.fluxcd.io/requestedAt="$(date +%s)"

[doc('Sync single ExternalSecret')]
[script]
sync-es ns name:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite es "{{ name }}" \
      force-sync="$(date +%s)"

[doc('Sync all HRs / KS / ES')]
[script]
sync-all type:
    kubectl get {{ type }} --no-headers -A | while read -r ns name _; do
      just k8s sync-{{ type }} "$ns" "$name"
    done

[doc('Snapshot a VolSync ReplicationSource')]
[script]
snapshot ns name:
    kubectl -n "{{ ns }}" patch replicationsources "{{ name }}" --type merge \
      -p '{"spec":{"trigger":{"manual":"'"$(date +%s)"'"}}}'

[doc('Snapshot ALL VolSync ReplicationSources (NUKE — careful)')]
[script]
snapshot-all:
    kubectl get replicationsources --no-headers -A | while read -r ns name _; do
      just k8s snapshot "$ns" "$name"
    done

[doc('Wait for VolSync ReplicationDestination to complete')]
[script]
wait-rd ns name:
    kubectl -n "{{ ns }}" wait --for=condition=Synchronizing=False --timeout=30m replicationdestination/"{{ name }}"

[doc('Trigger bootstrap VolSync restore for an app')]
[script]
restore app ns="default":
    kubectl -n "{{ ns }}" patch replicationdestination "{{ app }}-bootstrap" --type merge \
      -p '{"spec":{"trigger":{"manual":"restore-once"}}}'
    just k8s wait-rd "{{ ns }}" "{{ app }}-bootstrap"

[doc('List failed Helm Releases')]
[script]
failed-hrs:
    kubectl get hr --all-namespaces | grep -E "False|Unknown" || echo "All HRs healthy"

[doc('Restart all failed HelmReleases (suspend+resume)')]
[script]
restart-failed-hrs:
    kubectl get hr --all-namespaces | grep False | awk '{print $2, $1}' | xargs -L 1 bash -c 'flux suspend hr $0 -n $1'
    kubectl get hr --all-namespaces | grep False | awk '{print $2, $1}' | xargs -L 1 bash -c 'flux resume hr $0 -n $1'

[doc('List Kopia snapshots for a ReplicationSource')]
[script]
list-snapshots rsrc ns="default":
    kubectl -n volsync-system exec deploy/kopia -- \
      kopia snapshot list "{{ rsrc }}@{{ ns }}:/data" --all --json \
      | jq -r '.[] | [.startTime, .id, .stats.totalSize] | @tsv' \
      | column -t

[private]
[script]
render-local-ks ns ks:
    flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ ks }}"
```

## `kubernetes/bootstrap/mod.just`

A 04-es docban már részletezett. Itt referenciaként:
- `just k8s-bootstrap cluster` — teljes lánc (talos → k8s → kubeconfig → namespaces → resources → crds → apps)
- `just k8s-bootstrap apps` — csak a helmfile sync
- `just k8s-bootstrap crds` — csak CRD apply
- Privát stage recipe-ek

## `kubernetes/talos/mod.just`

A 02-es docban már részletezett. Itt referenciaként:
- `just talos apply-node <ip>` — config apply egy node-ra
- `just talos apply-cluster` — minden node-ra
- `just talos gen-schematic-id` — schematic SHA
- `just talos download-image <version> <schematic>` — installer ISO
- `just talos reboot-node <ip>`
- `just talos reset-node <ip>`
- `just talos upgrade-node <ip>`
- `just talos upgrade-k8s <version>`

## `provision/openmediavault/mod.just`

**Fájl:** `provision/openmediavault/mod.just`

```just
set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

omv_dir := justfile_dir() + '/provision/openmediavault'

[private]
[script]
default:
    just -l omv

[doc('Install / configure OMV via Ansible (idempotent)')]
[script]
install:
    cd {{ omv_dir }} && \
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml

[doc('Run only the package update role')]
[script]
update:
    cd {{ omv_dir }} && \
    ansible-playbook -i inventory/hosts.yml playbooks/update.yml

[doc('Sanity check: ping host and verify NFS')]
[script]
check:
    cd {{ omv_dir }} && \
    ansible -i inventory/hosts.yml omv -m ping && \
    showmount -e 192.168.1.10
```

Részletek a [10-omv-ansible.md](./10-omv-ansible.md)-ben.

## `provision/cloudflare/mod.just`

**Fájl:** `provision/cloudflare/mod.just`

```just
set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

tf_dir := justfile_dir() + '/provision/cloudflare'

[private]
[script]
default:
    just -l cloudflare

[doc('terraform init')]
[script]
init:
    cd {{ tf_dir }} && terraform init -upgrade

[doc('terraform plan')]
[script]
plan:
    cd {{ tf_dir }} && terraform plan

[doc('terraform apply')]
[script]
apply:
    cd {{ tf_dir }} && terraform apply

[doc('terraform unlock')]
[script]
unlock id:
    cd {{ tf_dir }} && terraform force-unlock {{ id }}
```

Hasonlóan `provision/ovh/mod.just`.

## Régi Task → új Just mapping táblázat

| Régi `task` | Új `just` | Megjegyzés |
|---|---|---|
| `task an:init` | **TÖRÖL** | Ansible K3s install megszűnik |
| `task an:list` | **TÖRÖL** | |
| `task an:prepare` | **TÖRÖL** | |
| `task an:install` | **TÖRÖL** | Talos saját maga telepedik |
| `task an:nuke` | `just talos reset-cluster reboot` | Talos reset |
| `task an:ping` | `just omv check` | csak OMV-re (Talos: `talosctl health`) |
| `task an:uptime` | `talosctl -n <ip> dmesg` | Talos-natív |
| `task an:rollout-reboot` | `just talos reboot-node <ip>` | |
| `task an:force-reboot` | `just talos reset-node <ip>` | |
| `task an:force-poweroff` | `talosctl -n <ip> shutdown` | |
| `task es:sync` | `just k8s sync-es <ns> <name>` | egyszerűbb név |
| `task fx:verify` | `flux check --pre` | natív flux parancs |
| `task fx:install` | `just k8s-bootstrap cluster` | Talos bootstrap is benne |
| `task fx:reconcile` | `flux reconcile -n flux-system ks cluster-apps --with-source` | natív |
| `task fx:hr-restart` | `just k8s restart-failed-hrs` | |
| `task fx:nodes` | `kubectl get nodes` | natív |
| `task fx:pods` | `kubectl get pods -A` | natív |
| `task fx:kustomizations` | `kubectl get ks -A` | natív |
| `task fx:helmreleases` | `kubectl get hr -A` | natív |
| `task fx:gitrepositories` | `kubectl get gitrepository -A` | natív |
| `task fx:certificates` | `kubectl get certificate -A` | natív |
| `task fx:gateways` | `kubectl get gateway -A` | natív |
| `task hm:all` | **TÖRÖL** vagy átírjuk | Host maintenance Proxmox-specifikus volt |
| `task hm:proxmox` | **TÖRÖL** | Proxmox kiesik |
| `task hm:k8s` | **TÖRÖL** | K3s-specifikus |
| `task hm:openmediavault` | `just omv update` | átemelve |
| `task hm:openwrt` | n/a | OpenWRT manuálisan kezelve marad |
| `task k:kubeconfig` | natív: `talosctl kubeconfig -n <ip>` | |
| `task k:mount` | `just k8s browse-pvc <ns> <claim>` | |
| `task pc:init` | `pre-commit install` | natív |
| `task pc:run` | `pre-commit run --all-files` | natív |
| `task pc:update` | `pre-commit autoupdate` | natív |
| `task so:*` | natív `sops` parancsok | nincs wrapper |
| `task tf:init:cloudflare` | `just cloudflare init` | |
| `task tf:plan:cloudflare` | `just cloudflare plan` | |
| `task tf:apply:cloudflare` | `just cloudflare apply` | |
| `task tf:unlock:cloudflare` | `just cloudflare unlock <id>` | |
| `task tf:*:ovh` | `just ovh <recipe>` | |
| `task vs:list rsrc=X` | `just k8s list-snapshots X` | egyszerűbb interface |
| `task vs:snapshot rsrc=X` | `just k8s snapshot <ns> <name>` | |
| `task vs:restore` | `just k8s restore <app>` | bootstrap restore |
| `task vs:maintenance` | `kubectl -n volsync-system exec deploy/kopia -- kopia maintenance run` | natív |
| `task vs:status` | `kubectl get replicationsource -A` | natív |
| `task vs:last-backups` | `just k8s list-snapshots <app>` | |
| `task vs:restore-suspend-app` | n/a (manuálisan `flux suspend`) | |
| `task vs:restore-wipe-job` | n/a (k8s natív Job) | |
| `task vs:restore-volsync-job` | `just k8s restore <app>` | a teljes flow benne van |
| `task vs:restore-resume-app` | n/a (`flux resume`) | |

**Csökkenés**: ~40 task → ~20 just recipe. A natív parancsok közvetlenül használhatók — nem feltétlen kell wrapper minden köré.

## VolSync restore — egyszerű parancs

A jelenlegi `task vs:restore-*` lánc 4 lépésből áll (suspend → wipe → restore → resume). Az új Just recipe ezt egyszerűsíti, mert **friss cluster esetén** csak a restore kell (nincs régi PVC tartalom, amit wipe-elni kellene).

**Cutover során**:
```bash
# Egy-egy app restore-ja:
just k8s restore plex default
just k8s restore paperless default
# ...
```

A részletes flow a [11-data-migration.md](./11-data-migration.md)-ben.

**In-place restore** (ha cutover után valamit vissza kell hozni): manuálisan a flux suspend → bootstrap RD újra-trigger → wait → flux resume. Külön Just recipe ehhez nincs — ritka eset, manuális.

## Validation

```bash
# mise és just müködik:
mise --version
just --version
just -l                                         # listázza a mod group-okat

# k8s műveletek:
just k8s sync-all ks
just k8s prune-pods
just k8s failed-hrs

# OMV:
just omv check

# Cloudflare:
just cloudflare plan
```

## Migration runbook (Task → Just)

A talos branch-en egyetlen commit-tal:
1. `mkdir -p kubernetes/talos kubernetes/bootstrap provision/openmediavault`
2. `.justfile` létrehozás (root)
3. `.mise.toml` létrehozás
4. `.minijinja.toml` létrehozás
5. `kubernetes/mod.just` létrehozás
6. `kubernetes/bootstrap/mod.just` létrehozás
7. `kubernetes/talos/mod.just` létrehozás
8. `provision/openmediavault/mod.just` létrehozás (akkor is, ha az OMV deploy később jön)
9. `provision/cloudflare/mod.just`, `provision/ovh/mod.just` létrehozás
10. **TÖRÖLNI**: `Taskfile.yml`, `.taskfiles/` mappa, `CLAUDE.md` Task-referenciák update
11. `git add -A && git commit -m "🧹 chore(tooling): migrate Task to Just"`

## Rollback

A `talos` branch-en lévő munka main-en nem érinti. Ha a Just minta nem válik be, lokálisan `git checkout main` és a Task workflow változatlanul fut. Cutover ELŐTT (a talos branch merge előtt) van utolsó döntéspont.

## Open issues

- **`mise pipx:ansible` integrációja**: a bjw-s minta `pipx:ansible` és `pipx:ansible-core` mindkettő latest. Verzió-pinneléshez `pipx:ansible@10.0.0` formátum. Aktuális stabil verzió ellenőrizni.
- **`just` `mod` keyword unstable**: `JUST_UNSTABLE=1` env var kell. Just 1.45+ már stabilizálta, ellenőrizd az aktuális just docs-on.
- **`flux-local`** pip package: a `render-local-ks` recipe használja, a `mise` `[tools]` `pipx:flux-local = "latest"` sorral telepíthető.
- **CLAUDE.md frissítés**: a root `CLAUDE.md` jelenleg részletesen leírja a Task workflow-t. Ezt frissíteni kell a Just-ra cutover-rel egyszerre.
- **CI/CD**: ha jövőben GitHub Actions vagy ilyesmi futtatna `just` parancsokat, a `.mise.toml` automatic install (`mise install`) első lépés.
- **`gum` opcional**: ha valakinek nincs `gum` lokálisan, a `just log` recipe hibázik. Mise telepíti, de elszigetelt használat esetén workaround kell.
