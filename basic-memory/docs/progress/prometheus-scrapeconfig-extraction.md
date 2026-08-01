---
title: prometheus-scrapeconfig-extraction
type: progress
permalink: home-ops/docs/progress/prometheus-scrapeconfig-extraction
---

# External Prometheus scrape targets consolidated into ScrapeConfig CRs

## Metadata (observation-form, schema validation)

- [topic] External Prometheus scrape targets consolidated into ScrapeConfig CRs under app/scrapeconfigs/, retiring the inline HelmRelease additionalScrapeConfigs
- [status] done
- [closed] 2026-08-01
- [priority] medium

## What was delivered

- [delivered] The inline `additionalScrapeConfigs.openwrt` block was extracted into `kubernetes/apps/observability/kube-prometheus-stack/app/scrapeconfigs/openwrt.yaml` as a `ScrapeConfig` CR (monitoring.coreos.com/v1alpha1). Commit `b44c52cc9` (2026-08-01).
- [delivered] `scrapeConfigSelectorNilUsesHelmValues: false` set on the prometheusSpec (`kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml:501`) so Prometheus discovers `ScrapeConfig` CRs alongside ServiceMonitor/PodMonitor/Probe.
- [delivered] `app/scrapeconfigs/kustomization.yaml` wired into `app/kustomization.yaml`.
- [detail] `spec.jobName: openwrt` preserves the `job` label the grafana.com 18153 OpenWRT dashboard filters on.
- [detail] `metricRelabelings` (plural, per the ScrapeConfig CRD schema) drops `^go_.*`, matching the former inline block verbatim.
- [detail] `${ROUTER_IP}` resolves via the existing Flux `postBuild.substituteFrom` cluster-settings patch (the same mechanism the openwrt scrape always used). The CiliumNetworkPolicy LAN egress grant (`192.168.1.1/32:9100`) was unchanged; only its header comment was updated.

## Completeness proof (why this item is closeable)

- [evidence] Across the ENTIRE git history the `additionalScrapeConfigs` block ever held exactly ONE job, `openwrt` — introduced in `8263c7d2e` and removed in `b44c52cc9`. Verified with `git log -S additionalScrapeConfigs --all -- kubernetes/` and by inspecting each hit. There was never a second target to migrate.
- [evidence] Repo-wide grep for `additionalScrapeConfigs|additional_scrape_configs|extraScrapeConfigs` over `kubernetes/` (yaml/yml/j2) returns zero hits in any manifest, Secret, or ConfigMap.

## Live verification (2026-08-01)

- [evidence] `up{instance="192.168.1.1:9100", job="openwrt"} => 1` — the ScrapeConfig-sourced job is present and UP (queried via `promtool query instant` inside the prometheus pod).
- [evidence] `prometheus.spec.additionalScrapeConfigs` is empty (absent) — `kubectl -n observability get prometheus -o jsonpath='{.items[*].spec.additionalScrapeConfigs}'` returns nothing.
- [evidence] ScrapeConfig CR count cluster-wide = 1 (observability/openwrt). External scrape targets today are ONLY openwrt (ScrapeConfig) + devices_probe and nfs_probe (Probe CRs); all ~50 scrape jobs report `up=1`.
- [evidence] All Prometheus selectors are `{}` (match-all): serviceMonitorSelector, podMonitorSelector, probeSelector, ruleSelector, scrapeConfigSelector.

## Scope split

- [decision] The NAS targets (`nas-smartctl` :9633, `nas-node` :9100) were split out into [[nas-host-exporters]] (status: planned) and are NOT part of this item. They live on a different host (OMV NAS), need their own Cilium egress grant, and bundle smartctl_exporter + node_exporter in one delivery.

## Acceptance criteria

- [criterion] AC1: `grep -rniE 'additionalScrapeConfigs|additional_scrape_configs|extraScrapeConfigs' kubernetes/` returns 0 hits. PASS (verified 2026-08-01).
- [criterion] AC2: `kubectl -n observability get prometheus -o jsonpath='{.items[*].spec.additionalScrapeConfigs}'` returns empty. PASS (verified 2026-08-01).
- [criterion] AC3: `up{job="openwrt"} == 1` in Prometheus. PASS (`up{instance="192.168.1.1:9100", job="openwrt"} => 1`, 2026-08-01).

## Related

- relates_to [[observability]]
- relates_to [[flux-gitops]]
- relates_to [[nas-host-exporters]]
- continues [[observability-probes-and-disk-health]]
