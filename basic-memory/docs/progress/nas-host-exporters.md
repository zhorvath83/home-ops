---
title: nas-host-exporters
type: note
permalink: home-ops/docs/progress/nas-host-exporters
tags:
- progress
- observability
- nas
- smartctl
- node-exporter
---

# NAS host exporters wired into the cluster Prometheus

## Metadata (observation-form, schema validation)

- [topic] smartctl_exporter + node_exporter installed on the OMV NAS host and scraped by the cluster Prometheus, with an ATA/SATA alert group on the Alertmanager/Pushover plane
- [status] done
- [closed] 2026-08-01
- [priority] high
- [roadmap] merged into this note — docs/roadmap/nas-host-exporters deleted on closure (2026-08-01)

## Execution model

- [decision] Delivery: direct commits to main, matching repo norm. Deploy happens on push (Flux watches refs/heads/main).
- [decision] Maestro/worker split: the manifest and rule authoring was delegated to a local Ollama-hosted agent (glm-5.2:cloud) in three scoped briefs; every artifact was reviewed line-by-line and every validation re-run independently by the Maestro before commit. One real defect was found this way (see Review findings).
- [decision] The OMV Ansible codification was deliberately NOT built in this session — just omv install still references a playbooks/site.yml + inventory/hosts.yml pair that does not exist (Phase 10). Host install stayed imperative and is documented below instead.
- [decision] The Grafana ATA dashboard was deferred to a follow-up rather than introducing a new repo convention mid-item (see Grafana coverage).

## What was delivered

### Host side (nas.lan, 192.168.1.10) — imperative, not yet codified

- [delivered] prometheus-smartctl-exporter 0.14.0-2~bpo13+1 installed from trixie-backports (apt-get install -t trixie-backports). Same upstream version as the in-cluster image, so metric shape is identical across both exporters.
- [delivered] prometheus-node-exporter 1.9.0-1+b4 from trixie main.
- [delivered] No exporter flag overrides. Defaults are correct: auto-scan, -d sat inherited from the scan, --nocheck=standby, 60 s interval, :9633.
- [delivered] smartd left running as an independent out-of-band second opinion.
- [evidence] Both systemd units active, listening on *:9633 and *:9100. Verified from the Mac over the LAN, which also proves external reachability.

Exact commands, for the Ansible follow-up:

    sudo apt-get install -y -t trixie-backports prometheus-smartctl-exporter
    sudo apt-get install -y prometheus-node-exporter

### Cluster side (GitOps)

- [delivered] kube-prometheus-stack/app/scrapeconfigs/nas-smartctl.yaml — ScrapeConfig, jobName nas-smartctl, target ${NAS_IP}:9633, relabeling instance -> nas, ^go_.* dropped. Commit 8a690647e.
- [delivered] kube-prometheus-stack/app/scrapeconfigs/nas-node.yaml — same shape, jobName nas-node, ${NAS_IP}:9100. Commit 8a690647e.
- [delivered] The prometheus CiliumNetworkPolicy gained one egress entry: 192.168.1.10/32 ports 9633 + 9100. The 192.168.1.1/32 openwrt grant untouched. Commit 8a690647e.
- [delivered] smartctl-exporter/app/prometheusrule.yaml — new group smartctl-exporter-ata with 7 alerts; the two existing NVMe temperature alerts narrowed with job!="nas-smartctl". Commit 323418c8e.
- [delivered] smartctl-exporter/tests/prometheusrule_test.yaml — +279 lines: 7 per-alert blocks, 2 cross-firing blocks, 1 baseline-quiet block. Commit 323418c8e.

## Corrections to the roadmap (measured, not assumed)

- [correction] The roadmap claimed, from reading v0.14.0 source, that mineTemperatures emits one series per temperature JSON key, so op_limit_max=55, limit_max=70 and lifetime_max=50 would all become series. LIVE MEASUREMENT REFUTES THIS: sdb emits ONLY temperature_type="current". The temperature_type="current" matcher was kept anyway as a guard against a future exporter version, but the stated reason in the roadmap was wrong.
- [correction] The roadmap said /dev/sda produces only benign info series. It also produces smartctl_device_temperature{device="sda",temperature_type="current"} 0 and temperature_type="drive_trip" 0. Harmless for a "> 50" rule, but the ATA temperature rules do evaluate against an sda series.
- [confirmed] /dev/sda produces NO attribute series and NO smart_status — all 104 attribute series belong to sdb. The roadmap decision to omit a device filter is therefore correct and is now backed by cluster-side measurement, not just host-side.

## Review findings (verify-don-t-trust)

