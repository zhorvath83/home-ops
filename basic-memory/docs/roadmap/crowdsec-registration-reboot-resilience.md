---
title: crowdsec-registration-reboot-resilience
type: roadmap
permalink: docs/roadmap/crowdsec-registration-reboot-resilience
topic: CrowdSec agent/appsec LAPI registration survives an in-place pod restart
status: in-progress
priority: high
scope: Make the agent and appsec wait-for-lapi-and-register init step idempotent so
  a node reboot (pod restarted in place, same name) no longer crashloops on "user
  already exist", and garbage-collect the stale machine records every rollout leaves
  behind in the LAPI.
rationale: Both gateways run CrowdSec ext_authz fail-closed (failOpen false, statusOnError
  503), so a stuck appsec pod turns into a full 503 outage on envoy-external AND envoy-internal.
  One node reboot (2026-11-05) was enough to trigger it.
related_areas:
- networking
- observability
options:
- A — skip registration when /tmp_config already holds credentials (postRenderer patch)
- B — per-start unique machine name (pod name + suffix) on conflict, plus LAPI agents
  GC
- C — static machine credentials seeded by the LAPI postStart hook, no auto-registration
- D — LAPI agents_autodelete only (hygiene, does NOT fix the conflict on its own)
---

# CrowdSec agent/appsec LAPI registration survives an in-place pod restart

## Metadata (observation-form, schema validation)

- [topic] CrowdSec registration idempotency across node reboot
- [status] in-progress — implemented on main 2026-11-05 (commit 064001d38, option A+B+D); live-verified; only AC1 on a real node reboot remains
- [priority] high — single point of failure for all gateway traffic

## Incident (2026-11-05, measured)

- [fact] Node k8s-cp0 rebooted ~06:36 UTC. The pods `crowdsec-appsec-7b75949986-88gc4` and `crowdsec-agent-9c4qv` (created 2026-10-31, same UID) were restarted in place, so their init container ran again.
- [fact] The init container failed with `cscli lapi register: ... http 403 Forbidden: API error: user 'crowdsec-appsec-7b75949986-88gc4': user already exist`. Restart count was 454 at the time of measurement, and both pods were stuck in Pending/Unknown for ~9.5h.
- [fact] Bouncer log: `failed to evaluate request ... action:error`. Envoy access log: `503 ext_authz_error UAEX` on every route, e.g. `httproute/selfhosted/sure`.
- [fact] Both gateway SecurityPolicies (`networking/envoy-external-crowdsec`, `networking/envoy-internal-rfc1918`) use extAuth grpc -> `crowdsec/crowdsec-bouncer:8080` with `failOpen: false`, `statusOnError: 503`.
- [fact] Alerts fired correctly: CrowdSecAppsecDown, CrowdSecAgentDown, CrowdSecAcquisitionStalled, EnvoyExtAuthzErrors, KubePodNotReady, KubeDaemonSetRolloutStuck. Detection is not the gap; self-healing is.
- [fact] Manual remedy: delete the two pods. The replacements get new names and register cleanly.

## Root cause (chart 0.24.2, measured)

- [fact] The init command is hard-coded in `templates/appsec-deployment.yaml:58`, `agent-daemonSet.yaml:56` and `agent-deployment.yaml:58`: `until nc ...; ln -s /staging/etc/crowdsec /etc/crowdsec && cscli lapi register --machine "$USERNAME" -u "$LAPI_URL" --token "$REGISTRATION_TOKEN" && cp .../local_api_credentials.yaml /tmp_config/`. There is no values knob, so any change needs a HelmRelease `postRenderers` patch (the HR already patches all three workloads, `kubernetes/apps/crowdsec/crowdsec/app/helmrelease.yaml`).
- [fact] `USERNAME` is the pod name (fieldRef metadata.name). `cscli lapi register` has no force/overwrite flag (v1.8.2 flags: --file, --machine, --token, --url).
- [fact] The agent side cannot delete its own machine: `cscli machines delete` needs LAPI database access. The fix "on conflict, delete and re-register" proposed earlier in chat is **not possible from the init container**.
- [fact] Credentials are handed over through `/tmp_config`, an `emptyDir: {}` (disk-backed). The main container copies `/tmp_config/local_api_credentials.yaml` in at start (`appsec-deployment.yaml:116`, `agent-daemonSet.yaml:103-105`).
- [fact] LAPI flush config: `MaxItems 5000, MaxAge 7d, AgentsGC nil, BouncersGC nil`, so machine records are never garbage-collected.
- [fact] `cscli machines list` on 2026-11-05 returned 37 machines. 33 are stale `crowdsec-agent-*`/`crowdsec-appsec-*` records going back to 2026-08-03, one pair per rollout.

## Options

