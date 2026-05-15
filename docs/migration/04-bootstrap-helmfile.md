# 04 — Bootstrap helmfile chain

## Status — 2026-05-16

| Részfeladat | Állapot |
|---|---|
| Cilium app subtree (`kubernetes/apps/kube-system/cilium/{app,config}`) — bootstrap helmfile `values.yaml.gotmpl` forrása | ✅ Phase 3 |
| `kubernetes/flux/cluster/ks.yaml` (FluxInstance `sync.path` célja) | ✅ Phase 5 részmunka |
| bjw-s naming + GitRepository név egységesítve | ✅ Phase 6 részmunka |
| `kubernetes/apps/external-secrets/onepassword-connect/app/clustersecretstore.yaml` (postsync hook által apply-olt) | ✅ kész — bjw-s/onedr0p mintára áthelyezve a `stores/` aldirból a `app/`-ba; CSS resource név `onepassword-connect`-re átnevezve; 1 Flux Kustomization (healthChecks + healthCheckExprs a HelmRelease + ClusterSecretStore Ready-re); 27 consumer ks.yaml `dependsOn` és 19 ExternalSecret `secretStoreRef` átírva |
| `kubernetes/apps/kube-system/coredns/` subtree | ✅ kész — bjw-s referencia értékekkel (control-plane affinity + CriticalAddonsOnly toleration), `replicaCount: 1` single-node-ra |
| `kubernetes/apps/flux-system/flux-operator/` subtree | ✅ kész |
| `kubernetes/apps/flux-system/flux-instance/` subtree | ✅ kész — `sync.url` a `zhorvath83/home-ops` repo, `sync.ref: refs/heads/talos`, `sync.path: kubernetes/flux/cluster`; cutoverkor `refs/heads/main`-re kell állítani |
| `kubernetes/bootstrap/helmfile.d/00-crds.yaml` (envoy-gateway, kube-prometheus-stack, grafana-operator) | ✅ kész |
| `kubernetes/bootstrap/helmfile.d/01-apps.yaml` (Cilium → CoreDNS → cert-manager → ESO → 1P Connect → flux-operator → flux-instance, 7 release) | ✅ kész — `cert-manager-webhook-ovh` kihagyva (Cloudflare DNS-01 solver beépített) |
| `kubernetes/bootstrap/helmfile.d/templates/values.yaml.gotmpl` (DRY: olvas `app/helmrelease.yaml`-ből) | ✅ kész |
| `kubernetes/bootstrap/resources.yaml.j2` (1P Connect creds + sops-age Secret, `op://` ref-ek) | ✅ kész |
| `kubernetes/bootstrap/mod.just` recipe-ek (`cluster`, `talos`, `kubernetes`, `kubeconfig`, `wait`, `namespaces`, `resources`, `crds`, `apps`) | ✅ kész |
| `kubernetes/bootstrap/flux/` k3s-éra legacy törlés | ✅ kész |
| `1Password HomeOps/homelab-age-key` item létrehozva | ⏸ verifikálandó éles futtatás előtt |
| `1Password HomeOps/1password-connect-kubernetes` item (credentials + token) | ⏸ verifikálandó éles futtatás előtt |
| `just k8s-bootstrap cluster` éles futtatás | ⏸ pending — végrehajtás következő session |

## Cél

A Talos cluster bootstrap után az alap Kubernetes platform (CNI, DNS, cert-manager, ESO, Flux) deklaratív helmfile chain-nel install-álódik. Ez váltja le a jelenlegi Ansible-alapú K3s bootstrap-et.

## Inputs

- Talos node `Ready` állapotban (Cilium install már megtörtént a chain első lépéseként — lásd [02](./02-talos-bootstrap.md) Stage 4).
- `kubeconfig` lokális gépen elérhető.
- 1Password CLI (`op`) bejelentkezve, vault `Automation/1password connect` item-tel.
- `helmfile`, `kubectl`, `yq`, `gum`, `mise` telepítve (`.mise.toml`-on keresztül).

## Tervezett fájl-layout