- [finding] SmartctlAtaPrefailBelowThreshold as first written used on(instance, device, attribute_id). A filter comparison propagates only the grouping labels, so the alert lost BOTH attribute_name and job — a critical page would have said "a prefail SMART attribute failed" with only a numeric attribute_id, and could not be routed by job in Alertmanager. Fixed by extending the matcher to on(job, instance, device, attribute_id, attribute_name) and naming the attribute in the annotations. Safe: for a given attribute_id the value and thresh series share attribute_name, so matching stays one-to-one — verified live, still 10 matched pairs before and after.
- [observation] The worker agent flagged this itself as a "design observation, not a defect". It was a defect. The self-report was treated as a hypothesis and checked, which is why it was caught.

## Live verification (2026-08-01)

- [evidence] up{instance="nas", job="nas-smartctl"} => 1 and up{instance="nas", job="nas-node"} => 1.
- [evidence] smartctl_device_smart_status{device="sdb", instance="nas", job="nas-smartctl"} => 1.
- [evidence] count by (device) (smartctl_device_attribute{job="nas-smartctl"}) => {device="sdb"} 104. No attribute series for sda.
- [evidence] smartctl_device_temperature{job="nas-smartctl"}: sdb current=38, sda current=0, sda drive_trip=0.
- [evidence] node_filesystem_size_bytes shows the 16 TB sdb1 mounted at /export/backups, /export/media, /export/pve-backups, /export/scanner, /export/tmp and the OMV by-uuid path; 1644 node_* series total.
- [evidence] go_* drop works: count({__name__=~"go_.*", job=~"nas-.*"}) returns empty.
- [evidence] Hubble, 75 s live capture: 5 FORWARDED flows from prometheus-kube-prometheus-stack-0 to 192.168.1.10:9633 and 5 to :9100, ZERO DROPPED egress. The empty DROPPED list is meaningful precisely because forwarded traffic to the same host was present in the same capture.
- [evidence] The prefail expression run against LIVE data returns empty. 10 prefail attributes are actually evaluated (thresh > 0), and the narrowest margin is 25 normalized points (Helium_Condition at 100 vs threshold 75). The group is not merely quiet — the distance to firing is quantified.
- [evidence] All other new expressions (Current_Pending_Sector > 0, Offline_Uncorrectable > 0, temperature > 50) return empty against live data.
- [evidence] prometheus_rule_evaluation_failures_total for both smartctl-exporter and smartctl-exporter-ata groups => 0.
- [evidence] count(ALERTS{alertname=~"SmartctlAta.*"}) => 0 after the group loaded.
- [evidence] just k8s test-prom-rules: SUCCESS, 15 rules found (8 NVMe + 7 ATA), all promtool unit tests passed. Re-run independently by the Maestro, not taken from the worker report.
- [evidence] flux -n observability get ks smartctl-exporter and kube-prometheus-stack both Ready True on refs/heads/main@sha1:323418c8.

## Grafana coverage — acceptance criterion only partially met

- [evidence] Dashboard grafana.com 22604 (URL-imported, so not patchable in place) was audited panel by panel against the NAS disk. WORKS: Disk Temperature, Devices, Unhealthy, Disk Lifetime (power_on_seconds, power_cycle_count). DOES NOT WORK: Media Errors and Critical Warnings (NVMe-only metrics the NAS never emits), Total Data Written (Total_LBAs_Written) and Wear Leveling (Wear_Leveling_Count) — both SSD attributes.
- [conclusion] No panel anywhere shows Reallocated_Sector_Ct, Current_Pending_Sector, Offline_Uncorrectable, UDMA_CRC_Error_Count or Helium_Condition — exactly the attributes the new alerts are built on. The criterion "Grafana renders the NAS disk temperature and key attributes" is met for temperature and health, NOT met for the key attributes.
- [observation] There is no precedent in this repo for a self-authored dashboard JSON: every GrafanaDashboard is either a chart-shipped ConfigMap or a grafana.com URL. Introducing a configMapGenerator-based dashboard would be a new convention, so it was deferred rather than improvised mid-item.

## Acceptance criteria

- [criterion] smartctl_device_smart_status{device="sdb"} 1 on the host. PASS.
- [criterion] node_exporter answers on :9100. PASS (1644 node_* series).
- [criterion] Prometheus shows nas-smartctl and nas-node UP with instance="nas". PASS.
- [criterion] CNP contains the 192.168.1.10/32 grant and Hubble shows no DROPPED egress. PASS, with forwarded traffic present in the same capture as the control.
- [criterion] just k8s test-prom-rules passes including the both-exporters and baseline-quiet tests. PASS.
- [criterion] flux get ks Ready True on the new revision. PASS.
- [criterion] Zero alerts firing from the new group 24 h after deploy. PENDING — 0 firing at deploy time and the expressions return empty against live data, but the 24 h window has not elapsed.
- [criterion] Grafana renders the NAS disk temperature and key attributes. PARTIAL — temperature, lifetime and health render; the ATA attributes do not. See Grafana coverage.

