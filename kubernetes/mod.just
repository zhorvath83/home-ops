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

[doc('List Kopia snapshots for a ReplicationSource (rich tabular output with size, files, retention)')]
[script]
list-snapshots rsrc ns="default" source_path="/data" kopia_ns="volsync-system":
    kubectl -n "{{ kopia_ns }}" exec deploy/kopia -- \
      kopia snapshot list "{{ rsrc }}@{{ ns }}:{{ source_path }}" \
        --all \
        --manifest-id \
        --json \
      | jq -r '
          def human_bytes:
            if . >= 1073741824 then ((. / 1073741824 * 10 | floor) / 10 | tostring) + " GiB"
            elif . >= 1048576 then ((. / 1048576 * 10 | floor) / 10 | tostring) + " MiB"
            elif . >= 1024 then ((. / 1024 * 10 | floor) / 10 | tostring) + " KiB"
            else tostring + " B"
            end;
          [
            ["TIME (UTC)", "SNAPSHOT", "SIZE", "FILES", "DIRS", "RETENTION"],
            (
              sort_by(.startTime) | reverse | map([
                (.startTime | sub("\\.[0-9]+Z$"; "Z") | gsub("T"; " ")),
                .id,
                ((.rootEntry.summ.size // .stats.totalSize // 0) | human_bytes),
                ((.rootEntry.summ.files // .stats.fileCount // 0) | tostring),
                ((.rootEntry.summ.dirs // .stats.dirCount // 0) | tostring),
                ((.retentionReason // []) | join(","))
              ])[]
            )
          ]
          | .[]
          | @tsv' \
      | column -t -s $'\t'

[doc('Show VolSync ReplicationSource status (formatted table)')]
[script]
rs-status rsrc ns="default":
    kubectl -n "{{ ns }}" get replicationsource "{{ rsrc }}" -o json \
      | jq -r '
        [
          ["Field", "Value"],
          ["Namespace", (.metadata.namespace // "-")],
          ["ReplicationSource", (.metadata.name // "-")],
          ["Source PVC", (.spec.sourcePVC // "-")],
          ["Repository Secret", (.spec.kopia.repository // .spec.restic.repository // "-")],
          ["Schedule", (.spec.trigger.schedule // "-")],
          ["Last Sync Time", (.status.lastSyncTime // "-")],
          ["Last Manual Sync", (.status.lastManualSync // "-")],
          ["Last Sync Duration", (.status.lastSyncDuration // "-")],
          ["Last Result", (.status.latestMoverStatus.result // "-")],
          ["Synchronizing", (((.status.conditions // []) | map(select(.type == "Synchronizing") | "\(.status) (\(.reason // "-"))") | first) // "-")],
          ["Compression", (.spec.kopia.compression // "-")],
          ["Retention", ("hourly=\(.spec.kopia.retain.hourly // "-") daily=\(.spec.kopia.retain.daily // "-") weekly=\(.spec.kopia.retain.weekly // "-") monthly=\(.spec.kopia.retain.monthly // "-")")]
        ]
        | .[]
        | @tsv' \
      | column -t -s $'\t'

[doc('Trigger a manual KopiaMaintenance run')]
[script]
kopia-maintenance name="kopia-daily-maintenance" ns="volsync-system":
    ts="$(date +%H%M%S)"
    kubectl -n "{{ ns }}" patch kopiamaintenances "{{ name }}" --type merge \
      -p "{\"spec\":{\"trigger\":{\"manual\":\"${ts}\"}}}"
    while true; do
      last_manual_sync="$(kubectl -n {{ ns }} get kopiamaintenances {{ name }} -o jsonpath='{.status.lastManualSync}' 2>/dev/null)"
      if [ "${last_manual_sync}" = "${ts}" ]; then
        break
      fi
      sleep 2
    done
    kubectl -n "{{ ns }}" get kopiamaintenances "{{ name }}" -o yaml

[doc('Show latest VolSync backups per ReplicationSource in a date window with timing and jitter')]
[script]
last-backups date=`date +%Y-%m-%d` start_hour="0" end_hour="23" ns="":
    DATE="{{ date }}" START_HOUR="{{ start_hour }}" END_HOUR="{{ end_hour }}" NAMESPACE="{{ ns }}" python3 - <<'PY'
    import json
    import os
    import re
    import statistics
    import subprocess
    from datetime import datetime
    from zoneinfo import ZoneInfo

    tz = ZoneInfo("Europe/Budapest")
    date = os.environ["DATE"]
    start_hour = int(os.environ["START_HOUR"])
    end_hour = int(os.environ["END_HOUR"])
    namespace = os.environ.get("NAMESPACE", "").strip()
    start_local = datetime.fromisoformat(f"{date}T00:00:00").replace(tzinfo=tz).replace(hour=start_hour)
    end_local = datetime.fromisoformat(f"{date}T00:00:00").replace(tzinfo=tz).replace(hour=end_hour)

    def parse_duration(value: str) -> float:
        total = 0.0
        for amount, unit in re.findall(r"([0-9]+(?:\.[0-9]+)?)(h|m|s)", value or ""):
            total += float(amount) * {"h": 3600, "m": 60, "s": 1}[unit]
        return total

    cmd = ["kubectl", "get", "replicationsources"]
    if namespace:
        cmd += ["-n", namespace]
    else:
        cmd += ["-A"]
    cmd += ["-o", "json"]
    data = json.loads(subprocess.check_output(cmd))

    rows = []
    for item in data.get("items", []):
        status = item.get("status") or {}
        last_sync = status.get("lastSyncTime")
        if not last_sync:
            continue
        utc = datetime.fromisoformat(last_sync.replace("Z", "+00:00"))
        local = utc.astimezone(tz)
        if not (start_local <= local <= end_local):
            continue
        duration = parse_duration(status.get("lastSyncDuration") or "")
        rows.append((
            item["metadata"]["namespace"],
            item["metadata"]["name"],
            local.strftime("%Y-%m-%d %H:%M:%S"),
            f"{duration:.1f}s" if duration else "-",
            status.get("latestMoverStatus", {}).get("result", "-"),
        ))

    if not rows:
        print(f"No backups in window {start_local} – {end_local}")
        raise SystemExit(0)

    rows.sort(key=lambda r: r[2])
    header = ("NAMESPACE", "RS", "LAST SYNC (local)", "DURATION", "RESULT")
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    def fmt_row(cells):
        return "  ".join(str(c).ljust(w) for c, w in zip(cells, widths))
    print(fmt_row(header))
    for r in rows:
        print(fmt_row(r))
    PY

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

[doc('Force a full Flux reconcile: refresh the Git source, then reconcile both root Kustomizations (cluster-vars + cluster-apps)')]
[script]
flux-reconcile:
    flux reconcile source git flux-system -n flux-system
    flux reconcile kustomization cluster-vars -n flux-system
    flux reconcile kustomization cluster-apps -n flux-system

[doc('Verify Flux prerequisites (flux check --pre)')]
[script]
flux-check:
    flux check --pre

[doc('Decode and print a Kubernetes Secret (requires kubectl-view-secret krew plugin)')]
[script]
view-secret ns secret:
    kubectl view-secret -n {{ ns }} {{ secret }}

[doc('Suspend or resume the global VolSync stack (state=suspend|resume) — pauses backup jobs cluster-wide')]
[script]
volsync-state state:
    flux -n volsync-system {{ state }} kustomization volsync
    flux -n volsync-system {{ state }} helmrelease volsync
    kubectl -n volsync-system scale deployment volsync --replicas {{ if state != "suspend" { "1" } else { "0" } }}

[doc('Point-in-time restore into the existing PVC via VolSync Direct copyMethod (previous=N is the snapshot offset, 0=latest). Suspends app, runs restore, resumes.')]
[script]
restore-into ns app previous="0":
    flux -n "{{ ns }}" suspend kustomization "{{ app }}"
    flux -n "{{ ns }}" suspend helmrelease "{{ app }}"
    kubectl -n "{{ ns }}" get deploy,sts -l "app.kubernetes.io/name={{ app }}" -o name \
      | xargs -r -I{} kubectl -n "{{ ns }}" scale {} --replicas=0
    kubectl -n "{{ ns }}" wait pod --for=delete --selector="app.kubernetes.io/name={{ app }}" --timeout=5m || true
    cat <<EOF | kubectl apply --server-side -f -
    apiVersion: volsync.backube/v1alpha1
    kind: ReplicationDestination
    metadata:
      name: {{ app }}-manual
      namespace: {{ ns }}
    spec:
      trigger:
        manual: restore-$(date +%s)
      kopia:
        repository: {{ app }}-volsync-secret
        copyMethod: Direct
        destinationPVC: {{ app }}
        previous: {{ previous }}
        sourceIdentity:
          sourceName: {{ app }}
    EOF
    kubectl -n "{{ ns }}" wait "job/volsync-dst-{{ app }}-manual" --for=create --timeout=120s
    kubectl -n "{{ ns }}" wait "job/volsync-dst-{{ app }}-manual" --for=condition=complete --timeout=120m
    kubectl -n "{{ ns }}" delete replicationdestination "{{ app }}-manual"
    flux -n "{{ ns }}" resume kustomization "{{ app }}"
    flux -n "{{ ns }}" resume helmrelease "{{ app }}"
    flux -n "{{ ns }}" reconcile helmrelease "{{ app }}" --force
    kubectl -n "{{ ns }}" wait pod --for=condition=ready --selector="app.kubernetes.io/name={{ app }}" --timeout=5m

[private]
[script]
render-local-ks ns ks:
    flux-local build ks --namespace "{{ ns }}" --path "{{ kubernetes_dir }}/flux/cluster" "{{ ks }}"