```
kubernetes/bootstrap/
├── mod.just                              # bootstrap recipes (cluster, talos, kubernetes, apps stb.)
├── resources.yaml.j2                     # 1Password Connect creds Secret-ek bootstrap időre
└── helmfile.d/
    ├── 00-crds.yaml                      # CRD-only helmfile (Envoy Gateway, Prometheus Operator, Grafana Operator)
    ├── 01-apps.yaml                      # main bootstrap chain
    └── templates/
        └── values.yaml.gotmpl            # DRY: app/ alól olvas value-kat
```

## Helmfile values.yaml.gotmpl — DRY trükk

A bootstrap helmfile **NEM duplikálja** a Helm value-kat. A `templates/values.yaml.gotmpl` egyetlen sorral beolvassa az adott app `helmrelease.yaml` `spec.values` szekcióját:

**Fájl:** `kubernetes/bootstrap/helmfile.d/templates/values.yaml.gotmpl`

```gotemplate
{{ (fromYaml (readFile (printf "../../../../kubernetes/apps/%s/%s/app/helmrelease.yaml" .Release.Namespace .Release.Name))).spec.values | toYaml }}
```

Magyarázat: ha a release neve `cilium` és namespace `kube-system`, akkor a `kubernetes/apps/kube-system/cilium/app/helmrelease.yaml`-ből olvassa a `spec.values` mezőt. Tehát **bootstrap és runtime ugyanazt a Helm value-t használja** — nincs drift.

## CRD bootstrap (00-crds.yaml)

A CRD-k szétválasztása a fő install-tól megszünteti a Flux `dependsOn` láncot a CRD-re hivatkozó komponensekre.

**Fájl:** `kubernetes/bootstrap/helmfile.d/00-crds.yaml`

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/helmfile
helmDefaults:
  cleanupOnFail: true
  wait: true
  waitForJobs: true
  args:
    - --include-crds
    - --no-hooks                              # csak CRD-t akarunk

releases:
  - name: envoy-gateway
    namespace: networking
    chart: oci://mirror.gcr.io/envoyproxy/gateway-helm
    version: 1.8.0

  - name: kube-prometheus-stack
    namespace: observability
    chart: oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack
    version: 85.0.3

  - name: grafana-operator
    namespace: observability
    chart: oci://ghcr.io/grafana/helm-charts/grafana-operator
    version: 5.22.2
```

**Verziók**: a bjw-s aktuális verziókkal indulnak — Renovate frissíteni fogja.

**Apply mód** (a `mod.just` `crds` recipe):

```bash
helmfile -f kubernetes/bootstrap/helmfile.d/00-crds.yaml template -q \
  | yq ea -e 'select(.kind == "CustomResourceDefinition")' \
  | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -
```

`yq` filter csak CRD-ket szűr ki, a többi resource-t (Deployment, ServiceAccount stb.) eldobja.

## Resources bootstrap (resources.yaml.j2)

**Fájl:** `kubernetes/bootstrap/resources.yaml.j2`

```yaml
---
# 1Password Connect creds — a Connect server-hez kellnek
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-credentials-secret
  namespace: external-secrets
stringData:
  1password-credentials.json: 'op://HomeOps/1password-connect-kubernetes/credentials'
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-vault-secret
  namespace: external-secrets
stringData:
  token: op://HomeOps/1password-connect-kubernetes/token
---
# SOPS age key — Flux ezzel decrypt-eli a *.sops.yaml fájlokat reconcile-on
# (cluster-secrets.sops.yaml + homepage/secret.sops.yaml)
apiVersion: v1
kind: Secret
metadata:
  name: sops-age
  namespace: flux-system
stringData:
  age.agekey: op://HomeOps/homelab-age-key/keys.txt
```

Apply (`mod.just` `resources` recipe):

```bash
minijinja-cli kubernetes/bootstrap/resources.yaml.j2 | op inject | kubectl apply --server-side -f -
```

Ez a **három Secret**:
- `onepassword-connect-credentials-secret` + `onepassword-connect-vault-secret`: az 1Password Connect chart inicializálásához.
- `sops-age`: a Flux Kustomization-ök `decryption.secretRef`-ben hivatkozzák, hogy a SOPS-titkosított fájlokat dekódolják reconcile időben.

**1Password item path-ek** (a `op inject` ezt cseréli):
- `op://HomeOps/1password-connect-kubernetes/credentials` — Connect server credentials.json
- `op://HomeOps/1password-connect-kubernetes/token` — vault token
- `op://HomeOps/homelab-age-key/keys.txt` — age private key (a jelenlegi K3s setup-ban is itt él)