## Follow-ups

- [follow-up] Grafana ATA attribute panels. Needs a decision first: introduce a self-authored dashboard JSON convention (configMapGenerator + GrafanaDashboard configMapRef), or find a community ATA dashboard. The grafana.com search API returned nothing usable for smartctl; only direct dashboard IDs resolve.
- [follow-up] Codify both exporter installs in an OMV Ansible playbook. just omv install already points at provision/openmediavault/playbooks/site.yml and inventory/hosts.yml, neither of which exists — the recipe is currently broken regardless of this item.
- [follow-up] Pin the smartctl-exporter package version in that playbook. It comes only from trixie-backports and is outside Renovate reach, so a future backport could change flag names.
- [follow-up] Re-enable the OMV scheduled SMART self-tests. Both jobs are enable: false and the last extended test ran at 11893 power-on hours against 28407 now — roughly 1.9 years. Passive polling cannot find latent unreadable sectors on the parts of the disk that are never read; arguably higher value than any alert in this item.
- [follow-up] Remove the stale WDC WD30EZRX entries from the OMV SMART device config — that drive is not attached.
- [follow-up] Decide whether the smartd e-mail path is retired now that Pushover coverage exists, or kept deliberately as a channel that does not depend on the cluster being healthy.
- [follow-up] Unauthenticated metrics on the LAN: :9633 and :9100 are open with no host firewall, and smartctl_device_info carries the disk model and serial number as labels. Those reach Prometheus and Grafana but never git. Accepted for parity with the openwrt scrape; revisit if the LAN trust boundary changes.

## Related
- relates_to [[observability]]
- relates_to [[prometheus-scrapeconfig-extraction]]
- relates_to [[resticprofile-backup]]
- relates_to [[flux-gitops]]
- relates_to [[networking]]
- continues [[observability-probes-and-disk-health]]
## Update — 2026-08-01: SmartctlAtaTempHigh changed to >= 50 (human decision)

- [decision] The human asked to be alerted AT 50 C, not above it. SmartctlAtaTempHigh is now `>= 50`; the description reads "at or above 50°C" so it is not a lie at the boundary. Commit f8edc8fbd, live-verified in the cluster.
- [decision] SmartctlAtaTempCritical was deliberately left at `> 55`. Only the 50 C boundary was asked for, and touching the critical rule was out of scope. The operator asymmetry between the sibling pair is intentional and was flagged to the human.
- [risk] This partially reverses the original rationale. The drive measured `lifetime_max = 50`, meaning it has ALREADY reached 50 C once in normal service — so `>= 50` may fire on a hot summer day after the 15m for-duration, warning severity, routed to Pushover via the AlertmanagerConfig default receiver. Accepted knowingly. If it becomes noisy the non-destructive lever is a longer `for:` (30-60m, so only sustained heat pages), not a threshold walk-back.
- [observation] The unit test was rewritten to pin the boundary: 49 silent, 50 fires (previously 51, which would have passed under BOTH `> 50` and `>= 50` — a test that could not fail). Under the old operator the new 50-fires assertion would fail, which is the property that makes it a real test.
- [finding] The cross-firing High test block pinned the old annotation string and broke when the rule wording changed, even though its firing behaviour was unaffected. The delegation brief had said that block "must stay exactly as it is", reasoning only about firing behaviour — a Maestro-side brief defect, not a worker error. The worker stopped and escalated instead of either weakening the rule or silently editing a block it had been told not to touch. Only the stale description string was updated.
- [evidence] Live after deploy: expr `smartctl_device_temperature{job="nas-smartctl", temperature_type="current"} >= 50` present in the cluster PrometheusRule; `count(ALERTS{alertname=~"SmartctlAta.*"})` => 0; sdb at 39 C.
- [evidence] just k8s test-prom-rules: 15 rules, all promtool tests pass (re-run independently by the Maestro).


## Design rationale (merged from roadmap, 2026-08-01)

The roadmap note `docs/roadmap/nas-host-exporters` was merged into this progress note on closure and deleted; the durable design rationale and measured baseline below are preserved verbatim. The execution, review, live verification and follow-ups live in the sections above and below; where they differ, those supersede the roadmap.

