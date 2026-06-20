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

[doc('Emergency rollback: suspend and rollback HR, leave suspended. Resume manually after fixing the source.')]
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

# === hubble ===
#
# Flow visibility for the CNP egress-shape survey (BM: cnp-per-app-audit).
# Shared filter args — hubble-live captures, hubble-analyze re-slices the same /tmp/hubble-live.jsonl:
#   label      cilium endpoint label, e.g. k8s:app.kubernetes.io/name=bazarr  (empty = cluster-wide / all)
#   verdict    DROPPED | ALLOWED                                              (empty = all)
#   direction  egress | ingress — needs label; egress = app is source, ingress = app is destination

[doc('Hubble healthcheck: relay reachability, TLS, flow-buffer size + flow/s, connected nodes. -P auto port-forwards to kube-system/hubble-relay.')]
[group('observe')]
[script]
hubble-status:
    hubble status -P

[arg('direction', pattern='|egress|ingress')]
[arg('secs', pattern='|[0-9]+')]
[arg('verdict', pattern='|FORWARDED|DROPPED|ALLOWED')]
[doc('Capture live flows for secs (default 60), then summarise. Args: label secs verdict direction (see hubble header).')]
[group('observe')]
[script]
hubble-live label="" secs="60" verdict="" direction="":
    label="{{ label }}"
    secs="{{ secs }}"
    verdict="{{ verdict }}"
    # an empty positional placeholder (e.g. to skip ahead to verdict) falls back to the default window
    [ -n "$secs" ] || secs=60
    # fail fast on the common setup miss (tool absent / mise env not active) instead of waiting out the window for nothing
    command -v hubble >/dev/null 2>&1 || { echo "hubble not found in PATH — is it installed and your mise env active?" >&2; exit 127; }
    # fixed path so hubble-analyze can re-slice the same capture without recapturing; overwritten each run, intentionally not cleaned up
    cap="/tmp/hubble-live.jsonl"
    hpid=""
    # keep the capture file on exit (analyze reads it) — only reap the background observer
    trap 'kill "$hpid" 2>/dev/null || true; pkill -P "$hpid" 2>/dev/null || true' EXIT INT TERM
    if [ -n "$label" ]; then
      hubble observe -P -f -o json -l "$label" > "$cap" &
    else
      hubble observe -P -f -o json > "$cap" &
    fi
    hpid=$!
    if [ -n "$label" ]; then scope="label=$label"; else scope="cluster-wide"; fi
    if [ -n "$verdict" ]; then vdisp="$verdict"; else vdisp="all"; fi
    just log info "Capturing live ${vdisp} flows for ${secs}s — trigger app activity now" scope "$scope"
    sleep "$secs"
    kill "$hpid" 2>/dev/null || true
    wait "$hpid" 2>/dev/null || true
    # grep -c already prints 0 on no match (and exits 1) — keep that 0, do not append another
    nflows="$(grep -c '"flow"' "$cap" 2>/dev/null || true)"
    just log info "Captured ${nflows:-0} flows to ${cap}" window "${secs}s"
    just k8s hubble-analyze "$label" "{{ verdict }}" "{{ direction }}"

[arg('direction', pattern='|egress|ingress')]
[arg('verdict', pattern='|FORWARDED|DROPPED|ALLOWED')]
[doc('Re-slice the last capture with different filters, no recapture. Args: label verdict direction (see hubble header).')]
[group('observe')]
[script]
hubble-analyze label="" verdict="" direction="":
    cap="/tmp/hubble-live.jsonl"
    [ -s "$cap" ] || { echo "no capture at $cap — run 'just k8s hubble-live' first" >&2; exit 1; }
    # -R + fromjson? reads JSONL line-by-line and tolerates a truncated final line if hubble was killed mid-write.
    # awk hash-dedup (one pass, O(unique-tuples) memory) instead of sort|uniq -c — avoids sorting the full raw flow set on long/cluster-wide captures.
    rows="$(jq -R -r --arg lbl "{{ label }}" --arg verdict "{{ verdict }}" --arg dir "{{ direction }}" '
        def src:
          if .source.pod_name then .source.pod_name
          elif ((.source_names // []) | length) > 0 then "fqdn:"+(.source_names[0])
          elif ((.source.labels//[])|any(.=="reserved:kube-apiserver")) then "kube-apiserver"
          elif ((.source.labels//[])|any(.=="reserved:host")) then "host"
          elif ((.source.labels//[])|any(.=="reserved:world")) then "world:"+(.IP.source//"??")
          else "ip:"+(.IP.source//"??") end;
        def dest:
          # l7.dns.query BEFORE pod_name: DNS queries hit coredns (which has a pod_name) — checking pod_name first would mask the resolved FQDN, the primary narrow-world allowlist source
          if (.l7.dns.query // "") != "" then "DNS:"+.l7.dns.query
          elif .destination.pod_name then .destination.pod_name
          elif ((.destination_names // []) | length) > 0 then "fqdn:"+(.destination_names[0])
          elif ((.destination.labels//[])|any(.=="reserved:kube-apiserver")) then "kube-apiserver"
          elif ((.destination.labels//[])|any(.=="reserved:host")) then "host"
          elif ((.destination.labels//[])|any(.=="reserved:world")) then "world:"+(.IP.destination//"??")
          else "ip:"+(.IP.destination//"??") end;
        def port: ((.l4.TCP.destination_port // .l4.UDP.destination_port // .l4.ICMPv4.type // .l4.ICMPv6.type // "?")|tostring);
        def proto: (((.l4 // {})|keys|.[0]) // "?");
        fromjson? | .flow
          | select(if $verdict == "" then true elif $verdict == "ALLOWED" then (.verdict == "FORWARDED" or .verdict == "REDIRECTED") else (.verdict == $verdict) end)
          # non-DROPPED: drop only true reply legs, keep initiating (false) and unknown-direction (null, e.g. UDP/DNS) legs; DROPPED: keep all
          | select(if .verdict == "DROPPED" then true else (.is_reply != true) end)
          # label scope: direction picks the endpoint (egress = app is source, ingress = app is destination); empty dir matches either, like hubble -l
          | select(
              if $lbl == "" then true
              elif $dir == "egress" then ((.source.labels // []) | index($lbl))
              elif $dir == "ingress" then ((.destination.labels // []) | index($lbl))
              else (((.source.labels // []) + (.destination.labels // [])) | index($lbl)) end
            )
          | [.verdict, src, dest, port, proto, (.traffic_direction // "-"), (.drop_reason_desc // "-")]
          | @tsv
      ' "$cap" | awk '{ c[$0]++ } END { for (k in c) print c[k] "\t" k }' | sort -rn)"
    if [ -z "$rows" ]; then
      just log info "No flows matched the filter"
    else
      { printf 'COUNT VERDICT SRC DEST PORT PROTO DIR REASON\n'; printf '%s\n' "$rows"; } | column -t
    fi
