---
title: AD-024-crowdsec-namespace-psa-exception
type: decision
permalink: home-ops/docs/decisions/ad-024-crowdsec-namespace-psa-exception
decision_id: AD-024
topic: 'crowdsec namespace PSA exception — explicit enforce: privileged'
status: active
decided_at: '2026-07-30'
decision: 'The crowdsec namespace runs pod-security.kubernetes.io/enforce: privileged
  — a deliberate, Git-recorded exception to the cluster restricted-PSA baseline —
  because the crowdsec agent DaemonSet mounts hostPath /var/log and the upstream crowdsec
  image entrypoint requires root.'
rationale: 'The agent DaemonSet mounts hostPath /var/log to read host container logs
  (a node log collector inherently needs it, like victoria-logs-collector). The upstream
  image entrypoint requires root: the LAPI creates /etc/crowdsec as a symlink on the
  root filesystem at runtime, and agent/appsec copy credentials into /staging/etc/crowdsec
  and open /var/lib/crowdsec/data/crowdsec.db read-write on the root filesystem —
  a rootless posture broke acquisition, which is what triggered the official-chart
  migration. Explicit privileged is chosen over bare label removal (both work, since
  the cluster default for an unlabeled namespace is privileged, but the explicit label
  states the exception in Git and survives a default change).'
tradeoffs: The namespace is root + hostPath by design; the restricted-PSA admission
  guarantee is forfeited here, mitigated by compensating controls (no SA token, seccomp
  RuntimeDefault, all caps dropped, APE false, CNPs) and a small fixed chart-supplied
  workload set. podSecurityContext is left {} and warn/audit labels are omitted (the
  namespace is knowingly root + hostPath). This is a one-namespace exception, not
  a precedent.
related_areas:
- k8s-workloads
- networking
- observability
---

# AD-024 — crowdsec namespace PSA exception (explicit enforce: privileged)

## Metadata (observation-form, schema validation)

- [decision_id] AD-024
- [status] active
- [decided_at] 2026-07-30
- [topic] crowdsec namespace PSA exception — explicit enforce: privileged

## Context

The `crowdsec` namespace previously carried a human-locked `pod-security.kubernetes.io/enforce: restricted` label while the workload ran on the bjw-s `app-template` chart bent into a rootless posture the upstream crowdsec image was not designed for. That rootless bend broke log acquisition — the victorialogs tail datasource stalled silently on every VictoriaLogs pod replacement, and the chart-native `file` datasource the image is built for needs hostPath `/var/log` — which is what triggered the migration to the official `crowdsecurity/crowdsec` chart. The migration replaces the six PSA labels with a single explicit `pod-security.kubernetes.io/enforce: privileged` (no `enforce-version`, no `warn`/`audit` — the privileged profile has no checks to version and the namespace is knowingly root + hostPath).

This is a deliberate, Git-recorded exception to [[pod-security-admission-enforcement]] (which keeps infra namespaces at `privileged` and pushes app namespaces toward `restricted`). `crowdsec` is treated as privileged-by-design infra, not a restricted-app namespace.

## Decision

The `crowdsec` namespace runs `pod-security.kubernetes.io/enforce: privileged`, recorded explicitly in `kubernetes/apps/crowdsec/namespace.yaml` — reversing the earlier `restricted` and chosen over bare label removal (which would lean on the implicit cluster default).

## Rationale

- The agent DaemonSet mounts hostPath `/var/log` read-only to read host container logs (`agent.hostVarLog: true`); a node log collector inherently needs it, exactly like `victoria-logs-collector` in the unlabeled `observability` namespace.
- The upstream crowdsec image entrypoint requires root: the LAPI command creates `/etc/crowdsec` as a symlink on the root filesystem at runtime (`ln -s /etc/crowdsec_data /etc/crowdsec`), and the agent and appsec copy credentials into `/staging/etc/crowdsec` and open `/var/lib/crowdsec/data/crowdsec.db` read-write on the root filesystem. A rootless posture broke acquisition — the original symptom that triggered the chart migration.
- Explicit `privileged` over bare label removal: both work on this cluster (the effective default for an unlabeled namespace is `privileged`), but the explicit label states the exception in Git and survives any future change to the cluster default.

## Compensating controls (in place of the restricted profile)

- No service-account token mounted: `automountServiceAccountToken: false` on lapi/agent/appsec (postRenderer patch) and on web-ui (values); the bouncer's API token mount was also dropped in a separate commit. The crowdsec workloads never call the Kubernetes API.
- `seccompProfile: RuntimeDefault` on all three workloads (lapi/agent/appsec) plus the two agent/appsec `wait_for_lapi` init containers — applied through chart values.
- `capabilities.drop: [ALL]` on the same five targets, through chart values.
- `allowPrivilegeEscalation: false` and `privileged: false` on all five targets.
- CiliumNetworkPolicies: four CNP documents scope crowdsec egress to the CrowdSec APIs over 443 and ingress to the LAPI/appsec/metrics ports only (bouncer, web-ui, prometheus, and the agent/appsec registration + streaming). The namespace is not network-open.

## Declined options (with reasons — not future work)

- `readOnlyRootFilesystem`: DECLINED. Blocking evidence — the LAPI's container command creates `/etc/crowdsec` as a symlink on the root filesystem at runtime; the agent and appsec copy credentials into `/staging/etc/crowdsec` on the root filesystem (an emptyDir there would hide the pre-baked hub/parsers/scenarios they also read) and open `/var/lib/crowdsec/data/crowdsec.db` read-write on the root filesystem (the chart gives them no PVC). Unlocking it would require rewriting the container command and volume mounts via postRenderer. The human's explicit instruction this session: "I do not want hardening that requires all sorts of workarounds."
- Rootless (`runAsNonRoot` uid 10001 + `supplementalGroups: [0]`, the `victoria-logs-collector` vlagent pattern): DECLINED, does not transfer. The crowdsec entrypoint requires root, and since the agent already runs as root it reads the 0640 root:root host container logs by ownership — the `supplementalGroups: [0]` trick vlagent needs only exists because vlagent is rootless.

## Tradeoffs

- The namespace is root + hostPath by design; the restricted-PSA admission guarantee is forfeited here. Mitigated by the compensating controls above and by the workload set being small, fixed (lapi/agent/appsec + bouncer + web-ui), and fully chart-supplied (no ad-hoc pods can land unlabeled in this namespace).
- `podSecurityContext` is deliberately left `{}` and the namespace PSA `warn`/`audit` labels are omitted — the namespace is knowingly root + hostPath, so `warn`/`audit` would only emit noise on every deploy.
- This is a one-namespace exception, not a precedent; any new namespace still follows [[pod-security-admission-enforcement]].

## Related

- exception_to [[pod-security-admission-enforcement]]
- relates_to [[crowdsec-psa-removal-and-official-chart-migration]]
- relates_to [[k8s-workloads]]
- relates_to [[networking]]
- relates_to [[observability]]