## Scope

Deliver disk-health and host metrics for the NAS machine (`nas.lan`, `${NAS_IP}` = 192.168.1.10) on the
same alerting plane as the rest of the cluster (Prometheus → Alertmanager → Pushover), by installing
two Debian-packaged exporters on the OMV host and scraping them with `ScrapeConfig` CRs, exactly
following the already-merged `ScrapeConfig/openwrt` pattern.

This item **owns the NAS `node_exporter` scrape outright**, bundling it with the smartctl work — both
exporters live on the same host, need the same Cilium egress grant, the same `app/scrapeconfigs/`
directory, and the same install step. The OpenWRT-only [[prometheus-scrapeconfig-extraction]] item no
longer covers the NAS.

## Decisions (with human, 2026-08-01)

- [decision] **Deliver on the OMV host.** Rationale is measured, not speculative: the 16 TB disk
  already carries 7 reallocated sectors at 28407 power-on hours, holds 12 TB of backup data (81% full),
  and its scheduled SMART self-tests have been disabled for roughly 1.9 years.
- [decision] **Both exporters in one item** — `prometheus-smartctl-exporter` (:9633) and
  `prometheus-node-exporter` (:9100). One Cilium egress patch, one directory, one install step.
- [decision] **No `device-include`/`device-exclude` filter** on the smartctl exporter. Auto-scan is
  correct here and survives device renaming (see the measured evidence for `/dev/sda` below). This
  reverses the initial plan draft.

## Measured baseline (live evidence, 2026-08-01)

All of the following was read from the running host and from the exporter's own source; none of it is assumed.

### Host

- [evidence] `nas.lan`, OpenMediaVault **8.5.1**, Debian 13 (trixie), kernel 7.0.12, amd64, systemd 257,
  up 21 days. It is a **QEMU VM** on the M93p.
- [evidence] `smartmontools 7.4-3` installed; passwordless `sudo` works; `smartctl` lives at `/usr/sbin`.
- [evidence] **No firewall** — `iptables -S` shows `-P INPUT ACCEPT` and the nft ruleset is empty. Nothing
  blocks inbound :9633/:9100; equally, nothing protects them. Port 9633 is free.
- [evidence] `trixie-backports` is an enabled apt source. `prometheus-smartctl-exporter` candidate
  **0.14.0-2~bpo13+1** (backports only, priority 100 → needs `-t trixie-backports`);
  `prometheus-node-exporter` candidate **1.9.0-1+b4** (trixie main).
- [observation] The backports package is upstream **v0.14.0** — the *same* version as the in-cluster
  image `quay.io/prometheuscommunity/smartctl_exporter:v0.14.0`. Metric shape is therefore identical
  across both exporters, which is what makes one shared rule set possible.

### Disks

- [evidence] `/dev/sda` — 16 G QEMU virtual disk (OS root, ext4, 25% used). `smart_support.available = false`.
  **No SMART at all.**
- [evidence] `/dev/sdb` — TOSHIBA MG08ACA16TE, 16 TB, 7200 rpm, helium-sealed enterprise HDD, presented
  to the host over **USB** and addressed by smartctl as `-d sat`. ext4, 15 T, **81% full** (12 T used),
  mounted at `/srv/dev-disk-by-uuid-a9c14a22-…`.
- [evidence] `smartctl --json --scan` returns exactly two devices: `/dev/sda` type `scsi`, `/dev/sdb` type `sat`.
- [evidence] `smart_status.passed = true`, 26 attributes readable, `temperature.current` 37–38 °C.
- [correction] `smartctl -H` prints *"SMART Status not supported: Incomplete response, ATA output
  registers missing"*. This is **not** a defect and **not** a risk: it only means the USB bridge does not
  return ATA output registers for the health command, so smartctl falls back to an attribute-based
  assessment and still emits `smart_status.passed = true`. The OMV GUI shows the same data. The exporter
  will therefore publish `smartctl_device_smart_status = 1` correctly.
- [evidence] **APM level 128** = "minimum power consumption without standby" → the disk **never spins
  down**, so 60 s SMART polling cannot cause head-parking wear or spin-up latency.

### Measured SMART attributes of /dev/sdb (value/thresh, raw)

