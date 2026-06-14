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

[arg('resource', pattern='hr|ks|gitrepo|ocirepo|es')]
[doc('Sync all resources of a Flux type cluster-wide (resource=hr|ks|gitrepo|ocirepo|es).')]
[group('sync')]
[script]
sync resource:
    # Annotation set depends on resource type:
    #   - es:                       force-sync  (External Secrets Operator)
    #   - hr:                       requestedAt + forceAt  (forceAt drives chart force-upgrade)
    #   - ks / gitrepo / ocirepo:   requestedAt  (forceAt has no effect on these)
    ts="$(date +%s)"
    case "{{ resource }}" in
      es)  anns=("force-sync=${ts}") ;;
      hr)  anns=("reconcile.fluxcd.io/requestedAt=${ts}" "reconcile.fluxcd.io/forceAt=${ts}") ;;
      ks|gitrepo|ocirepo) anns=("reconcile.fluxcd.io/requestedAt=${ts}") ;;
      *)   echo "Unsupported resource: {{ resource }}" >&2; exit 1 ;;
    esac
    kubectl get {{ resource }} --no-headers -A | while read -r ns name _; do
      kubectl -n "$ns" annotate --field-manager flux-client-side-apply --overwrite {{ resource }} "$name" "${anns[@]}"
    done

[doc('Sync single ExternalSecret')]
[group('sync')]
[script]
sync-es name ns:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite es "{{ name }}" \
      force-sync="$(date +%s)"

[doc('Sync single Flux HelmRelease')]
[group('sync')]
[script]
sync-hr name ns:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite hr "{{ name }}" \
      reconcile.fluxcd.io/requestedAt="$(date +%s)" \
      reconcile.fluxcd.io/forceAt="$(date +%s)"

[doc('Sync single Flux Kustomization')]
[group('sync')]
[script]
sync-ks name ns:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite ks "{{ name }}" \
      reconcile.fluxcd.io/requestedAt="$(date +%s)"

# === flux ===

[doc('Apply local Flux Kustomization')]
[group('flux')]
[script]
apply-ks name ns:
    just k8s render-local-ks "{{ name }}" "{{ ns }}" \
      | kubectl apply --server-side --force-conflicts --field-manager=kustomize-controller -f -

[doc('Delete local Flux Kustomization')]
[group('flux')]
[script]
delete-ks name ns:
    just k8s render-local-ks "{{ name }}" "{{ ns }}" | kubectl delete -f -

[doc('Verify Flux prerequisites (flux check --pre)')]
[group('flux')]
[script]
flux-check:
    flux check --pre

[doc('Force a full Flux reconcile: refresh the Git source, then reconcile the cluster-apps root Kustomization.')]
[group('flux')]
[script]
flux-reconcile:
    t0=${SECONDS}
    just log info "Stage: reconcile Git source"
    flux reconcile source git flux-system -n flux-system
    t1=${SECONDS}
    just log info "Reconciled Git source" duration "$((t1-t0))s"
    just log info "Stage: reconcile cluster-apps"
    flux reconcile kustomization cluster-apps -n flux-system
    t2=${SECONDS}
    just log info "Reconciled cluster-apps" duration "$((t2-t1))s"
    just log info "flux-reconcile complete" total "$((t2-t0))s"

[doc('List failed/unknown HelmReleases — JSON-based detection on the Ready condition.')]
[group('flux')]
[script]
list-failed-hrs:
    failed="$(kubectl get hr -A -o json \
      | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status!="True")) | "\(.metadata.namespace)/\(.metadata.name)\t\(.status.conditions[] | select(.type=="Ready") | .status)\t\(.status.conditions[] | select(.type=="Ready") | .reason // "-")"')"
    if [ -z "${failed}" ]; then
      echo "All HRs healthy"
    else
      printf 'NAMESPACE/NAME\tREADY\tREASON\n%s\n' "${failed}" | column -t -s $'\t'
    fi

[doc('Restart all failed HelmReleases (suspend + resume) — JSON-based detection on the Ready=False condition.')]
[group('flux')]
[script]
restart-failed-hrs:
    kubectl get hr -A -o json \
      | jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="False")) | "\(.metadata.namespace) \(.metadata.name)"' \
      | while read -r ns name; do
          flux suspend hr "$name" -n "$ns"
          flux resume hr "$name" -n "$ns"
        done

[doc('Emergency rollback: suspend HR, helm-rollback to previous release, leave suspended. Resume manually after fixing the source.')]
[group('flux')]
[script]
hr-rollback name ns:
    just log info "Suspending HelmRelease" target "{{ ns }}/{{ name }}"
    flux -n "{{ ns }}" suspend helmrelease "{{ name }}"
    just log info "Rolling back to previous release" target "{{ ns }}/{{ name }}"
    helm -n "{{ ns }}" rollback "{{ name }}"
    just log info "Rollback complete — HR stays suspended" hint "fix the source, then: flux -n {{ ns }} resume hr {{ name }}"

# === debug ===

[doc('Open a debug Alpine shell with a PVC mounted (default mountpath=/mnt; pod auto-removes on exit)')]
[group('debug')]
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

[doc('Open a shell on a node (Alpine, sysadmin profile; debug pod is cleaned up on EXIT — even on Ctrl-C)')]
[group('debug')]
[script]
node-shell node:
    trap 'kubectl delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug --field-selector spec.nodeName={{ node }} --ignore-not-found --wait=false' EXIT
    kubectl debug node/{{ node }} -n default -it --image='mirror.gcr.io/alpine:latest' --profile sysadmin

[doc('Prune pods in Failed, Pending, or Succeeded state')]
[group('debug')]
[script]
prune-pods:
    for phase in Failed Pending Succeeded; do
      kubectl delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true
    done

[doc('Decode and print a Kubernetes Secret (all data keys, base64-decoded; KEY=value lines — no krew plugin needed)')]
[group('debug')]
[script]
view-secret secret ns:
    kubectl get secret -n "{{ ns }}" "{{ secret }}" -o json \
      | jq -r '.data // {} | to_entries[] | "\(.key)=\(.value | @base64d)"'

[private]
[script]
render-local-ks name ns:
    flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ name }}"
