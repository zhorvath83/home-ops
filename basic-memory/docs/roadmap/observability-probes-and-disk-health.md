---
title: observability-probes-and-disk-health
type: roadmap
permalink: home-ops/docs/roadmap/observability-probes-and-disk-health
topic: Add blackbox-exporter (active probes, DONE) and smartctl-exporter (disk health,
  pending)
status: proposed
priority: medium
scope: 'Two independent exporters. Stage 1 (blackbox-exporter — active HTTP/TCP/DNS/ICMP
  probes) is DONE: delivered as phase P4 of docs/progress/grafana-operator-migration,
  live at kubernetes/apps/observability/blackbox-exporter/. Stage 2 (smartctl-exporter
  — SMART attribute scraping on the PC801/PC711 NVMe pair) is PENDING; delivery approach
  decided 2026-08-01 (community prometheus-smartctl-exporter chart). Live testing
  settled the privilege question: privileged: true is mandatory, so the only remaining
  choice is whether to postRender away the unused ServiceAccount token.'
rationale: 'Stage 1 rationale is spent — active probing exists. Stage 2 stands: the
  PC801/PC711 NVMe pair is the single hardware failure boundary (etcd + every PVC),
  and node-exporter exposes no SMART attributes, so wear/media-error/critical-warning
  are the only early-warning signals available. Talos exposes no native SMART path
  (upstream siderolabs/talos#11239 open), so a privileged pod is the only route to
  that telemetry.'
options:
- 'Stage 2 delivery: community prometheus-smartctl-exporter chart — DECIDED 2026-08-01'
- 'Stage 2 privilege posture: privileged: true is unavoidable (live-tested); remaining
  choice is ship as-is vs postRenderer dropping the SA token + rbac.create false'
related_areas:
- observability
- talos-cluster
---

# Add blackbox-exporter (active probes) and smartctl-exporter (disk health)

## Metadata (observation-form, schema validation)

- [topic] Add blackbox-exporter (active probes, DONE) and smartctl-exporter (disk health, pending)
- [status] proposed
- [priority] medium
- [assessed] 2026-08-01 — currency review; Stage 1 found already delivered, Stage 2 approach decided and live-tested

## Stage 1 — blackbox-exporter (DONE)

Delivered as phase **P4** of [[grafana-operator-migration]], not as a separate work item — which
is why no `docs/progress/blackbox-exporter` note exists. Already recorded as an observation in
[[observability]].

- [evidence] Live app tree: `kubernetes/apps/observability/blackbox-exporter/` — `ks.yaml` plus
  `app/` with `ocirepository.yaml` (chart `prometheus-blackbox-exporter` 11.16.0),
  `helmrelease.yaml`, `probes.yaml`, `prometheusrule.yaml`, `grafanadashboard.yaml`,
  `ciliumnetworkpolicy.yaml`, `kustomization.yaml`.
- [evidence] `flux -n observability get ks blackbox-exporter` → Ready True, applied revision
  `refs/heads/main@sha1:00855145`.
- [evidence] Live `Probe` CRs: `devices` (icmp → nas.lan), `nfs` (tcp_connect → nas.lan:2049).
- [evidence] `BlackboxProbeFailed` alert (`probe_success == 0`) routes to Alertmanager → Pushover.
- [evidence] `probe_success` is consumed beyond alerting: it backs a prometheus-adapter External
  Metrics rule driving an HPA — see [[prometheus-adapter]] and [[nfs-dependency-zeroscaler]].

The Stage 1 scope in the original plan is therefore fully superseded, and the plan's original
recommended order (smartctl first, blackbox second) was inverted in practice.

## Stage 2 — smartctl-exporter (PENDING)

- [decision] Delivery approach: the community **`prometheus-smartctl-exporter`** Helm chart,
  following the already-merged blackbox-exporter delivery shape. Decided with the human
  2026-08-01. Rejected alternatives: a bespoke privileged CronJob writing into node-exporter's
  textfile collector (same capability, shorter duty cycle, but self-maintained privileged code
  with no Renovate coverage), and not deploying at all.
- [reference] bjw-s-labs/home-ops `kubernetes/apps/observability/smartctl-exporter/` studied
  file-by-file as the reference implementation; deltas against our conventions resolved in favour
  of the blackbox-exporter shape (our `ks.yaml` `commonMetadata`/`dependsOn`/`timeout`, lowercase
  `prometheusrule.yaml`, existing `folderRef: observability` instead of a new `GrafanaFolder`,
  explicit resources, no CNP file since the exporter needs no egress).

### Live test results (2026-08-01) — the privilege question is settled

Six short-lived test pods on `k8s-cp0` using `quay.io/prometheuscommunity/smartctl-exporter:v0.14.0`
(all deleted afterwards). Decisive outcome:

- [evidence] **`privileged: true` is unavoidable.** With `privileged: false`, `runAsUser: 0`,
  `drop: ALL`, `add: SYS_RAWIO` and the host `/dev` bind-mounted, `smartctl -d nvme -a /dev/nvme0`
  fails with `Smartctl open device: /dev/nvme0 failed: Operation not permitted`. Identical failure
  with no capabilities at all. `CapEff` confirmed `0x20000` (CAP_SYS_RAWIO) in the SYS_RAWIO run,
  so the capability was genuinely present.
- [evidence] The blocker is the **container device cgroup**, not a capability: the hostPath mount
  supplies the device *nodes* (`ls -l /dev/nvme*` lists them, and `smartctl --scan` even discovers
  both drives by name), but `open()` on the char device is denied. Only `privileged: true` sets the
  device cgroup to allow-all; Kubernetes has no per-device grant without a device plugin.
- [evidence] With `privileged: true` the same image reads both drives fine — so the chart's
  hardcoded `privileged: true` + `runAsUser: 0` is a genuine requirement, not chart laziness.
- [observation] **Device mapping (was unknown, now measured, and it is counter-intuitive):**
  `/dev/nvme0` = **PC711** (data disk, all PVCs), serial `KDA8N47141100896P`, NVMe 1.3.
  `/dev/nvme1` = **PC801** (Talos OS + etcd), serial `SJBAN46291390A74W`, NVMe 1.4.
  Both also appear as `/dev/nvmeXn1` namespace block devices, which smartctl reads equally well.
- [conclusion] The only remaining posture choice is: ship the chart as-is, or ship it with a
  postRenderer that drops the automounted ServiceAccount token and sets `rbac.create: false`
  (the exporter needs no Kubernetes API access at all). Full privilege reduction is off the table.

### Measured SMART baseline (2026-08-01, taken before deploy)

Both drives are healthy, so **no alert in the planned set fires on day one** — the rules go live quiet:

| metric | PC711 /dev/nvme0 (data PVCs) | PC801 /dev/nvme1 (Talos OS + etcd) |
|---|---|---|
| SMART overall self-assessment | PASSED | PASSED |
| percentage_used (wear) | 0% | 1% |
| available_spare / threshold | 100% / 50% | 100% / 50% |
| media and data integrity errors | 0 | 0 |
| critical_warning | 0x00 | 0x00 |
| temperature | 51 C | 53 C |
| data units written | 43.9 TB | 6.07 TB |
| power on hours | 14254 | 2067 |

### Implementation state (2026-08-01)

Files written in the working tree, **since committed and deployed** (pushing to `main` is what deploys, since
Flux watches `refs/heads/main`). All commits are pushed and live — see Deployment outcome below:

- [file] `kubernetes/apps/observability/smartctl-exporter/ks.yaml` — blackbox shape:
  `commonMetadata`, `dependsOn: kube-prometheus-stack`, `timeout: 5m`, `wait: false`.
- [file] `.../app/ocirepository.yaml` — chart `prometheus-smartctl-exporter` tag `0.17.1`.
- [file] `.../app/helmrelease.yaml` — `config.device_include: /dev/nvme.*`, `rbac.create: false`,
  resources, `podLabels.ingress.home.arpa/allow-prometheus`, ServiceMonitor with `instance`
  relabeled to the node name, `prometheusRules.enabled: false`, plus the postRenderer.
- [file] `.../app/prometheusrule.yaml` — 9 alerts; `SmartctlInterfaceSlow` kept at `warning`.
- [file] `.../app/grafanadashboard.yaml` — dashboard 22604 rev 3, `inputName: DS_PROMETHEUS`,
  `folderRef: observability`.
- [file] `.../app/kustomization.yaml`; and `kubernetes/apps/observability/kustomization.yaml`
  gained `./smartctl-exporter/ks.yaml` between blackbox-exporter and prometheus-adapter.

- [observation] `postRenderers` is an established local pattern, not a new one — three precedents
  drop the SA token the same way: `kubernetes/apps/crowdsec/crowdsec/app/helmrelease.yaml:193`,
  `kubernetes/apps/crowdsec/bouncer/app/helmrelease.yaml:73`,
  `kubernetes/apps/external-secrets/onepassword-connect/app/helmrelease.yaml:45`.
- [evidence] Independent verification (not the implementer's word): `helm template` with our exact
  values renders `DaemonSet/smartctl-exporter-0` — matching the postRenderer target verbatim —
  with resources applied, `ServiceAccount` present and **zero** `RoleBinding` (`rbac.create: false`
  works). Feeding that rendered DaemonSet through `kustomize build` with the same patch yields
  `automountServiceAccountToken: false` while `privileged: true` stays intact.
- [evidence] `yamllint` exit 0; `kustomize build` OK on both the app dir and
  `kubernetes/apps/observability`; `pre-commit` — all 15 applicable hooks Passed.
- [evidence] `datasourceName: Prometheus` matches the live `GrafanaDatasource` `prometheus`
  (`spec.datasource.name: Prometheus`), so the dashboard binds.
- [caveat] `flux-local` does **not** apply HelmRelease postRenderers, so a flux-local render can
  never show `automountServiceAccountToken` — the deployed crowdsec postRenderer is equally absent
  from its output. The kustomize verification above is the real proof.

### Verified facts (2026-08-01, evidence-backed)

- [observation] Chart `oci://ghcr.io/prometheus-community/charts/prometheus-smartctl-exporter`
  exists; `0.17.1` is the newest tag (ghcr registry tag list), app version v0.14.0, port 9633.
- [observation] The chart **hardcodes** its privilege posture in `templates/daemonset.yaml`:
  `privileged: true` + `runAsUser: 0` (lines 67-69) and a whole-`/dev` hostPath (lines 87-89).
  `values.yaml` exposes **no** `securityContext`, `capabilities` or hostPath override, and the
  pod spec does not set `automountServiceAccountToken`.
- [observation] `config.device_include: /dev/nvme.*` limits which devices smartctl **probes**,
  not what the pod can **see**. It is the correct filter regardless of `/dev/nvmeN` ordering,
  which is not pinned by the machineconfig (disks are selected by model at
  `kubernetes/talos/nodes/k8s-cp0.yaml.j2:8-32`).
- [observation] Pod Security Admission enforces **nothing** on this cluster: a
  privileged+hostNetwork+hostPID pod was admitted by server-side dry-run in both `observability`
  and `default`; node-exporter already runs `hostNetwork`/`hostPID`/hostPath `/` in the
  unlabeled `observability` namespace. So Stage 2 needs no new namespace and no PSA label. This
  matches the rationale already recorded in [[AD-024-crowdsec-namespace-psa-exception]] and is
  exactly what [[pod-security-admission-enforcement]] proposes to change — if that item lands,
  this exporter will need an explicit exception.
- [observation] Talos exposes no native SMART path: `talosctl get disks`/`blockdevices` give
  inventory only, dmesg gives post-hoc kernel errors. Upstream feature request
  siderolabs/talos#11239 is open. There is no privileged-pod-free route to SMART telemetry.
- [observation] Grafana dashboard **22604** ("SMARTctl Exporter Dashboard", uid `ce8j0dmrrej9cc`,
  revision 3 = latest) declares its datasource input as `DS_PROMETHEUS` — **not** the
  `DS_SIGNCL-PROMETHEUS` our blackbox board uses, so the `datasources` stanza must not be copied
  from blackbox. It panels `percentage_used`, `media_errors` and `critical_warning`, but
  **not** `available_spare`/`_threshold` — that alert will fire with no built-in panel.

### The one genuinely new risk

This would be the **first workload with raw block-level ioctl access to the PC801 OS+etcd disk**.
The privileged-pod capability class is already precedented on this single node — `privileged: true`
in `kubernetes/apps/kube-system/intel-gpu-resource-driver/app/helmrelease.yaml:17`, `SYS_ADMIN` in
`kubernetes/apps/kube-system/cilium/app/helmrelease.yaml:101,111`, and a hostPath over the whole
PC711 PVC dataset in `kubernetes/apps/kube-system/democratic-csi/app/helmrelease.yaml:94` — but
none of those reach PC801 at the block layer. Note that `device_include` cannot mitigate this:
the pod sees all of `/dev` regardless, so the filter is scoping, not a security boundary.

### Remaining open question

- [question] Keep or drop the `SmartctlInterfaceSlow` alert (noisy on NVMe power-state changes,
  and low value for consumer drives).

### Planned alert set (metric names verified against the exporter's EXAMPLE.md)

`smartctl_device_media_errors != 0` and `smartctl_device_critical_warning != 0` (critical),
`smartctl_device_smart_status != 1` / `smartctl_device_status != 1` (critical),
`smartctl_device_available_spare_threshold > smartctl_device_available_spare` (critical),
`smartctl_device_percentage_used > 80` (warning) and `> 90` (critical),
`smartctl_device_temperature{temperature_type="current"} > 70` (warning) and `> 80` (critical).
The wear alerts are a deliberate addition — neither the chart nor bjw-s ships them, and
`percentage_used` is the single most useful consumer-NVMe failure-prediction signal.

## Related

- relates_to [[observability]]
- relates_to [[talos-cluster]]
- relates_to [[pushover-provider-model-unify]]
- relates_to [[alertmanager-introduction]]
- relates_to [[grafana-operator-migration]]
- relates_to [[prometheus-adapter]]
- relates_to [[pod-security-admission-enforcement]]

## Deployment outcome (2026-08-01) — live and verified

Stage 2 is **deployed**. Four commits on `main`:

- [commit] `7c2101b9c` ✨ feat(observability): add smartctl-exporter for NVMe SMART health (7 files)
- [commit] `d3809ddec` 📝 docs(roadmap): close blackbox half, record smartctl-exporter plan
- [commit] `3a08e7e07` 🐛 fix(observability): match smartctl device filter on bare device name
- [commit] `ddfc59969` ♻️ refactor(observability): drop smartctl alerts on nonexistent metrics

### The gotcha that only live verification caught

- [gotcha] **`device_include` matches the BARE device name, not the `/dev/` path.** The first deploy
  was fully green — Kustomization Ready, HelmRelease `Helm install succeeded`, pod Running 1/1,
  scrape target `up = 1` — and collected **nothing**. Pod log: `msg="Ignoring device" name=nvme0`,
  `name=nvme1`, `msg="Number of devices found" count=0`. smartctl_exporter v0.14.0 matches
  `--smartctl.device-include` against `nvme0`/`nvme1`, so `/dev/nvme.*` matched zero devices. The
  chart's own `values.yaml` comment (`device_include: /dev/sd.*`) is misleading for this version.
  Fixed to `nvme.*` in `3a08e7e07` → `msg="Found device" name=nvme0`, `name=nvme1`, `count=2`.
  **Neither `kustomize build`, nor `pre-commit`, nor `helm template` can catch this class of bug** —
  only reading the exporter's own log after deploy does.
- [gotcha] Two alerts referenced metrics the exporter does **not** expose for NVMe:
  `smartctl_device_interface_speed` and `smartctl_device_status` both return `count = 0` live. The
  `SmartctlInterfaceSlow` alert was therefore vacuous and the `or smartctl_device_status != 1` half
  of `SmartctlSmartStatusFailed` was dead. Removed in `ddfc59969`; 8 real alerts remain.
- [observation] The 16 series the exporter DOES expose: `available_spare`,
  `available_spare_threshold`, `block_size`, `bytes_read`, `bytes_written`, `capacity_blocks`,
  `capacity_bytes`, `critical_warning`, `media_errors`, `num_err_log_entries`, `percentage_used`,
  `power_cycle_count`, `power_on_seconds`, `smart_status`, `smartctl_exit_status`, `temperature`.

### Live verification evidence

- [evidence] `flux -n observability get ks smartctl-exporter` → Ready, `refs/heads/main@sha1:ddfc5996`.
- [evidence] HelmRelease → `Helm upgrade succeeded … v2`, chart `prometheus-smartctl-exporter@0.17.1`.
- [evidence] **The postRenderer works in the real cluster**: the live DaemonSet has
  `automountServiceAccountToken=false` while `privileged=true`, and the running pod's volumes are
  only `dev` + `k8tz` — **no `kube-api-access` token volume**. Zero RoleBindings in the namespace.
- [evidence] Metrics land with `instance="k8s-cp0"` (the ServiceMonitor relabeling works) and
  `device="nvme0"`/`"nvme1"`; values match the pre-deploy baseline exactly (wear 0/1, temp 50/52 C,
  media_errors 0/0).
- [evidence] `prometheus_rule_group_rules{rule_group=~".*smartctl.*"}` → **8**, with
  `prometheus_rule_evaluation_failures_total` → **0**. No `Smartctl*` alert is firing.
- [evidence] `GrafanaDashboard/smartctl-exporter` → `DashboardSynchronized=True`,
  "Dashboard was successfully applied to 1 instances".