| id | name | value/thresh | raw | note |
|---|---|---|---|---|
| 1 | Raw_Read_Error_Rate | 100/50 | 0 | prefail |
| 3 | Spin_Up_Time | 100/1 | 7776 | prefail |
| 5 | Reallocated_Sector_Ct | 100/10 | **7** | prefail; non-zero baseline |
| 7 | Seek_Error_Rate | 100/50 | 0 | prefail |
| 9 | Power_On_Hours | 29/0 | 28407 | ~3.24 years |
| 10 | Spin_Retry_Count | 100/30 | 0 | prefail |
| 12 | Power_Cycle_Count | 100/0 | 23 | |
| 23 | Helium_Condition_Lower | 100/75 | 0 | prefail; helium-seal health |
| 24 | Helium_Condition_Upper | 100/75 | 0 | prefail; helium-seal health |
| 191 | G-Sense_Error_Rate | 100/0 | **1** | non-zero baseline |
| 193 | Load_Cycle_Count | 99/0 | 17675 | |
| 194 | Temperature_Celsius | 100/0 | **214749610021** | raw is packed min/max — GARBAGE, unusable |
| 196 | Reallocated_Event_Count | 100/0 | **3** | non-zero baseline |
| 197 | Current_Pending_Sector | 100/0 | 0 | |
| 198 | Offline_Uncorrectable | 100/0 | 0 | |
| 199 | UDMA_CRC_Error_Count | 200/0 | 0 | USB/SATA link integrity |
| 220 | Disk_Shift | 100/0 | **33685505** | vendor-packed — unusable |

- [evidence] Top-level `temperature` JSON: current=37, lifetime_min=19, **lifetime_max=50**,
  power_cycle_min=34, power_cycle_max=48, **op_limit_max=55**, op_limit_min=5, limit_max=70, limit_min=-40.
  The drive publishes its own operating envelope — this is where the thresholds below come from.
- [evidence] Self-test log: last **Extended offline** test completed without error at **11893** power-on
  hours; the drive is now at 28407 → **no self-test in ~16500 hours (~1.9 years)**.

### What already monitors this disk

- [evidence] `smartmontools` (smartd) is **enabled and active** on the host. `/etc/smartd.conf`:
  `DEFAULT -a -o on -S on -T permissive -R 5! -R 197! -U 198+ -W 0,50,55 -n standby,q`, monitoring the
  Toshiba by `by-id` path, alerting by **e-mail** to a `pomail.net` address via `mail-eu.smtp2go.com`.
- [evidence] OMV config `conf.service.smartmontools`: `enable: true`, `interval: 1800`,
  `powermode: standby`, global `tempmax: 50`; per-device entry for the USB Toshiba has `tempmax: 45`,
  `tempdiff: 10`. Both scheduled self-test jobs (`type: S` and `type: L`) are `enable: false`.
- [conclusion] The gap this item closes is **not** "the disk is unmonitored" — it is that the existing
  monitoring is **out-of-band**: e-mail only, invisible in Grafana, not routed to Pushover, no history,
  no dashboard, and silently dependent on an SMTP relay nobody checks. Note also that smartd's own
  choices independently corroborate the design below: `-R 5!`/`-R 197!`/`-U 198+` alert on *growth*
  rather than absolute value, and `-W 0,50,55` uses exactly the 50/55 °C thresholds derived here.
- [observation] The OMV SMART config still lists a **WDC WD30EZRX** 3 TB drive that is not attached
  (`lsblk` shows only sda/sdb). Stale config entries — worth cleaning during implementation.

### Exporter behaviour (read from prometheus-community/smartctl_exporter v0.14.0 source)

- [evidence] Scan: `smartctl --json --scan`; a scanned type of `scsi` is rewritten to `auto` (`main.go:143`).
- [evidence] Per-device read (`readjson.go:67`):
  `smartctl --json --info --health --attributes --tolerance=verypermissive --nocheck=standby
  --format=brief --log=error --device=<type> <name>`, every 60 s. The scanned type **is** passed
  through, so `/dev/sdb` is read as `-d sat` automatically — no configuration needed.
- [evidence] `--smartctl.powermode-check` defaults to **`standby`**, so a sleeping disk is skipped by
  default. Combined with APM=128 this question is closed twice over.
- [evidence] `buildDeviceLabel` (`smartctl.go:45-55`) strips the `/dev/` prefix → the `device` label value
  is **`sdb`**, *not* `/dev/sdb`. Any rule matching `device=~"/dev/sd.*"` would match nothing.
- [evidence] `smartctl_device_attribute` labels are exactly
  `{device, attribute_name, attribute_flags_short, attribute_flags_long, attribute_value_type, attribute_id}`
  with `attribute_value_type` ∈ `value|worst|thresh|raw` (`metrics.go:103-116`).
