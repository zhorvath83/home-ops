---
title: workload-token-and-rootless-hygiene
type: roadmap
permalink: home-ops/docs/roadmap/workload-token-and-rootless-hygiene
topic: Token + rootless hygiene for the remaining workloads
status: done
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


## Accepted exceptions

### wallos — caps cannot be dropped (2026-07-29, accepted)

The roadmap step 2 ("re-add a scoped capabilities.drop to wallos, keep only SETGID/SETUID/CHOWN")
is a **dead end** and is dropped as a won't-do. Evidence:

- The manifest already records the failure inline
  (`kubernetes/apps/selfhosted/wallos/app/helmrelease.yaml:58`):
  `ERROR: [pool www] failed to setgid(82): Operation not permitted (1)` — php-fpm's www pool
  drops to gid 82 at startup, which needs CAP_SETGID. Dropping ALL caps (even with scoped re-adds
  of SETGID/SETUID/CHOWN) was tried repeatedly by the operator and by others; the container
  crashloops. Wallos must run as root with the default capability set.
- Confirmed empirically ("már próbáltam, más is próbálta, gyakorlatilag semmiben nem lehet").

Wallos is at its hardening floor already: root (runAsUser 0), but tokenless
(`automountServiceAccountToken: false`), seccomp `RuntimeDefault`, `allowPrivilegeEscalation: false`,
and `readOnlyRootFilesystem: false` is required (php-fpm writes `/var/log/startup.log`).
No manifest change is made; the existing inline comment is the accurate record.

### Implication for PSS

wallos cannot pass `restricted` PSS (root + non-dropped caps) and cannot pass `baseline` either
(baseline forbids added caps, but wallos needs the default cap set which includes SETGID — baseline
allows the default set, only forbids *added* caps, so wallos is baseline-eligible on caps; the root
uid is the restricted blocker). For namespace-wide `restricted` enforcement on `selfhosted`,
wallos would need an isolated/privileged namespace exception, same as calibre-web-automated.


### maintainerr — readOnlyRootFilesystem not supported (2026-07-29, accepted)

Roadmap step "set readOnlyRootFilesystem on maintainerr" is a **won't-do**. The image does not support
a read-only rootfs even though the manifest already provides emptyDir mounts for `/tmp` and
`/opt/data/logs` (`kubernetes/apps/downloads/maintainerr/app/helmrelease.yaml:95-103`) — the app writes
to other paths and crashloops under roRoot. Confirmed empirically (operator experience). maintainerr
stays at its current floor: rootless (runAsUser 10001), `automountServiceAccountToken: false`,
`capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false`, seccomp `RuntimeDefault`, and
`readOnlyRootFilesystem: false` (required). No manifest change.

### calibre-web-automated — cannot be hardened (2026-07-29, accepted)

Roadmap step 3 (non-root path for calibre-web-automated) is a **won't-do** — "cwa nem szigorítható".
The image is an S6-overlay root image (runAsUser 0, APE=true, caps add
[CHOWN,SETUID,SETGID,FOWNER,DAC_OVERRIDE] at `kubernetes/apps/media/calibre-web-automated/app/helmrelease.yaml`);
it cannot run non-root. This is the roadmap's option (c): documented accepted exception. cwa is the
`media` namespace PSS blocker — if `media` moves to baseline/restricted enforcement, cwa needs an
isolated/privileged namespace exception (same conclusion as wallos for `selfhosted`).

## Roadmap resolution (2026-07-29)

All items resolved — implemented where the image allows, accepted-exception where it does not:

- 1a/1b/1c (token hygiene) — **done** (this roadmap session series).
- 2 wallos scoped caps — **accepted exception** (php-fpm setgid(82) needs root + default caps).
- 3 calibre-web-automated non-root — **accepted exception** (S6-overlay root image).
- 4 maintainerr roRoot — **accepted exception** (image does not support read-only rootfs).

The token-hygiene goal (no API-less workload mounts an unused token) is fully achieved. The rootless
goal is achieved where images allow; wallos, calibre-web-automated, and maintainerr stay at their
image-imposed floors, each with a documented inline + BM rationale. These three are the PSS-enforcement
blockers recorded in `docs/roadmap/pod-security-admission-enforcement` — namespace-wide `restricted`
on `selfhosted` and `media` will require isolated/privileged namespace exceptions for wallos and cwa.
