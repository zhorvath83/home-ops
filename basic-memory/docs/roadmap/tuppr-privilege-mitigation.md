---
title: tuppr-privilege-mitigation
type: roadmap
permalink: home-ops/docs/roadmap/tuppr-privilege-mitigation
topic: Contain the upgrade controllers blast radius — tuppr privilege mitigation
status: proposed
priority: high
scope: The Talos/K8s upgrade controller (tuppr) legitimately needs broad power; since
  its chart ClusterRole and its os:admin Talos credential are largely intrinsic to
  its job, focus on reducing and containing blast radius and on detection, rather
  than removing capability.
rationale: Boxing in what the single most powerful automation identity can reach —
  and making its actions observable — buys strong defense-in-depth without giving
  up automated upgrades. A clean full-removal likely does not exist, so mitigation
  is the realistic win.
related_areas:
- talos-cluster
options:
- Minimize role
- Accept-and-detect
- Suspend-between-windows — best combined
---

# Contain the upgrade controllers blast radius — tuppr privilege mitigation

## Metadata (observation-form, schema validation)

- [topic] Contain the upgrade controllers blast radius — tuppr privilege mitigation
- [status] proposed
- [priority] high

## What we gain

- The most powerful automation identity is bounded by network, namespace, and (where feasible) role scope.
- Any abuse becomes observable even where capability cannot be removed.
- Upgrades stay automated — no operational regression.

## What to do

1. Evaluate downgrading the Talos API role from os:admin to the minimal role the upgrade flow needs (os:reader / os:etcd-backup); test a real TalosUpgrade, and accept+document if os:admin is genuinely required.
2. Keep and pin the existing CNP egress scope (kube-apiserver:50000 + factory.talos.dev only) as a tested invariant.
3. Keep tuppr suspended between planned upgrade windows (it already gates on VolSync-idle) to shrink the exposure window.
4. Add detection: alert on the tuppr ServiceAccount reading secrets outside upgrade windows or patching validatingwebhookconfigurations.
5. Record the residual (accepted) risk in an ADR.

## Options

1. Minimize role
2. Accept-and-detect
3. Suspend-between-windows — best combined

## Related

- relates_to [[talos-cluster]]
- relates_to [[AD-019-tuppr-system-upgrade]]
- relates_to [[tuppr-upgrade-automation]]