- [evidence] `mineTemperatures` (`smartctl.go:276-291`) emits one
  `smartctl_device_temperature{temperature_type=<key>}` series for **every** key of the temperature JSON
  — so `op_limit_max=55`, `limit_max=70`, `lifetime_max=50` all become series. Every temperature rule
  **must** keep the `temperature_type="current"` matcher; the existing NVMe rules already do.
- [evidence] `mineSmartStatus` (`smartctl.go:470-480`) is guarded by `if smartStatus.Exists()`.

### The /dev/sda question — settled empirically

Reproducing the exporter's exact command against both disks:

| device | exit_status | error messages | smart_status | attributes |
|---|---|---|---|---|
| `/dev/sda` (`-d auto`) | 0 | none | **absent** | absent |
| `/dev/sdb` (`-d sat`) | 0 | none | present, passed=true | 26 |

- [conclusion] `/dev/sda` yields **no** `smartctl_device_smart_status` series (the `Exists()` guard) and no
  attribute series, so the existing global `SmartctlSmartStatusFailed` (`smart_status != 1`) **cannot**
  fire on it. Only benign info series are produced. A device filter is therefore unnecessary; omitting
  it keeps the config robust across device renaming.

## Design

### Host side (imperative, on nas.lan)

1. `apt-get install -t trixie-backports prometheus-smartctl-exporter` and
   `apt-get install prometheus-node-exporter`; both ship systemd units and enable on install.
2. No exporter flag overrides for smartctl (defaults are correct: auto-scan, `-d sat` from scan,
   `--nocheck=standby`, 60 s interval, :9633).
3. Leave smartd running — it stays as an independent, out-of-band second opinion.
4. Codify both installs in the OMV Ansible playbook (`provision/openmediavault/playbooks/`, not yet
   present) so any host rebuild reproduces them.

### Cluster side (GitOps, under kubernetes/apps/observability/kube-prometheus-stack/app/)

1. `scrapeconfigs/nas-smartctl.yaml` — `ScrapeConfig`, `spec.jobName: nas-smartctl`,
   `staticConfigs.targets: ["${NAS_IP}:9633"]`, `relabelings` rewriting `instance` → `nas`,
   `metricRelabelings` dropping `^go_.*` (mirrors `ScrapeConfig/openwrt`).
2. `scrapeconfigs/nas-node.yaml` — same shape, `jobName: nas-node`, target `${NAS_IP}:9100`.
3. `ciliumnetworkpolicy.yaml` — extend the existing `kube-prometheus-stack-prometheus` egress with
   `toCIDRSet: 192.168.1.10/32` ports 9633 and 9100. The 192.168.1.1/32:9100 openwrt grant is untouched.
4. `prometheusrules/` — a new ATA/SATA rule group (below) plus a two-line narrowing of the existing
   NVMe temperature alerts.
5. `grafanadashboard.yaml` — verify whether the existing smartctl dashboard (grafana.com 22604) renders
   ATA attributes or is NVMe-only; add an ATA row or a second dashboard if not.

- [observation] `${NAS_IP}` already resolves via the root cluster-apps `postBuild.substituteFrom:
  cluster-settings` patch (`components/common/vars/cluster-settings.yaml:13`) — the same mechanism the
  openwrt scrape uses. `scrapeConfigSelectorNilUsesHelmValues: false` is already set.
- [observation] **No new liveness alert is needed.** `TargetDown` already exists live
  (`observability/kube-prometheus-stack-general.rules`, `for: 10m`, `severity: warning`,
  `100 * (count(up == 0) BY (cluster, job, namespace, service) / count(up) BY (…)) > 10`) and covers
  static `ScrapeConfig` targets, since the grouping degrades gracefully when `namespace`/`service`
  are absent. Adding a per-job `up == 0` rule would be redundant.

### Alert rules — new group `smartctl-exporter-ata`

The design constraint is that **nothing may fire on day one** against the measured baseline, while still
catching real degradation. The non-zero baselines (7 reallocated sectors, 3 reallocated events,
1 G-sense event) make every naive `> 0` rule wrong.

