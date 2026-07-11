---
title: default-deny-ingress-baseline
type: roadmap
permalink: home-ops/docs/roadmap/default-deny-ingress-baseline
topic: Default-deny ingress baseline — make ingress opt-in like egress already is
status: proposed
priority: high
scope: Add a clusterwide default-deny ingress posture mirroring the existing allow-cluster-egress
  model, then grant explicit ingress per observed need, starting with the control-plane
  and infra pods.
rationale: Egress is already enforced on 100% of pods; extending the same opt-in model
  to ingress gives symmetric containment, so a compromised app can only reach the
  workloads it is explicitly allowed to.
related_areas:
- networking
options:
- Clusterwide default-deny CCNP + per-app allows — consistent with the current CCNP
  model
- Per-namespace default-deny where a big-bang clusterwide flip feels risky
---

# Default-deny ingress baseline — make ingress opt-in like egress already is

## Metadata (observation-form, schema validation)

- [topic] Default-deny ingress baseline — make ingress opt-in like egress already is
- [status] proposed
- [priority] high

## What we gain

- Symmetric, complete containment — lateral reach is allow-listed in both directions.
- The most sensitive infra (Flux controllers, cert-manager, metrics-server) stops being reachable from arbitrary app pods.
- A predictable, auditable ingress map — Hubble already provides the observability to build it safely.

## What to do

1. Use Hubble to enumerate the real ingress each infra/control-plane pod needs (ports + source identities).
2. Introduce a default-deny-ingress CCNP, then explicit allow policies per observed need.
3. Roll out staged, starting with the crown-jewel namespaces (flux-system, cert-manager, kube-system).
4. Verify with a Hubble capture: legitimate flows still forward, cross-namespace app→infra attempts drop.

## Options

1. Clusterwide default-deny CCNP + per-app allows — consistent with the current CCNP model
2. Per-namespace default-deny where a big-bang clusterwide flip feels risky

## Related

- relates_to [[networking]]
- relates_to [[AD-023-cnp-threat-model-audit]]
- relates_to [[iam]]
