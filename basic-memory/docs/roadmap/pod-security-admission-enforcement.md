---
title: pod-security-admission-enforcement
type: roadmap
permalink: home-ops/docs/roadmap/pod-security-admission-enforcement
topic: Enforced Pod Security Standards — turn the existing hardening into a guaranteed
  floor
status: proposed
priority: high
scope: Apply pod-security.kubernetes.io/enforce labels to the application namespaces
  (baseline, then restricted where workloads already comply), keeping infra namespaces
  at privileged.
rationale: The workloads already run rootless with dropped capabilities and RuntimeDefault
  seccomp; enforcing PSS converts that voluntary good posture into an admission-level
  guarantee that no future or compromised workload can weaken.
related_areas:
- k8s-workloads
options:
- PSS labels only (native, zero extra components) — recommended
- Add Kyverno/Gatekeeper later if policy needs outgrow PSS
---

# Enforced Pod Security Standards — turn the existing hardening into a guaranteed floor

## Metadata (observation-form, schema validation)

- [topic] Enforced Pod Security Standards — turn the existing hardening into a guaranteed floor
- [status] proposed
- [priority] high

## What we gain

- A hard, cluster-enforced ceiling on pod privilege — the good defaults become non-negotiable.
- New apps inherit the security bar automatically; a regression is rejected at admission, not discovered later.
- Closes the highest-leverage node-breakout path with near-zero disruption — most apps already satisfy restricted.

## What to do

1. Audit each app namespace against the restricted profile (most already pass: runAsNonRoot, drop ALL, seccomp RuntimeDefault).
2. Label downloads/media/selfhosted/observability/security with enforce=baseline and warn/audit=restricted first.
3. Tighten to enforce=restricted where the namespace is clean; keep kube-system/system-upgrade/volsync-system/cert-manager at privileged.
4. Resolve the last root-running apps first via workload-token-and-rootless-hygiene.
5. Verify: run in warn mode, review warnings, then flip to enforce.

## Options

1. PSS labels only (native, zero extra components) — recommended
2. Add Kyverno/Gatekeeper later if policy needs outgrow PSS

## Related

- relates_to [[k8s-workloads]]
- relates_to [[AD-023-cnp-threat-model-audit]]
- relates_to [[workload-token-and-rootless-hygiene]]