| alert | expr (abbreviated; all use `job="nas-smartctl"`) | for | severity | why it cannot fire today |
|---|---|---|---|---|
| `SmartctlAtaPrefailBelowThreshold` | `smartctl_device_attribute{attribute_value_type="value"} <= on(instance,device,attribute_id) (smartctl_device_attribute{attribute_value_type="thresh"} > 0)` | 15m | critical | every prefail attribute is at value 100 against thresholds of 1–75 |
| `SmartctlAtaReallocatedSectorsGrowing` | `X > min_over_time(X[7d])` where X = `…{attribute_name="Reallocated_Sector_Ct",attribute_value_type="raw"}` | 30m | warning | the series is flat at 7, so it never exceeds its own 7-day minimum |
| `SmartctlAtaPendingSectors` | `…{attribute_name="Current_Pending_Sector",attribute_value_type="raw"} > 0` | 15m | critical | baseline is 0 |
| `SmartctlAtaOfflineUncorrectable` | `…{attribute_name="Offline_Uncorrectable",attribute_value_type="raw"} > 0` | 15m | critical | baseline is 0 |
| `SmartctlAtaCrcErrorsGrowing` | `X > min_over_time(X[7d])` where X = `…{attribute_name="UDMA_CRC_Error_Count",attribute_value_type="raw"}` | 30m | warning | flat at 0; growth-based so a single transient USB-bridge CRC event does not latch forever |
| `SmartctlAtaTempHigh` | `smartctl_device_temperature{job="nas-smartctl",temperature_type="current"} > 50` | 15m | warning | current 37–38 °C |
| `SmartctlAtaTempCritical` | `smartctl_device_temperature{job="nas-smartctl",temperature_type="current"} > 55` | 15m | critical | current 37–38 °C |

- [decision] **One generic prefail rule instead of six per-attribute rules.** SMART's own
  normalized-value-vs-threshold mechanism is exactly the "is this attribute failing" signal, and only
  prefail attributes carry a non-zero threshold — so `thresh > 0` is a sufficient and self-maintaining
  filter. This single rule subsumes Raw_Read_Error_Rate, Seek_Error_Rate, Spin_Retry_Count,
  Spin_Up_Time, the *normalized* Reallocated_Sector_Ct, **and both Helium_Condition attributes**
  (thresh 75 — the correct way to catch helium-seal loss, which is the signature failure mode of this
  drive class). It also automatically covers any future disk without a rule change.
- [decision] **Temperature thresholds 50 / 55 °C**, not the NVMe 70 / 80. Justified by three independent
  sources agreeing: the drive's own `op_limit_max = 55`; the host's existing smartd `-W 0,50,55`; and the
  measured `lifetime_max = 50`, which proves the drive has already reached 50 °C in normal service, so
  anything at or below 50 would be a recurring false alarm.
- [decision] Narrow the two existing NVMe temperature alerts with `job!="nas-smartctl"`. Without it an
  HDD above 70 °C would fire both the ATA and the NVMe rule. Two lines, no behaviour change for NVMe.
- [decision] Growth is expressed as `X > min_over_time(X[7d])`, **not** `increase()`/`delta()`.
  `smartctl_device_attribute` is a gauge; `increase()`/`delta()` apply counter-reset correction and
  edge extrapolation that are meaningless here. The `min_over_time` form is self-baselining, needs no
  hard-coded magic number, and stays correct if the drive is ever replaced.

### promtool unit tests

Follow the existing suite at `kubernetes/apps/observability/smartctl-exporter/tests/prometheusrule_test.yaml`
(run via `just k8s test-prom-rules`), asserting `exp_annotations` so broken `{{ $labels.* }}` templates fail.
Two test properties are specific to this item and must not be skipped:

- [observation] **Series from both exporters in one test.** The NVMe and ATA exporters emit
  *identically named* metrics; a test that feeds only ATA series cannot detect cross-firing. Each
  temperature test must include both a `job="nas-smartctl"` and a non-NAS series and assert the correct
  rule fires on exactly one of them.
- [observation] **Negative baseline tests.** Feed the literal measured values (Reallocated_Sector_Ct=7,
  Reallocated_Event_Count=3, G-Sense_Error_Rate=1, temperature 38, all prefail values 100) and assert
  **zero** alerts. This is the executable form of the "quiet on day one" requirement.

## Rejected

- [observation] `Reallocated_Sector_Ct > 0`, `Reallocated_Event_Count > 0`, `G-Sense_Error_Rate > 0` —
  fire immediately on the measured baseline (7 / 3 / 1). Growth, not absolute value, is the signal.
- [observation] Any rule on attribute 194 `Temperature_Celsius` raw (214749610021) or attribute 220
  `Disk_Shift` raw (33685505) — vendor-packed fields, not scalars. Use `smartctl_device_temperature`.
- [observation] 45 °C warning / 50 °C critical — below the drive's measured `lifetime_max = 50`, so it
  would fire in normal summer operation.
- [observation] A dedicated `Helium_Condition raw > 0` rule — the raw field is 0 and the *normalized*
  value/threshold pair (100/75) is the real signal; subsumed by the generic prefail rule.
