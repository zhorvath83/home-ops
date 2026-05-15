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

[doc('Sync single Flux Kustomization')]
[script]
sync-ks ns name:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite ks "{{ name }}" \
      reconcile.fluxcd.io/requestedAt="$(date +%s)"

[doc('Sync single ExternalSecret')]
[script]
sync-es ns name:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite es "{{ name }}" \
      force-sync="$(date +%s)"

[doc('Sync all HRs / KS / ES of the given type')]
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

[doc('Snapshot ALL VolSync ReplicationSources (cluster-wide)')]
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

[doc('Restart all failed HelmReleases (suspend + resume)')]
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
