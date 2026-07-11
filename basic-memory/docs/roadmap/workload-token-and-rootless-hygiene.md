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