- [observation] A `relabelings` block forcing the `job` label — unnecessary, `spec.jobName` already sets
  it (verified against the live `ScrapeConfig` CRD, which exposes both `relabelings` and `metricRelabelings`).
- [observation] A dedicated `up{job="nas-smartctl"} == 0` alert — `TargetDown` already covers it.
- [observation] `--smartctl.device-include=^sdb$` — unnecessary (see the /dev/sda evidence) and brittle
  across USB re-enumeration.
- [observation] TLS / basic auth on the exporter ports via `--web.config.file` — deferred. It would
  match no existing precedent (the openwrt `node_exporter` is plaintext on the same LAN) and adds a
  credential to distribute. Recorded as a risk below rather than silently dropped.

## Verification method (how the above was established, 2026-08-01)

- [observation] Live read-only SSH inspection of `nas.lan`: OS, packages, apt sources and pins, disks,
  firewall, listeners, smartd config, OMV SMART config, self-test log, and the full SMART JSON of both
  disks — including replaying the exporter's own `smartctl` command verbatim against each disk.
- [observation] Source verification of `smartctl_exporter` v0.14.0 (`main.go`, `readjson.go`,
  `smartctl.go`, `metrics.go`, `device_filter.go`) for the invocation, device labelling, filter
  semantics and metric label sets. Doc summaries were **not** trusted for the label names.
- [observation] Live read-only cluster checks: the `ScrapeConfig` CRD field set, the existing
  `TargetDown` rule and its owner, and the smartctl ServiceMonitor.
- [observation] Local **ollama** models were used as design and adversarial review, then verified rather
  than trusted. Useful contributions: flagging `increase()`/`delta()` on a gauge, the promtool
  false-confidence gap, package-pinning drift, and the exporter-rebuild persistence gap. Four findings
  were **refuted**: (a) the claimed blocker that `/dev/sda` would trigger the global `smart_status`
  alert — refuted by the `Exists()` guard and by measurement; (b) 45/50 °C thresholds — below the
  drive's measured lifetime max; (c) "Helium_Condition is irrelevant on a non-helium drive" — the MG08
  *is* helium-sealed; (d) `Reallocated_Sector_Ct > 0` as a warning — fires on day one, the very
  constraint the model had been given.

## Acceptance criteria

- [criterion] `curl -s http://192.168.1.10:9633/metrics | grep smartctl_device_smart_status` returns
  `smartctl_device_smart_status{device="sdb"} 1` on the host.
- [criterion] `curl -s http://192.168.1.10:9100/metrics | head` returns node_exporter output.
- [criterion] Prometheus target page shows `nas-smartctl` and `nas-node` as UP with `instance="nas"`.
- [criterion] `kubectl -n observability get ciliumnetworkpolicy kube-prometheus-stack-prometheus`
  contains the 192.168.1.10/32 egress grant; a Hubble capture shows no DROPPED egress to it
  (`just k8s hubble-live-capture` + `just k8s hubble-analyze`).
- [criterion] `just k8s test-prom-rules` passes, including the both-exporters and baseline-quiet tests.
- [criterion] `flux -n observability get ks kube-prometheus-stack` Ready True on the new revision.
- [criterion] **Zero alerts firing** from the new group 24 h after deploy (the group goes live quiet).
- [criterion] Grafana renders the NAS disk's temperature and key attributes.

## Risks and follow-ups

- [risk] **Unauthenticated metrics on the LAN.** :9633 and :9100 are open with no host firewall.
  `smartctl_device_info` exposes the disk model and **serial number** as labels — these reach Prometheus
  and Grafana but never git. Accepted for parity with the existing openwrt scrape; revisit if the LAN
  trust boundary changes.
- [risk] **Backports drift.** `prometheus-smartctl-exporter` comes only from `trixie-backports` and is
  outside Renovate's reach. A future backport could change flag names. Mitigation: the OMV Ansible
  playbook should pin the version explicitly, and the in-cluster chart tag stays the version reference.
- [follow-up] **Re-enable the OMV scheduled SMART self-tests** (both jobs are `enable: false`; last
  extended test was ~16500 power-on hours ago). Passive SMART polling cannot find latent unreadable
  sectors on the 19 % of the disk that is never read — only a long self-test can. Arguably higher value
  than any alert in this item.
- [follow-up] Remove the stale `WDC WD30EZRX` entries from the OMV SMART device config.
- [follow-up] Decide whether smartd's e-mail path is retired once Pushover coverage is live, or kept
  deliberately as an independent channel that does not depend on the cluster being healthy.
- [follow-up] Verify grafana.com dashboard 22604 covers ATA attributes; it was chosen for NVMe.