1. **A — skip if credentials exist.** Patch the init command: if `/tmp_config/local_api_credentials.yaml` exists, skip register. Keeps the machine identity. Depends on the emptyDir surviving a node reboot for the same pod UID (unmeasured, see M1). If the file is missing and the name conflicts, the pod is still stuck, so A needs B as a fallback.
2. **B — unique name on conflict.** Register as `$USERNAME`; on "already exist", register as `$USERNAME-<short random/boot id>`. Always self-heals. Leaks one stale record per conflict, so it needs D.
3. **C — static credentials.** The LAPI postStart hook (which already seeds `crowdsec-web-ui` and `blocklist-import` with `machines add --force`) also seeds fixed `crowdsec-agent`/`crowdsec-appsec` machines from 1Password, and the init writes credentials from the Secret instead of auto-registering. No conflict and no leak. Larger change: new secrets, the auto_registration token becomes unused, and it must be checked whether 2 appsec pods during a maxSurge rollout can share one machine identity (M4).
4. **D — LAPI agents GC.** `db_config.flush.agents_autodelete.login_password: <duration>`. Cleans the backlog. Does not fix the conflict, because the conflicting record is fresh. Always paired with A, B or C.

- [recommendation] **A+B in one init script, plus D.** Reuse credentials when present; on conflict fall back to a suffixed name; GC stale records. Smallest change, keeps the chart's auto-registration model, always self-heals. Revisit C only if M4 shows shared identity is safe and B's suffix churn is unwanted.

## Open decisions

- [decision] D1 — A+B+D (recommended) vs C+D.
- [decision] D2 — agents_autodelete duration. It must exceed the longest legitimate heartbeat gap (e.g. 7d, aligned with MaxAge).
- [decision] D3 — out of scope unless chosen: whether `envoy-internal` should stay fail-closed on CrowdSec. Today a CrowdSec fault also cuts LAN access. That is a security trade-off decided at bouncer rollout (see envoy-crowdsec-bouncer).

## Measurement plan (before implementing)

- [measure] M1 — does `/tmp_config` survive a node reboot for the same pod UID? Talos kubelet dir `/var/lib/kubelet/pods/<uid>/volumes/kubernetes.io~empty-dir/crowdsec-config`: read it via `talosctl ls`/`read` on the node before and after the next planned reboot. Today's incident does not answer this: the init ran again, but it would have run either way.
- [measure] M2 — conflict reproduction without a reboot. Run a throwaway pod with the init image and register `--machine <existing-name>` against the LAPI; expect the 403 `user already exist`. Then run the patched script and expect a suffixed name and a 0 exit. Clean up the test machine afterwards.
- [measure] M3 — confirm the exact config key and the LAPI behaviour of `flush.agents_autodelete` for crowdsec v1.8.2 (Context7 / upstream docs). Check that it only deletes machines whose last_heartbeat is older than the duration: `crowdsec-lapi-85fd6b78f5-qb89j`, `crowdsec-web-ui` and `blocklist-import` have fresh heartbeats and must survive.
- [measure] M4 (only for option C) — two pods logging in with the same machine credentials simultaneously: JWT, heartbeat and alert attribution behaviour.
- [measure] M5 — postRenderer patch rendering: `flux build`/`helm template` + kustomize patch for all three workloads. Confirm the command is replaced in the init container only and that the main container and securityContext are untouched.

## Acceptance criteria

1. After an in-place restart of the agent and appsec pods (simulated: kill the pod sandbox, or a planned node reboot), both become Ready without manual action, and Envoy returns no `ext_authz_error` 503 beyond the startup window.
2. M2 reproduction: the patched init exits 0 when the machine name already exists.
3. The stale machine backlog is cleaned up: `cscli machines list` contains only live identities + crowdsec-web-ui + blocklist-import + the LAPI's own record, within the configured GC duration.
4. A normal rollout (new pod names) still registers on the first try, and the RollingUpdate maxSurge of appsec still causes no 503 window.
5. `helm template`/`flux build` + pre-commit pass. No change to the bouncer or the SecurityPolicies unless D3 says so.


## Execution (2026-11-05, on main)

### Decisions taken

- [decision] D1 — A+B+D, as recommended. C (static credentials) was not needed: A+B self-heal in every measured case.
- [decision] D2 — `agents_autodelete.login_password: 7d`, aligned with `flush.max_age: 7d`. Safe because a GC'd machine whose pod comes back simply fails the stored-credential check and registers again.
- [decision] D3 — fail-closed on envoy-internal is unchanged (out of scope).

### Measurements