## SOPS bootstrap

A `cluster-secrets.sops.yaml` és minden további `*.sops.yaml` fájl (pl. `homepage/secret.sops.yaml`) Flux reconcile-on dekódolódik a `sops-age` Secret-tel. A bootstrap-nek **csak ennyit** kell tennie:
1. `sops-age` Secret létrehozás (a fenti `resources.yaml.j2`).
2. A Flux Kustomization-ök (`cluster-vars` és `cluster-apps`) `decryption: { provider: sops, secretRef: { name: sops-age } }`-et tartalmazzák — részletek a [05-flux-operator.md](./05-flux-operator.md)-ben.

A bootstrap-időben **NEM** dekódoljuk manuálisan a SOPS fájlokat — a Flux reconcile végzi minden alkalommal. A `sops` CLI csak lokális szerkesztéshez kell (`sops edit kubernetes/flux/vars/cluster-secrets.sops.yaml`).

## Main bootstrap chain (01-apps.yaml)

**Fájl:** `kubernetes/bootstrap/helmfile.d/01-apps.yaml`

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/helmfile

helmDefaults:
  cleanupOnFail: true
  wait: true
  waitForJobs: true

releases:
  # 1. Cilium CNI — első, mert nélküle a node NotReady
  - name: cilium
    namespace: kube-system
    chart: oci://quay.io/cilium/charts/cilium
    version: 1.19.4
    values:
      - templates/values.yaml.gotmpl
    hooks:
      # CRD-k várása
      - command: bash
        args:
          - -c
          - until kubectl get crd ciliumloadbalancerippools.cilium.io ciliuml2announcementpolicies.cilium.io &>/dev/null; do sleep 5; done
        events: [postsync]
        showlogs: true
      # IP pool + L2 policy apply
      - command: kubectl
        args:
          - apply
          - --namespace=kube-system
          - --server-side
          - --field-manager=kustomize-controller
          - --kustomize
          - ../../apps/kube-system/cilium/config/
        events: [postsync]
        showlogs: true

  # 2. CoreDNS — Cilium után, Talos-built-in CoreDNS disabled
  - name: coredns
    namespace: kube-system
    chart: oci://ghcr.io/coredns/charts/coredns
    version: 1.45.2
    values:
      - templates/values.yaml.gotmpl
    needs:
      - kube-system/cilium

  # 3. cert-manager-webhook-ovh — OVH DNS-01 challenge support
  - name: cert-manager-webhook-ovh
    namespace: cert-manager
    chart: oci://ghcr.io/home-operations/charts-mirror/cert-manager-webhook-ovh
    version: 0.9.2
    values:
      - templates/values.yaml.gotmpl
    needs:
      - kube-system/coredns

  # 4. cert-manager
  - name: cert-manager
    namespace: cert-manager
    chart: oci://quay.io/jetstack/charts/cert-manager
    version: v1.20.2
    values:
      - templates/values.yaml.gotmpl
    needs:
      - cert-manager/cert-manager-webhook-ovh

  # 5. External Secrets Operator
  - name: external-secrets
    namespace: external-secrets
    chart: oci://ghcr.io/external-secrets/charts/external-secrets
    version: 2.4.1
    values:
      - templates/values.yaml.gotmpl
    needs:
      - cert-manager/cert-manager

  # 6. 1Password Connect (server) + ClusterSecretStore
  - name: onepassword-connect
    namespace: external-secrets
    chart: oci://ghcr.io/1password/connect
    version: 2.4.1
    values:
      - templates/values.yaml.gotmpl
    needs:
      - external-secrets/external-secrets
    hooks:
      # ClusterSecretStore apply (1Password backend regisztráció)
      - command: kubectl
        args:
          - apply
          - --server-side
          - --field-manager=kustomize-controller
          - --filename
          - ../../apps/external-secrets/onepassword-connect/app/clustersecretstore.yaml
        events: [postsync]
        showlogs: true

  # 7. Flux Operator — Flux controller-eket telepít (operator-pattern)
  - name: flux-operator
    namespace: flux-system
    chart: oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator
    version: 0.49.0
    values:
      - templates/values.yaml.gotmpl
    needs:
      - external-secrets/onepassword-connect

  # 8. Flux Instance — FluxInstance CR ami a cluster-szintű reconcile-t indítja
  - name: flux-instance
    namespace: flux-system
    chart: oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance
    version: 0.49.0
    wait: false                                # GitRepo reconcile aszinkron
    values:
      - templates/values.yaml.gotmpl
    needs:
      - flux-system/flux-operator
