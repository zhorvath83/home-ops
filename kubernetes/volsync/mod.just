set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
[script]
default:
    just -l volsync

[doc('Snapshot a single VolSync ReplicationSource (positional args: ns name)')]
[script]
snapshot ns name:
    kubectl -n "{{ ns }}" patch replicationsources "{{ name }}" --type merge \
      -p '{"spec":{"trigger":{"manual":"'"$(date +%s)"'"}}}'

[doc('Snapshot ALL VolSync ReplicationSources (cluster-wide)')]
[script]
snapshot-all:
    kubectl get replicationsources --no-headers -A | while read -r ns name _; do
      just volsync snapshot "$ns" "$name"
    done

[doc('Wait for a ReplicationDestination to finish synchronizing (positional args: ns name)')]
[script]
wait-rd ns name:
    kubectl -n "{{ ns }}" wait --for=condition=Synchronizing=False --timeout=30m replicationdestination/"{{ name }}"

[doc('Trigger the always-on bootstrap restore for an app (positional args: app [ns=default])')]
[script]
restore app ns="default":
    kubectl -n "{{ ns }}" patch replicationdestination "{{ app }}-bootstrap" --type merge \
      -p '{"spec":{"trigger":{"manual":"restore-once"}}}'
    just volsync wait-rd "{{ ns }}" "{{ app }}-bootstrap"

[doc('Point-in-time restore into the existing PVC via VolSync Direct copyMethod (positional args: ns app [previous=0] [ks=app]).')]
[script]
restore-into ns app previous="0" ks="":
    ks="{{ ks }}"; [ -z "${ks}" ] && ks="{{ app }}"
    flux -n "{{ ns }}" suspend kustomization "${ks}"
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
    flux -n "{{ ns }}" resume kustomization "${ks}"
    flux -n "{{ ns }}" resume helmrelease "{{ app }}"
    flux -n "{{ ns }}" reconcile helmrelease "{{ app }}" --force
    kubectl -n "{{ ns }}" wait pod --for=condition=ready --selector="app.kubernetes.io/name={{ app }}" --timeout=5m

[doc('List Kopia snapshots for a ReplicationSource — rich tabular output (positional args: rsrc [ns=default] [source_path=/data] [kopia_ns=volsync-system])')]
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

[doc('Show VolSync ReplicationSource status (positional args: rsrc [ns=default])')]
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

[doc('Trigger a manual KopiaMaintenance run (positional args: [name=kopia-daily-maintenance] [ns=volsync-system])')]
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

[doc('Show latest backups per ReplicationSource in a date window with timing and jitter (positional args: [date=today] [start_hour=0] [end_hour=23] [ns=all])')]
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

[doc('Suspend or resume the global VolSync stack (state=suspend|resume) — pauses backup jobs cluster-wide')]
[script]
state state:
    flux -n volsync-system {{ state }} kustomization volsync
    flux -n volsync-system {{ state }} helmrelease volsync
    kubectl -n volsync-system scale deployment volsync --replicas {{ if state != "suspend" { "1" } else { "0" } }}
