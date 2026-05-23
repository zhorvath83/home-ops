---
title: cnp-per-app-audit
type: roadmap
permalink: home-ops/docs/roadmap/cnp-per-app-audit
topic: Per-app CiliumNetworkPolicy audit follow-up to AD-023
status: proposed
priority: medium
scope: Run the per-app CiliumNetworkPolicy audit promised by AD-023. For each app
  decide baseline-only, Szint I (ingress-only), or Szint II (ingress + strict egress
  + opt-out label). Target count is not predetermined — driven by audit findings.
rationale: AD-023 defined the two-tier threat-model approach but deferred the audit
  itself. Without it, per-app CNP coverage stays accidental (whichever app needed
  one during migration). The audit turns the AD-023 model into deliberate, documented
  coverage.
options:
- Pass-by-pass by exposure tier — externally-exposed first, then LAN-only routed,
  then internal-only
- Pass-by-pass by data sensitivity — secret providers and personal-data apps first,
  then media, then ephemeral
- Namespace-batched — walk each namespace top-to-bottom
related_areas:
- networking
- k8s-workloads
decision_link: AD-023-cnp-threat-model-audit
---

# Per-app CiliumNetworkPolicy audit follow-up to AD-023

## Metadata (observation-form, schema validation)

- [topic] Per-app CiliumNetworkPolicy audit follow-up to AD-023
- [status] proposed
- [priority] medium

## Scope

Run the per-app CiliumNetworkPolicy (CNP) audit promised by AD-023. Walk the workload inventory and, for each app, decide whether it stays on the cluster-wide baseline (`allow-cluster-egress` + `allow-dns-egress`) or gets a dedicated CNP — Szint I (ingress-only, no opt-out label) or Szint II (ingress + strict egress + `egress.home.arpa/custom-egress: ""` opt-out label).

The number of target apps is **not predetermined**. AD-023's "5-8 high-value apps" line was an early estimate; the actual list is whatever the threat-model walk-through surfaces. Today only `paperless` is on Szint I and `envoy-external` / `envoy-internal` carry ingress allowlists; everything else relies on the baseline.

## Rationale

AD-023 closed the architectural question (targeted threat-model approach instead of default-deny everywhere) and defined the two-tier severity model, but the audit itself was deferred. Without it, the per-app CNP coverage stays accidental — whichever app happened to need one during migration. The audit is the mechanism that turns the AD-023 model into deliberate, documented coverage and prevents the "everyone trusts the baseline" drift from going unchallenged.

## Options

1. Pass-by-pass audit driven by exposure tier — start with externally-exposed apps (`envoy-external` routes), then LAN-only routed apps, then internal-only workloads
2. Pass-by-pass audit driven by data sensitivity — start with secret providers and apps holding personal data (paperless-style), then media, then ephemeral workloads
3. Namespace-batched audit — walk each namespace top-to-bottom; cheaper context-switch cost, no prioritization signal

## Related

- relates_to [[networking]]
- relates_to [[k8s-workloads]]
- decided_in [[AD-023-cnp-threat-model-audit]]