```

**Spegel kihagyva**: bjw-s/onedr0p mind tartalmazza a peer-to-peer image cache-t, de single-node-on **nincs peer**. Worker node bővítéskor adhatjuk hozzá.

## Bootstrap orchestration

Az egész folyamatot egyetlen Just recipe vezényli (mod.just stages-zel):

**Fájl:** `kubernetes/bootstrap/mod.just`

```just
set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'
bootstrap_dir := kubernetes_dir + '/bootstrap'
controller := `talosctl config info -o json | jq -r '.endpoints[]' | shuf -n 1`
nodes := `talosctl config info -o yaml | yq -e '.nodes | join (" ")'`

[private]
[script]
default:
    just -l k8s-bootstrap

[doc('Bootstrap Cluster — teljes Talos+K8s lánc')]
[script]
cluster: talos kubernetes (kubeconfig "node") wait namespaces resources crds apps kubeconfig

[private]
[script]
talos:
    just log info "Stage: talos config apply"
    for n in {{ nodes }}; do
      if ! op=$(just talos::apply-node "$n" --insecure 2>&1); then
        if [[ "$op" == *"certificate required"* ]]; then
          just log info "Talos already configured, skipping" "node" "$n"
          continue
        fi
        just log fatal "Talos config apply failed" "node" "$n" "output" "$op"
      fi
    done

[private]
[script]
kubernetes:
    just log info "Stage: K8s bootstrap"
    until op=$(talosctl -n "{{ controller }}" bootstrap 2>&1 || true) && [[ "$op" == *"AlreadyExists"* ]]; do
      just log info "Waiting for K8s bootstrap..."
      sleep 5
    done

[private]
[script]
kubeconfig lb="cilium":
    just log info "Stage: fetch kubeconfig"
    talosctl kubeconfig -n "{{ controller }}" -f --force-context-name main {{ justfile_dir() }}

[private]
[script]
wait:
    just log info "Stage: wait for node"
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
      just log info "Waiting for node to appear..."
      sleep 5
    done

[private]
[script]
namespaces:
    just log info "Stage: create namespaces"
    find "{{ kubernetes_dir }}/apps" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | while IFS= read -r ns; do
      kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply --server-side -f -
    done

[private]
[script]
resources:
    just log info "Stage: bootstrap resources (1Password Connect creds)"
    just template "{{ bootstrap_dir }}/resources.yaml.j2" | kubectl apply --server-side -f -

[private]
[script]
crds:
    just log info "Stage: apply CRDs"
    helmfile -f "{{ bootstrap_dir }}/helmfile.d/00-crds.yaml" template -q \
      | yq ea -e 'select(.kind == "CustomResourceDefinition")' \
      | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -

[private]
[script]
apps:
    just log info "Stage: helmfile sync (main chain)"
    helmfile -f "{{ bootstrap_dir }}/helmfile.d/01-apps.yaml" sync --hide-notes
```

## Egész bootstrap parancs

```bash
# Lokálisan, miután a HP boot-olt USB-ről Talos installer módban:
op signin                                      # 1Password session
export TALOS_SCHEMATIC_ID="$(just talos gen-schematic-id)"
export TALOS_VERSION="$(curl -s https://api.github.com/repos/siderolabs/talos/releases/latest | jq -r .tag_name)"
export KUBERNETES_VERSION="$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r .tag_name)"

just k8s-bootstrap cluster
```

Egyetlen parancs → teljes cluster (Talos config → bootstrap → kubeconfig → namespaces → resources → CRDs → 8 release helmfile chain).

**Időbecslés**: 10-20 perc, mire az Helmfile lánc végigfut és a Flux Instance reconcile-olódik.

## Validation lépésről lépésre

```bash
# Stage: talos
talosctl -n 192.168.1.11 get machineconfig
# config betöltve

