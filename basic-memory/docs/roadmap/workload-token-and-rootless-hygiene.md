---
title: workload-token-and-rootless-hygiene
type: roadmap
permalink: home-ops/docs/roadmap/workload-token-and-rootless-hygiene
topic: Token + rootless hygiene for the remaining workloads
status: proposed
priority: low
scope: Set automountServiceAccountToken:false on the platform pods that do not call
  the API, and bring the two root-running apps (wallos, calibre-web-automated) and
  the one RW-rootfs app (maintainerr) up to the rootless/hardened baseline where their
  images allow.
rationale: Finishing the hardening baseline on the last few workloads makes the whole
  fleet uniformly rootless and token-minimal — the clean prerequisite for enforcing
  restricted PSS everywhere.
related_areas:
- k8s-workloads
---

# Token + rootless hygiene for the remaining workloads

## Metadata (observation-form, schema validation)

- [topic] Token + rootless hygiene for the remaining workloads
- [status] proposed
- [priority] low

## What we gain

- No workload carries an API token it does not use.
- The fleet reaches a uniform rootless / dropped-caps baseline.
- Unblocks enforce=restricted PSS on the app namespaces.

## What to do

1. Set automountServiceAccountToken:false on the default-SA platform pods (onepassword-connect, victoria-logs-server, kopia-maint jobs, …).
2. Re-add a scoped capabilities.drop to wallos (keep only the SETGID/SETUID it needs).
3. Evaluate a non-root path for calibre-web-automated; set readOnlyRootFilesystem on maintainerr.
4. Verify each app still starts and functions; re-check under PSS warn mode.

## Related

- relates_to [[k8s-workloads]]
- relates_to [[pod-security-admission-enforcement]]

## Execution plan (research-backed)

### Current state
- `wallos`: `kubernetes/apps/selfhosted/wallos/app/helmrelease.yaml:22-23` runAsNonRoot=false, runAsUser=0; :56 APE=false; :58 roRoot=false; :60 `capabilities: { drop: ["ALL"] }` is **commented out** (the note says php-fpm setgid(82) failed).
- `calibre-web-automated`: `kubernetes/apps/media/calibre-web-automated/app/helmrelease.yaml:23-24` runAsNonRoot=false, runAsUser=0 (S6 overlay); :102 APE=true; :103 roRoot=false; :104-107 caps drop [...] + **add [CHOWN,SETUID,SETGID,FOWNER,DAC_OVERRIDE]**.
- `maintainerr`: `kubernetes/apps/downloads/maintainerr/app/helmrelease.yaml:21-22` runAsNonRoot=true, runAsUser=10001; :59 APE=false; :60 roRoot=false; :61 drop ALL. Only gap is roRoot.
- A few platform pods run under the `default` SA with a mounted token (audit: external-secrets/onepassword-connect, observability/victoria-logs-server, volsync-system/kopia-maint jobs) — negligible privileges but unnecessary mounts.

### Target state
- No workload mounts an unused API token; the fleet is uniformly rootless/dropped-caps so `restricted` PSS can be enforced on selfhosted + media.

### Implementation steps
1. **Disable automount on API-less platform pods.** Find them:
   ```bash
   kubectl get pods -A -o json | jq -r '.items[] | select(.spec.automountServiceAccountToken != false and .spec.serviceAccountName=="default") | "\(.metadata.namespace)/\(.metadata.name)"'
   ```
   For each owning manifest set `automountServiceAccountToken: false` (bjw-s: under `defaultPodOptions` or the controller's pod spec). Targets: onepassword-connect, victoria-logs-server, kopia-maint job template.
2. **wallos** — re-add a scoped capability drop instead of nothing. In `helmrelease.yaml:60`, replace the commented line with a drop-all-plus-keep of the caps php-fpm actually needs:
   ```yaml
   capabilities:
     drop: ["ALL"]
     add: ["SETGID", "SETUID", "CHOWN"]   # php-fpm master needs setgid(82)/setuid; trim by testing
   ```
   Test the pod starts + the app works; remove any cap that isn't required. (This keeps it root-but-capability-bounded; full non-root is a bigger change gated on the image.)
3. **calibre-web-automated** — this is the `media` PSS blocker. Options, in preference order:
   a. Try the linuxserver-style `PUID/PGID` env to run S6 as non-root, dropping runAsUser=0 + the added caps; test thoroughly.
   b. If the image cannot run non-root, **isolate calibre in its own namespace** so `media` can still be enforced at baseline/restricted, and set that namespace to `privileged` (documented exception).
   c. If neither, document the accepted exception and keep media at warn-only.
4. **maintainerr** — set `readOnlyRootFilesystem: true` (:60) and add an `emptyDir` for any writable path it needs (check its logs for write failures; typically `/tmp` and its data dir which is already a PVC).
5. Commit per app: `🔒 fix(<app>): tighten securityContext / drop unused SA token`.

### Verification
- `kubectl get pod ... -o jsonpath='{.spec.automountServiceAccountToken}'` → false for the platform pods.
- Each edited app rolls out and functions (exercise it): wallos saves data, calibre serves books, maintainerr runs its rules.
- `kubectl label --dry-run=server ns selfhosted pod-security.kubernetes.io/enforce=restricted` → no violation from wallos after the fix.

### Rollback & safety
- Revert the helmrelease edits; pods restart to the prior spec.
- **Risk:** an over-aggressive cap drop or roRoot flip makes a container crashloop (e.g. php-fpm setgid, calibre S6 init). Change one app at a time, watch the rollout (`kubectl rollout status`), keep the previous values handy. This is why it precedes the PSS enforce flip.

### Gotchas & dependencies
- Prerequisite for `pod-security-admission-enforcement` reaching `restricted` on selfhosted and `baseline/restricted` on media.
- S6-overlay images (calibre) often genuinely need root at init — don't force it; isolate instead.

### Effort
M (~0.5 day; calibre is the uncertain part — may become its own isolate-namespace task).
