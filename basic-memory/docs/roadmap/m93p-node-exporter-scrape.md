---
title: m93p-node-exporter-scrape
type: roadmap
permalink: home-ops/docs/roadmap/m93p-node-exporter-scrape
topic: Add M93p (bare-metal OMV NAS) to kube-prometheus-stack scrape targets
status: proposed
scope: Add a Prometheus scrape target for the M93p node's `node_exporter` (after the
  post-cutover OMV bare-metal install completes). The M93p is NOT a cluster node but
  runs `node_exporter` on `:9100` per the OMV Ansible playbook. Should land as a `ScrapeConfig`
  CR alongside the OpenWrt scrape extracted in the observability-content-extract item.
priority: low
rationale: Without this, NAS-host metrics (CPU, memory, disk I/O, network) are invisible
  in Grafana, which weakens the operational picture during incidents involving NFS
  or backup performance issues.
related_areas:
- observability
- resticprofile-backup
---

# Add M93p (bare-metal OMV NAS) to kube-prometheus-stack scrape targets

## Metadata (observation-form, schema validation)

- [topic] Add M93p (bare-metal OMV NAS) to kube-prometheus-stack scrape targets
- [status] proposed
- [priority] low

## Scope

Add a Prometheus scrape target for the M93p node's `node_exporter` (after the post-cutover OMV bare-metal install completes). The M93p is NOT a cluster node but runs `node_exporter` on `:9100` per the OMV Ansible playbook. Should land as a `ScrapeConfig` CR alongside the OpenWrt scrape extracted in the observability-content-extract item.

## Rationale

Without this, NAS-host metrics (CPU, memory, disk I/O, network) are invisible in Grafana, which weakens the operational picture during incidents involving NFS or backup performance issues.

## Related

- relates_to [[observability]]
- relates_to [[resticprofile-backup]]
