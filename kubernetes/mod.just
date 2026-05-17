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

# === sync ===

[group('sync')]
[arg('resource', pattern='hr|ks|gitrepo|ocirepo|es')]
[doc('Sync all resources of a Flux type cluster-wide (resource=hr|ks|gitrepo|ocirepo|es)')]
[script]
sync resource:
    kubectl get {{ resource }} --no-headers -A | while read -r ns name _; do
      kubectl -n "$ns" annotate --field-manager flux-client-side-apply --overwrite {{ resource }} "$name" \
        "force-sync=$(date +%s)" \
        "reconcile.fluxcd.io/requestedAt=$(date +%s)" \
        "reconcile.fluxcd.io/forceAt=$(date +%s)"
    done

[group('sync')]
[doc('Sync single ExternalSecret')]
[script]
sync-es name ns:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite es "{{ name }}" \
      force-sync="$(date +%s)"

[group('sync')]
[doc('Sync single Flux HelmRelease')]
[script]
sync-hr name ns:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite hr "{{ name }}" \
      reconcile.fluxcd.io/requestedAt="$(date +%s)" \
      reconcile.fluxcd.io/forceAt="$(date +%s)"

[group('sync')]
[doc('Sync single Flux Kustomization')]
[script]
sync-ks name ns:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite ks "{{ name }}" \
      reconcile.fluxcd.io/requestedAt="$(date +%s)"

# === flux ===

[group('flux')]
[doc('Apply local Flux Kustomization')]
[script]
apply-ks name ns:
    just k8s render-local-ks "{{ name }}" "{{ ns }}" \
      | kubectl apply --server-side --force-conflicts --field-manager=kustomize-controller -f -

[group('flux')]
[doc('Delete local Flux Kustomization')]
[script]
delete-ks name ns:
    just k8s render-local-ks "{{ name }}" "{{ ns }}" | kubectl delete -f -

[group('flux')]
[doc('Verify Flux prerequisites (flux check --pre)')]
[script]
flux-check:
    flux check --pre

[group('flux')]
[doc('Force a full Flux reconcile: refresh the Git source, then reconcile both root Kustomizations (cluster-vars + cluster-apps). Structured per-stage logging with duration.')]
[script]
flux-reconcile:
    t0=${SECONDS}
    just log info "Stage: reconcile Git source"
    flux reconcile source git flux-system -n flux-system
    t1=${SECONDS}
    just log info "Reconciled Git source" duration "$((t1-t0))s"
    just log info "Stage: reconcile cluster-vars"
    flux reconcile kustomization cluster-vars -n flux-system
    t2=${SECONDS}
    just log info "Reconciled cluster-vars" duration "$((t2-t1))s"
    just log info "Stage: reconcile cluster-apps"
    flux reconcile kustomization cluster-apps -n flux-system
    t3=${SECONDS}
    just log info "Reconciled cluster-apps" duration "$((t3-t2))s"
    just log info "flux-reconcile complete" total "$((t3-t0))s"

[group('flux')]
[doc('List failed Helm Releases')]
[script]
list-failed-hrs:
    kubectl get hr --all-namespaces | grep -E "False|Unknown" || echo "All HRs healthy"

[group('flux')]
[doc('Restart all failed HelmReleases (suspend + resume) — JSON-based detection on the Ready=False condition, immune to flux/kubectl text-output drift')]
[script]
restart-failed-hrs:
    kubectl get hr -A -o json \
      | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="False")) | "\(.metadata.namespace) \(.metadata.name)"' \
      | while read -r ns name; do
          flux suspend hr "$name" -n "$ns"
          flux resume hr "$name" -n "$ns"
        done

# === debug ===

[group('debug')]
[doc('Open a debug Alpine shell with a PVC mounted (default mountpath=/mnt; pod auto-removes on exit)')]
[script]
browse-pvc claim ns="default" mountpath="/mnt":
    kubectl run -n "{{ ns }}" "debug-{{ claim }}" -it --rm --restart=Never \
      --image=mirror.gcr.io/alpine:latest \
      --overrides='{
        "apiVersion": "v1",
        "spec": {
          "containers": [{
            "name": "debug",
            "image": "mirror.gcr.io/alpine:latest",
            "command": ["/bin/sh"],
            "stdin": true,
            "tty": true,
            "workingDir": "{{ mountpath }}",
            "volumeMounts": [{"name": "data", "mountPath": "{{ mountpath }}"}]
          }],
          "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "{{ claim }}"}}],
          "restartPolicy": "Never"
        }
      }'

[group('debug')]
[doc('Open a shell on a node (Alpine, sysadmin profile; debug pod is cleaned up on EXIT — even on Ctrl-C)')]
[script]
node-shell node:
    trap 'kubectl delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug --field-selector spec.nodeName={{ node }} --ignore-not-found --wait=false' EXIT
    kubectl debug node/{{ node }} -n default -it --image='mirror.gcr.io/alpine:latest' --profile sysadmin

[group('debug')]
[doc('Prune pods in Failed, Pending, or Succeeded state')]
[script]
prune-pods:
    for phase in Failed Pending Succeeded; do
      kubectl delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true
    done

[group('debug')]
[doc('Decode and print a Kubernetes Secret (all data keys, base64-decoded; KEY=value lines — no krew plugin needed)')]
[script]
view-secret secret ns:
    kubectl get secret -n "{{ ns }}" "{{ secret }}" -o json \
      | jq -r '.data // {} | to_entries[] | "\(.key)=\(.value | @base64d)"'

[private]
[script]
render-local-ks name ns:
    flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ name }}"
