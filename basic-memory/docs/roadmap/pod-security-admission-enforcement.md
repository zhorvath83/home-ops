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

## Execution plan (research-backed)

### Current state
- Namespaces are defined per app-group as `kubernetes/apps/<group>/namespace.yaml` (12 files: downloads, media, selfhosted, security, networking, observability, cert-manager, volsync-system, system-upgrade, kube-system, external-secrets, flux-system). Each has `metadata.annotations` but **no** `pod-security.kubernetes.io/*` labels (e.g. `kubernetes/apps/downloads/namespace.yaml:4-7`). (The literal `name: _` is templated at apply time; labels under `metadata.labels` apply the same way the existing annotation does.)
- Most app pods already satisfy `restricted` (runAsNonRoot, drop ALL, seccomp RuntimeDefault). Known blockers below.

### Target state
- Each namespace carries an enforced PSS level appropriate to its workloads; the good posture becomes admission-guaranteed.

### Per-namespace recommendation (verify with a live securityContext scan first)
| Namespace | Target enforce | Blocker / note |
|---|---|---|
| downloads | `restricted` | maintainerr has roRoot=false but restricted does NOT require roRoot — OK |
| selfhosted | `baseline` now; `restricted` after L5 | wallos runs as root (`helmrelease.yaml:22-23`) → fails restricted (needs runAsNonRoot) but passes baseline |
| media | **stays `privileged`/warn until calibre fixed** | `calibre-web-automated` adds caps [CHOWN,SETUID,SETGID,FOWNER,DAC_OVERRIDE] (`helmrelease.yaml:104-107`) + APE=true → **violates even baseline**; PSS has no per-pod in-namespace exception |
| observability | `baseline` (→restricted where clean) | verify node-exporter/victoria-logs |
| security | `restricted` | pocket-id/tinyauth are distroless nonroot |
| networking | `baseline` | envoy/cloudflared |
| kube-system, system-upgrade, volsync-system, cert-manager | `privileged` | legit privileged infra (cilium, csi, tuppr, kopia-maint) — do NOT enforce restricted |
| external-secrets, flux-system | `baseline`/`restricted` | verify |

### Implementation steps
1. **Live-scan each namespace** against restricted before labeling:
   ```bash
   kubectl get pods -n <ns> -o json | jq -r '.items[].spec | {sa:.serviceAccountName, host:.hostNetwork, pods:[.containers[].securityContext]}'
   ```
2. **Start in warn/audit mode** (non-blocking) to surface violations without breaking anything. Add to each `namespace.yaml` under `metadata.labels`:
   ```yaml
   metadata:
     labels:
       pod-security.kubernetes.io/warn: restricted
       pod-security.kubernetes.io/warn-version: v1.36
       pod-security.kubernetes.io/audit: restricted
       pod-security.kubernetes.io/audit-version: v1.36
   ```
   Commit, reconcile, and watch `kubectl get events -A | grep -i podsecurity` + apply-time warnings.
3. **Flip to enforce** per namespace once clean, at the level from the table:
   ```yaml
       pod-security.kubernetes.io/enforce: restricted   # or baseline
       pod-security.kubernetes.io/enforce-version: v1.36
   ```
   Do downloads + security first (cleanest), then selfhosted (baseline), then the rest.
4. **media**: resolve calibre via `workload-token-and-rootless-hygiene` (fix/justify caps) OR move calibre to an isolated namespace, THEN enforce baseline/restricted on media. Until then keep media at warn only.
5. Test each namespace label change with `kubectl label --dry-run=server ns <ns> pod-security.kubernetes.io/enforce=restricted` to preview rejections before committing.

### Verification
- `kubectl get ns -L pod-security.kubernetes.io/enforce` → labels present.
- `kubectl label --dry-run=server ns <ns> pod-security.kubernetes.io/enforce=<level>` → no violations reported.
- Every pod in the namespace stays Running after a rollout restart; no PodSecurity admission denials in events.

### Rollback & safety
- Remove/lower the label and reconcile — instant, no workload change.
- **Risk:** flipping enforce with a non-compliant pod blocks its (re)creation on next restart/upgrade — that's why warn/audit + dry-run come first. Enforce one namespace at a time.

### Gotchas & dependencies
- PSS has no per-pod exception inside a namespace — a single non-compliant app (calibre) blocks the whole namespace; fix or isolate it.
- Hard dependency: `workload-token-and-rootless-hygiene` (wallos/calibre) unblocks restricted on selfhosted/media.
- Pin `*-version: v1.36` (matches the cluster) so a future API bump can't silently change semantics.

### Effort
M (~1 day staged across namespaces; media gated on the calibre fix).
