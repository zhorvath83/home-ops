set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'
bootstrap_dir := kubernetes_dir + '/bootstrap'

# controller: the first endpoint from the active talosconfig (IP-based; what talosctl -n expects for bootstrap/kubeconfig).
controller := `talosctl config info -o json 2>/dev/null | jq -r '.endpoints[0]' 2>/dev/null || echo 'cp0-k8s'`

# nodes: derive node *names* from kubernetes/talos/nodes/<name>.yaml.j2 — the talos apply-node recipe is name-based, not IP-based.
# Backticks run with cwd = this mod's directory (kubernetes/bootstrap), so reach into the sibling talos/ tree.
nodes := `find ../talos/nodes -maxdepth 1 -name '*.yaml.j2' -exec basename {} .yaml.j2 \; | tr '\n' ' '`

[private]
[script]
default:
    just -l cluster-bootstrap

[doc('Reassemble the Talos + Kubernetes platform on already-prepared nodes. Pre-requisites: just talos gen-secrets + USB-install done manually.')]
[script]
cluster: talosconfig talos kubernetes (kubeconfig "node") wait namespaces resources crds apps kubeconfig

[private]
[doc('Stage: regenerate the local talosconfig from 1Password secrets (idempotent — overwrites the local file).')]
[script]
talosconfig:
    just log info "Stage: regenerate talosconfig from 1Password"
    just talos gen-talosconfig

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
[doc('Stage: fetch kubeconfig from a controller node. lb="cilium" keeps the cluster API endpoint from talosconfig (default, post-Cilium-L2); lb="node" rewrites the server to the controller IP (pre-CNI bootstrap).')]
[script]
kubeconfig lb="cilium":
    just log info "Stage: fetch kubeconfig" "lb" "{{ lb }}"
    talosctl -n "{{ controller }}" kubeconfig -f --force-context-name main "{{ justfile_dir() }}/kubeconfig"
    if [[ "{{ lb }}" != "cilium" ]]; then
      kubectl --kubeconfig "{{ justfile_dir() }}/kubeconfig" config set-cluster main --server "https://{{ controller }}:6443"
    fi

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
    for d in "{{ kubernetes_dir }}/apps"/*/; do
      ns=$(basename "$d")
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
