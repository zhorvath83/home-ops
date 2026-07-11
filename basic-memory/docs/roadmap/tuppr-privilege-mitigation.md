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

## Execution plan (research-backed)

### Current state
- tuppr holds a Talos `os:admin` credential: `kubernetes/talos/machineconfig.yaml.j2:38-43` (`kubernetesTalosAPIAccess` enabled, `allowedRoles: [os:admin]`, `allowedKubernetesNamespaces: [system-upgrade]`). Talos generates a talosconfig Secret mounted by the tuppr pod.
- Its chart ClusterRole grants cluster-wide secret read + `validatingwebhookconfigurations` patch (audit).
- **Containment already good:** `kubernetes/apps/system-upgrade/tuppr/app/ciliumnetworkpolicy.yaml` scopes egress to `factory.talos.dev:443` + kube-apiserver `6443/50000` only, ingress to the webhook (:9443) + probes (:8081). Upgrades gate on all VolSync `ReplicationSource` idle; `TalosUpgrade` runs `drain.enabled:false`, `rebootMode: powercycle` (system-upgrade/CLAUDE.md).
- tuppr controller runs continuously (it must watch `TalosUpgrade`/`KubernetesUpgrade` CRs in `tuppr/upgrades/`).

### Target state
- The blast radius of tuppr is minimised and, where capability can't be removed, its abuse is detectable — closed out with a documented, accepted-risk ADR. (There is no clean full removal.)

### Implementation steps
1. **Role reduction — evaluate, expect to reject.** tuppr's core job is triggering Talos node upgrades via the Talos API, which requires `os:admin` (`upgrade` is privileged; `os:reader`/`os:etcd-backup` cannot upgrade). Confirm by reading tuppr's docs/CRs, then **document that os:admin is required** rather than downgrading. Do NOT lower it and silently break upgrades.
2. **Pin the network containment as a tested invariant.** The tuppr CNP is the real container. Add a note/comment that it must not be widened, and ensure flux-local builds it. Optionally add a CI assertion that the tuppr CNP egress stays `{factory.talos.dev, kube-apiserver:6443/50000}`.
3. **Shrink the exposure window (optional).** Keep tuppr scaled to 0 except during upgrade windows: suspend the Flux Kustomization + scale the deployment when idle —
   `flux suspend ks tuppr -n flux-system` and `kubectl -n system-upgrade scale deploy/tuppr --replicas=0`; resume both before applying an upgrade CR. Tradeoff: CRs won't reconcile while scaled down (acceptable — upgrades are deliberate, scheduled events). Document the runbook.
4. **Add detection.** The apiserver already emits metadata-level audit (`machineconfig.yaml.j2:121-125`, logs at `/var/log/audit/kube/`). Ship those to VictoriaLogs (observability) if not already, and add an alert rule for audit events where `user.username == "system:serviceaccount:system-upgrade:tuppr"` AND (`objectRef.resource == "secrets"` with verb get/list, OR `objectRef.resource == "validatingwebhookconfigurations"` with verb patch/update) occurring **outside** a known upgrade window. Alert via the existing Pushover/Alertmanager path.
5. **Close with an ADR** `docs/decisions/AD-0NN-tuppr-privilege-acceptance` recording the accepted residual risk, the containment controls, and the detection rule. Link it back from this roadmap item.

### Verification
- `kubectl auth can-i --list --as=system:serviceaccount:system-upgrade:tuppr` documented as the known baseline.
- CNP unchanged: `kubectl -n system-upgrade get cnp tuppr -o yaml` matches the pinned egress set.
- (If step 3) scaled to 0 between windows: `kubectl -n system-upgrade get deploy tuppr` → 0/0; upgrades still succeed after resume.
- (Step 4) fire a test: read a secret as the tuppr SA in a lab / or synthesize an audit event → alert triggers.

### Rollback & safety
- All steps are additive/observational or reversible (scale back up, resume ks). No capability is removed that would break upgrades if you keep os:admin.
- Do NOT downgrade the Talos role without proving upgrades still work — a broken upgrade path on a single node is worse than the contained privilege.

### Gotchas & dependencies
- Audit-log shipping to VictoriaLogs may need wiring (check observability); the metadata audit level records who/what/when but not bodies — sufficient for this detection.
- This is the item with "no clean solution" — the deliverable is containment + detection + documented acceptance, not elimination.

### Effort
M (~0.5 day: evaluation + detection rule + ADR; +optional suspend runbook).