# Stage: kubernetes
talosctl -n 192.168.1.11 service etcd
# etcd Healthy

# Stage: kubeconfig
kubectl get nodes
# main NotReady (CNI még nem)

# Stage: namespaces
kubectl get ns
# cert-manager, default, external-secrets, flux-system, kube-system, networking, observability, system-upgrade, volsync-system

# Stage: resources
kubectl -n external-secrets get secret onepassword-connect-credentials-secret
# létezik
kubectl -n external-secrets get secret onepassword-connect-vault-secret
# létezik
kubectl -n flux-system get secret sops-age
# létezik (Flux SOPS decryption-höz)

# Stage: crds
kubectl get crd | grep -E "gateway|prometheus|grafana"
# CRD-k apply-elve

# Stage: apps (helmfile végén)
kubectl get nodes
# main Ready

helm -n cert-manager list
# cert-manager DEPLOYED

helm -n flux-system list
# flux-operator, flux-instance DEPLOYED

kubectl -n flux-system get fluxinstance
# flux-instance Ready

# Stage: post-bootstrap — Flux reconcile (a FluxInstance hozza létre az auto Kustomization-t,
#   ami létrehozza a cluster-vars + cluster-apps Kustomization-okat)
kubectl -n flux-system get ks
# cluster-vars Ready=True
# cluster-apps Ready=True (vagy WaitingForDependency: cluster-vars rövid ideig)

# cluster-secrets Secret létrejön (SOPS dekódolva a sops-age Secret-tel):
kubectl -n flux-system get secret cluster-secrets
# létezik, 2 data field (PUBLIC_DOMAIN, SECRET_QBITTORRENT_PW)

# cluster-settings ConfigMap szintén:
kubectl -n flux-system get cm cluster-settings -o jsonpath='{.data.CLUSTER_NODE_1_CIDR}'
# 192.168.1.11/32
```

## Rollback

### Helmfile egyik release megakad

```bash
# Adott release release log-ja:
helm -n kube-system history cilium
helm -n kube-system status cilium

# Helmfile újrafutás (csak az adott release-re):
helmfile -f kubernetes/bootstrap/helmfile.d/01-apps.yaml -l name=cilium sync
```

### Teljes lánc megakad valahol középen

`needs:` miatt a függő release-ek várnak. Ha pl. ESO megakad:
```bash
kubectl -n external-secrets get pods
# crashloop?
kubectl -n external-secrets logs deploy/external-secrets-webhook
# diagnose

# Fix → helmfile retry:
just k8s-bootstrap apps
```

A helmfile idempotens — már install-elt release-eket nem nyúlja, csak ami hiányzik vagy diff-ben van.

### Teljes cluster nuke + reinstall

```bash
just talos reset-cluster reboot
# minden disk wipe
# majd újra:
just k8s-bootstrap cluster
```

## Open issues

- **clustersecretstore.yaml apply hook timing**: a 1Password Connect pod-ja várhat néhány másodpercet, mire ready. Ha a `kubectl apply` hook túl gyorsan fut, a CRO még nem létezik. A bjw-s minta `wait: true` defaultja várja a HelmRelease ready-t — ez fedezi. Ha mégis hibázik, `helmfile.d/01-apps.yaml` `onepassword-connect` release-hez plusz `hooks: [postsync: until kubectl get clustersecretstore.io ...]`.
- **`needs:` és kétmenetű reconcile**: ha Flux Operator install-ja előtt a Helmfile lánc megakad, az ESO pod-ok ott vannak, de a runtime Flux még nem tudja kezelni őket. A `helmfile sync` újrafuttatása ezt megoldja, vagy második menetben a Flux átveszi.
- **Spegel hozzáadása**: csak akkor, ha worker node lesz. Akkor a `01-apps.yaml`-be `kube-system/coredns` után `needs: [kube-system/coredns]` mellé.
- **Custom helm registry mirror**: a `mirror.gcr.io/...` aliasokat Renovate `registryAlias`-ban kezelni — lásd [09-renovate-rewrite.md](./09-renovate-rewrite.md).
