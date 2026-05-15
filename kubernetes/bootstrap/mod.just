set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'
bootstrap_dir := kubernetes_dir + '/bootstrap'

# controller: pick a node from the active talosconfig.endpoints.
controller := `talosctl config info -o json 2>/dev/null | jq -r '.endpoints[]' 2>/dev/null | shuf -n 1 || echo 'cp0-k8s'`

# nodes: every node listed in talosconfig.
nodes := `talosctl config info -o yaml 2>/dev/null | yq -e '.nodes | join(" ")' 2>/dev/null || echo 'cp0-k8s'`

[private]
[script]
default:
    just -l k8s-bootstrap

[doc('Bootstrap the full Talos + Kubernetes platform chain')]
[script]
cluster: talos kubernetes kubeconfig wait namespaces resources crds apps

[private]
[doc('Stage: apply Talos machine config to every node (idempotent — skips already configured nodes)')]
[script]
talos:
    just log info "Stage: talos config apply"
    for n in {{ nodes }}; do
      if ! op=$(just talos apply-node "$n" --insecure 2>&1); then
        if [[ "$op" == *"certificate required"* ]]; then
          just log info "Talos already configured, skipping" "node" "$n"
          continue
        fi
        just log fatal "Talos config apply failed" "node" "$n" "output" "$op"
      fi
    done

[private]
[doc('Stage: trigger Kubernetes bootstrap (etcd init) on the first controller')]
[script]
kubernetes:
    just log info "Stage: K8s bootstrap"
    until op=$(talosctl -n "{{ controller }}" bootstrap 2>&1 || true) && [[ "$op" == *"AlreadyExists"* ]]; do
      just log info "Waiting for K8s bootstrap to take..."
      sleep 5
    done

[private]
[doc('Stage: fetch kubeconfig from a controller node')]
[script]
kubeconfig:
    just log info "Stage: fetch kubeconfig"
    talosctl -n "{{ controller }}" kubeconfig -f --force-context-name main "{{ justfile_dir() }}/kubeconfig"

[private]
[doc('Stage: wait until the node registers with the K8s API (Ready=False is fine — CNI is the next stage)')]
[script]
wait:
    just log info "Stage: wait for node registration"
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
      just log info "Node not registered yet, retrying..."
      sleep 5
    done

[private]
[doc('Stage: create all app namespaces from the kubernetes/apps directory layout')]
[script]
namespaces:
    just log info "Stage: create namespaces"
    find "{{ kubernetes_dir }}/apps" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | while IFS= read -r ns; do
      kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply --server-side -f -
    done

[private]
[doc('Stage: render resources.yaml.j2 (op inject) and apply bootstrap-time Secrets')]
[script]
resources:
    just log info "Stage: bootstrap resources (1Password Connect + sops-age)"
    just template "{{ bootstrap_dir }}/resources.yaml.j2" | kubectl apply --server-side -f -

[private]
[doc('Stage: extract CRDs from upstream charts and apply them out-of-band')]
[script]
crds:
    just log info "Stage: apply CRDs"
    helmfile -f "{{ bootstrap_dir }}/helmfile.d/00-crds.yaml" template -q \
      | yq ea -e 'select(.kind == "CustomResourceDefinition")' \
      | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -

[private]
[doc('Stage: helmfile sync the main bootstrap chain (Cilium → CoreDNS → cert-manager → ESO → 1P Connect → Flux Operator → Flux Instance)')]
[script]
apps:
    just log info "Stage: helmfile sync (main chain)"
    helmfile -f "{{ bootstrap_dir }}/helmfile.d/01-apps.yaml" sync --hide-notes
