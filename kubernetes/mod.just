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
[doc('Force a full Flux reconcile: refresh the Git source, then reconcile both root Kustomizations (cluster-vars + cluster-apps)')]
[script]
flux-reconcile:
    flux reconcile source git flux-system -n flux-system
    flux reconcile kustomization cluster-vars -n flux-system
    flux reconcile kustomization cluster-apps -n flux-system

[group('flux')]
[doc('List failed Helm Releases')]
[script]
list-failed-hrs:
    kubectl get hr --all-namespaces | grep -E "False|Unknown" || echo "All HRs healthy"

[group('flux')]
[doc('Restart all failed HelmReleases (suspend + resume)')]
[script]
restart-failed-hrs:
    kubectl get hr --all-namespaces | grep False | awk '{print $2, $1}' | xargs -L 1 bash -c 'flux suspend hr $0 -n $1'
    kubectl get hr --all-namespaces | grep False | awk '{print $2, $1}' | xargs -L 1 bash -c 'flux resume hr $0 -n $1'

# === debug ===

[group('debug')]
[doc('Browse a PVC')]
[script]
browse-pvc claim ns="default":
    kubectl browse-pvc -n {{ ns }} -i mirror.gcr.io/alpine:latest {{ claim }}

[group('debug')]
[doc('Run a debug Alpine pod with a PVC mounted at /data/config (Ctrl-D to clean up)')]
[script]
mount-pvc claim ns="default":
    kubectl run -n "{{ ns }}" "debug-{{ claim }}" -i --tty --rm --image=null --privileged --overrides='{
      "apiVersion": "v1",
      "spec": {
        "containers": [{
          "name": "debug",
          "image": "docker.io/library/alpine:latest",
          "command": ["/bin/sh"],
          "stdin": true,
          "stdinOnce": true,
          "tty": true,
          "volumeMounts": [{"name": "config", "mountPath": "/data/config"}]
        }],
        "volumes": [{"name": "config", "persistentVolumeClaim": {"claimName": "{{ claim }}"}}],
        "restartPolicy": "Never"
      }
    }'

[group('debug')]
[doc('Open a shell on a node')]
[script]
node-shell node:
    kubectl debug node/{{ node }} -n default -it --image='mirror.gcr.io/alpine:latest' --profile sysadmin
    kubectl delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug

[group('debug')]
[doc('Prune pods in Failed, Pending, or Succeeded state')]
[script]
prune-pods:
    for phase in Failed Pending Succeeded; do
      kubectl delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true
    done

[group('debug')]
[doc('Decode and print a Kubernetes Secret (requires kubectl-view-secret krew plugin)')]
[script]
view-secret secret ns:
    kubectl view-secret -n {{ ns }} {{ secret }}

[private]
[script]
render-local-ks name ns:
    flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ name }}"