- [measure] M2 DONE — throwaway pod (same image, label `k8s-app: crowdsec` for the CNP, real `crowdsec-lapi-secrets` token, emptyDir `/tmp_config`), `USERNAME` set to the existing stale `crowdsec-agent-k7pzx`. Four runs:
  run1 (conflict, no stored creds) -> 403 then suffixed `crowdsec-agent-k7pzx-b882c869`, rc 0;
  run2 (in-place restart, valid creds) -> "reusing stored LAPI credentials", rc 0;
  run3 (stored password corrupted) -> "rejected, registering again" -> new suffix, rc 0;
  run4 (fresh name) -> plain register, rc 0.
  The first iteration used `date +%s` as the suffix and run3 failed, because the same second produced the same suffix. Switched to 8 random hex chars (`od -An -N4 -tx1 /dev/urandom`). Test pod, ConfigMap and the 5 test machines were removed afterwards.
- [measure] `cscli lapi status` in v1.8.2 authenticates with the stored login/password and returns an error on rejection (`cmd/crowdsec-cli/clilapi/status.go`). It works in the init context because the staging hub exists at `/staging/etc/crowdsec/hub`.
- [measure] M3 DONE (source v1.8.2 `pkg/database/flush.go`): `flushAgents` deletes machines with `last_heartbeat <= now - duration` AND **no alerts** AND matching auth type AND IP not 127.0.0.1/::1. The duration accepts days (`ParseDurationWithDays`). Consequences: the LAPI's own record (::1) is never deleted; stale agents that produced alerts are only removed after their alerts age out under max_age 7d. AC3 therefore lags by up to ~14d, not 7d.
- [measure] M5 DONE — `helm template` 0.24.2 + the HR postRenderer patches via `kubectl kustomize`, with Flux substitution emulated (`$$`->`$`). One patch with `target.name: crowdsec-(agent|appsec)` and no kind applies to both the Deployment and the DaemonSet. The rendered script is byte-identical to the M2-tested one. env, securityContext, mounts, the main container command and `automountServiceAccountToken: false` are preserved. The LAPI is untouched. pre-commit passed.
- [measure] M1 OPEN — whether the emptyDir survives a node reboot is still unmeasured. The design no longer depends on it: without the file, B handles the conflict.
- [measure] M4 N/A (option C not taken).


### Live verification (2026-11-05)

- [verified] Flux applied 064001d38. HR crowdsec upgraded (v11), and the new pods `crowdsec-agent-cbgsf` and `crowdsec-appsec-7ff9769c7d-g5dzr` registered on the first try. The new init logs show "Successfully registered".
- [verified] Outage end: the last `ext_authz_error` 503 on envoy-internal was at 16:43:30Z, and envoy-external had none in the window. Live requests through 192.168.1.18 now answer 302 (app redirect), and the bouncer logs no ERROR lines. Total outage: 06:36Z to 16:43Z.
- [verified] The merged LAPI config keeps `max_items 5000` / `max_age 7d` and adds `AgentsGC.LoginPassword "7d"`, so the `config.yaml.local` deep-merge works.
- [verified] On its first run the GC logged `deleted 28 expired machines (password auth)`, taking the machine count from 39 to 11. crowdsec-web-ui, blocklist-import, the LAPI's own record and both live pods were kept. The remaining stale records are younger than 7d and will age out.

### Acceptance criteria status

1. AC1 — PARTIAL. The script logic is proven by M2 run2/run3. A true in-place restart can only happen on a node reboot, so live confirmation is pending the next planned reboot. At that point also measure M1: `crowdsec-agent`/`appsec` init log should say "reusing stored LAPI credentials" (emptyDir survived) or show the suffixed fallback.
2. AC2 — DONE (M2).
3. AC3 — DONE for records older than 7d. The rest age out (up to ~14d if they carry alerts).
4. AC4 — DONE for agent/appsec (new names registered first try). See the follow-up below on the LAPI Recreate window.
5. AC5 — DONE (helm template + kustomize render, pre-commit green, bouncer and SecurityPolicies untouched).

### Follow-ups (out of scope)

- [follow-up] A rollout of the crowdsec-lapi Deployment (`strategy: Recreate`, 1 replica, RWO PVC) gives a short fail-closed 503 window on envoy-internal. Measured as 16:43:28-16:43:30Z during this deploy. This is pre-existing; worth its own item if it matters.
- [follow-up] The `flux` CLI does not run on the workstation: the mise lock for `aqua:fluxcd/flux2@2.10.0` still points at the 2.9.6 download URL, and `mise lock` regenerates it.
- [follow-up] BlackboxProbeFailed on `nas.lan:2049` (NFS) since 06:44Z is unrelated to this item.

## Related

- relates_to [[envoy-crowdsec-bouncer]]
- relates_to [[crowdsec-psa-removal-and-official-chart-migration]]
- relates_to [[networking]]
- relates_to [[observability]]
