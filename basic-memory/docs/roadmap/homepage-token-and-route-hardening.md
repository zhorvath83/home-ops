---
title: homepage-token-and-route-hardening
type: roadmap
permalink: home-ops/docs/roadmap/homepage-token-and-route-hardening
topic: Least-privilege token + gated route for the dashboard (homepage)
status: proposed
priority: low
scope: Drop the dashboards ServiceAccount token mount if unused, and confirm its externally-exposed
  route sits behind the identity gate, so the convenience dashboard carries no cluster-recon
  token and no open route.
rationale: Removing an unneeded token and gating the route makes the dashboard a pure
  presentation surface with no cluster-visibility value to an attacker.
related_areas:
- k8s-workloads
- iam
---

# Least-privilege token + gated route for the dashboard (homepage)

## Metadata (observation-form, schema validation)

- [topic] Least-privilege token + gated route for the dashboard (homepage)
- [status] proposed
- [priority] low

## What we gain

- The dashboard stops being a source of cluster topology for reconnaissance.
- Its external route matches the auth posture of the other protected apps.
- Clean least-privilege on a widely-reachable app.

## What to do

1. If the Kubernetes widgets are not required, set automountServiceAccountToken:false; if they are, keep the read-only ClusterRole but confirm it is the minimum.
2. Attach forward-auth/OIDC to the dash route (coordinated with forward-auth-coverage-external-data-apps).
3. Verify: dashboard renders; no usable API token in the pod; route requires auth.

## Related

- relates_to [[k8s-workloads]]
- relates_to [[iam]]
- relates_to [[forward-auth-coverage-external-data-apps]]
