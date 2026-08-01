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
- [roadmap] [[nas-host-exporters]] (docs/roadmap)

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
- relates_to [[nas-host-exporters]]
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
