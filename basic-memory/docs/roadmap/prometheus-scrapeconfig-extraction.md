---
title: prometheus-scrapeconfig-extraction
type: roadmap
permalink: home-ops/docs/roadmap/prometheus-scrapeconfig-extraction
topic: Extract external Prometheus scrape targets into ScrapeConfig CRs (openwrt done,
  M93p NAS pending)
status: proposed
priority: medium
scope: Consolidate external scrape targets under kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfigs/
  as ScrapeConfig CRs (monitoring.coreos.com/v1alpha1) instead of inline HelmRelease
  additionalScrapeConfigs. Stage 1 (openwrt router) is DONE. Stage 2 (M93p NAS node_exporter)
  is PENDING, blocked by the Phase 10 bare-metal OMV cutover. Replaces the closed
  docs/roadmap/observability-content-extract and docs/roadmap/m93p-node-exporter-scrape
  items.
rationale: 'Inline additionalScrapeConfigs in the HelmRelease is brittle on chart
  upgrades (Renovate-adjacent); ScrapeConfig CRs are Renovate-neutral and consistent
  with the ServiceMonitor/PodMonitor/Probe primitives. scrapeConfigSelectorNilUsesHelmValues:
  false lets Prometheus discover ScrapeConfig CRs alongside the others.'
related_areas:
- observability
- flux-gitops
- resticprofile-backup
---

# Extract external Prometheus scrape targets into ScrapeConfig CRs

## Metadata (observation-form, schema validation)

- [topic] Extract external Prometheus scrape targets into ScrapeConfig CRs (openwrt done, M93p NAS pending)
- [status] proposed
- [priority] medium

## Scope

Consolidate external scrape targets under `kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfigs/` as `ScrapeConfig` CRs (monitoring.coreos.com/v1alpha1) instead of inline HelmRelease `additionalScrapeConfigs`. Stage 1 (openwrt router) is DONE. Stage 2 (M93p NAS node_exporter) is PENDING, blocked by the Phase 10 bare-metal OMV cutover. Replaces the closed `docs/roadmap/observability-content-extract` and `docs/roadmap/m93p-node-exporter-scrape` items.

## Stage 1 — openwrt router scrape (DONE, 2026-08-01, commit b44c52cc9)

- [observation] The inline `additionalScrapeConfigs.openwrt` block (formerly `helmrelease.yaml:505-514`) was extracted into `app/scrapeconfigs/openwrt.yaml`, a `ScrapeConfig` CR.
- [observation] `spec.jobName: openwrt` preserves the `job=openwrt` label — the operator owns the rendered `job_name`, the `job` label is set via relabeling (verified against the live CRD schema). Required because the grafana.com 18153 OpenWRT dashboard (`app/grafanadashboard.yaml`) filters on `job`.
- [observation] `metricRelabelings` (plural, per CRD schema) drops `^go_.*`, matching the former inline block.
- [observation] `scrapeConfigSelectorNilUsesHelmValues: false` added to the prometheusSpec so Prometheus discovers ScrapeConfig CRs (the chart default would leave them undiscovered; the pre-existing selector block only covered serviceMonitor/podMonitor/rule/probe).
- [observation] `${ROUTER_IP}` resolves via the existing Flux postBuild `substituteFrom: cluster-settings` (`components/common/vars/cluster-settings.yaml:10`) injected into every child Kustomization by the root cluster-apps patch — same mechanism the former inline scrape already used.
- [observation] The CiliumNetworkPolicy LAN egress grant (`app/ciliumnetworkpolicy.yaml`, `192.168.1.1/32:9100`) is unchanged — the ScrapeConfig CR does not change the network topology; only its header comment was updated to reference `ScrapeConfig/openwrt` instead of `additionalScrapeConfigs`.

## Stage 2 — M93p NAS node_exporter scrape (PENDING, blocked)

- [observation] PENDING: add a `ScrapeConfig` CR for the M93p `node_exporter` (`:9100`) under the same `app/scrapeconfigs/` directory.
- [observation] Blocking external condition: the Phase 10 bare-metal OMV cutover. The M93p currently runs Debian 13 + Proxmox with OpenMediaVault as a VM on the same machine (README.md hardware table); Phase 10 retires the Proxmox hypervisor layer and runs OMV bare-metal. The M93p `node_exporter` is part of the OMV Ansible playbook and lands only after that cutover.
- [observation] No ZFS monitoring belongs here: the M93p DAS is 16 TB EXT4 (README.md) and the Talos cluster node has no ZFS (no `zfs` anywhere in `kubernetes/` manifests). Definitively out of scope — not a follow-up.

## Rationale

Inline `additionalScrapeConfigs` in the HelmRelease is brittle on chart upgrades (Renovate-adjacent); `ScrapeConfig` CRs are Renovate-neutral and consistent with the ServiceMonitor/PodMonitor/Probe primitives. `scrapeConfigSelectorNilUsesHelmValues: false` lets Prometheus discover `ScrapeConfig` CRs alongside the others. Consolidating openwrt (done) and M93p (pending) into one item reflects that both land in the same `app/scrapeconfigs/` directory.

## Related

- relates_to [[observability]]
- relates_to [[flux-gitops]]
- relates_to [[resticprofile-backup]]
