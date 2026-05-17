set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
[script]
default:
    just -l volsync

[doc('Snapshot a single VolSync ReplicationSource (positional args: rsrc [ns=default])')]
[script]
snapshot rsrc ns="default":
    kubectl -n "{{ ns }}" patch replicationsources "{{ rsrc }}" --type merge \
      -p '{"spec":{"trigger":{"manual":"'"$(date +%s)"'"}}}'

[doc('Snapshot ALL VolSync ReplicationSources (cluster-wide)')]
[script]
snapshot-all:
    kubectl get replicationsources --no-headers -A | while read -r ns name _; do
      just volsync snapshot "$name" "$ns"
    done

[doc('Wipe the PVC and restore it from a Kopia snapshot (positional args: rsrc [previous=0] [ns=default]). previous=0 = latest.')]
[script]
restore rsrc previous="0" ns="default":
    flux -n "{{ ns }}" suspend kustomization "{{ rsrc }}"
    flux -n "{{ ns }}" suspend helmrelease "{{ rsrc }}"
    kubectl -n "{{ ns }}" get deploy,sts -l "app.kubernetes.io/name={{ rsrc }}" -o name \
      | xargs -r -I{} kubectl -n "{{ ns }}" scale {} --replicas=0
    kubectl -n "{{ ns }}" wait pod --for=delete --selector="app.kubernetes.io/name={{ rsrc }}" --timeout=5m || true
    cat <<EOF | kubectl apply --server-side -f -
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: {{ rsrc }}-wipe
      namespace: {{ ns }}
    spec:
      ttlSecondsAfterFinished: 60
      backoffLimit: 0
      template:
        spec:
          restartPolicy: Never
          securityContext:
            runAsUser: 0
            runAsGroup: 0
            fsGroup: 0
          containers:
            - name: wipe
              image: docker.io/library/alpine:latest
              command: ["sh", "-c", "find /data -mindepth 1 -delete"]
              volumeMounts:
                - name: target
                  mountPath: /data
          volumes:
            - name: target
              persistentVolumeClaim:
                claimName: {{ rsrc }}
    EOF
    kubectl -n "{{ ns }}" wait "job/{{ rsrc }}-wipe" --for=condition=complete --timeout=10m
    kubectl -n "{{ ns }}" delete job "{{ rsrc }}-wipe"
    cat <<EOF | kubectl apply --server-side -f -
    apiVersion: volsync.backube/v1alpha1
    kind: ReplicationDestination
    metadata:
      name: {{ rsrc }}-manual
      namespace: {{ ns }}
    spec:
      trigger:
        manual: restore-$(date +%s)
      kopia:
        repository: {{ rsrc }}-volsync-secret
        copyMethod: Direct
        destinationPVC: {{ rsrc }}
        previous: {{ previous }}
        sourceIdentity:
          sourceName: {{ rsrc }}
    EOF
    kubectl -n "{{ ns }}" wait "job/volsync-dst-{{ rsrc }}-manual" --for=create --timeout=120s
    kubectl -n "{{ ns }}" wait "job/volsync-dst-{{ rsrc }}-manual" --for=condition=complete --timeout=120m
    kubectl -n "{{ ns }}" delete replicationdestination "{{ rsrc }}-manual"
    flux -n "{{ ns }}" resume kustomization "{{ rsrc }}"
    flux -n "{{ ns }}" resume helmrelease "{{ rsrc }}"
    flux -n "{{ ns }}" reconcile helmrelease "{{ rsrc }}" --force
    kubectl -n "{{ ns }}" wait pod --for=condition=ready --selector="app.kubernetes.io/name={{ rsrc }}" --timeout=5m

[doc('List Kopia snapshots for a ReplicationSource — rich tabular output (positional args: rsrc [ns=default])')]
[script]
list-snapshots rsrc ns="default":
    kubectl -n volsync-system exec deploy/kopia -- \
      kopia snapshot list "{{ rsrc }}@{{ ns }}:/data" \
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

[doc('Trigger a manual KopiaMaintenance run on the cluster-wide kopia-daily-maintenance CR')]
[script]
kopia-maintenance:
    ts="$(date +%H%M%S)"
    kubectl -n volsync-system patch kopiamaintenances kopia-daily-maintenance --type merge \
      -p "{\"spec\":{\"trigger\":{\"manual\":\"${ts}\"}}}"
    while true; do
      last_manual_sync="$(kubectl -n volsync-system get kopiamaintenances kopia-daily-maintenance -o jsonpath='{.status.lastManualSync}' 2>/dev/null)"
      if [ "${last_manual_sync}" = "${ts}" ]; then
        break
      fi
      sleep 2
    done
    kubectl -n volsync-system get kopiamaintenances kopia-daily-maintenance -o yaml

[doc('Show latest snapshots per ReplicationSource for a given date (positional arg: [date=today])')]
[script]
last-snapshots date=`date +%Y-%m-%d`:
    DATE="{{ date }}" python3 - <<'PY'
    import json
    import os
    import re
    import subprocess
    from datetime import datetime, timedelta
    from zoneinfo import ZoneInfo

    tz = ZoneInfo("Europe/Budapest")
    date = os.environ["DATE"]
    start_local = datetime.fromisoformat(f"{date}T00:00:00").replace(tzinfo=tz)
    end_local = start_local + timedelta(days=1)

    def parse_duration(value: str) -> float:
        total = 0.0
        for amount, unit in re.findall(r"([0-9]+(?:\.[0-9]+)?)(h|m|s)", value or ""):
            total += float(amount) * {"h": 3600, "m": 60, "s": 1}[unit]
        return total

    data = json.loads(subprocess.check_output(
        ["kubectl", "get", "replicationsources", "-A", "-o", "json"]))

    rows = []
    for item in data.get("items", []):
        status = item.get("status") or {}
        last_sync = status.get("lastSyncTime")
        if not last_sync:
            continue
        utc = datetime.fromisoformat(last_sync.replace("Z", "+00:00"))
        local = utc.astimezone(tz)
        if not (start_local <= local < end_local):
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
        print(f"No backups on {date}")
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

[arg('action', pattern='suspend|resume')]
[doc('Suspend or resume the global VolSync stack (action=suspend|resume) — pauses backup jobs cluster-wide')]
[script]
state action:
    flux -n volsync-system {{ action }} kustomization volsync
    flux -n volsync-system {{ action }} helmrelease volsync
    kubectl -n volsync-system scale deployment volsync --replicas {{ if action != "suspend" { "1" } else { "0" } }}
