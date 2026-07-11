---
title: cloudflare-access-terraform-parity
type: roadmap
permalink: home-ops/docs/roadmap/cloudflare-access-terraform-parity
topic: Full IaC parity for Cloudflare Access — every edge authz rule in Terraform
status: proposed
priority: medium
scope: Bring the complete live Cloudflare Access application/policy set (including
  the auth/id issuer hostnames) under provision/cloudflare Terraform, so the edge
  authorization model is fully reproducible from code.
rationale: When Terraform is the complete, authoritative definition of edge authz,
  the entire external security boundary is reviewable, diff-able, and rebuildable
  — no surprise dashboard state, no drift during an apply or a disaster rebuild.
related_areas:
- cloudflare
- iam
options:
- Import existing + codify
- Recreate under Terraform where import is messy
---

# Full IaC parity for Cloudflare Access — every edge authz rule in Terraform

## Metadata (observation-form, schema validation)

- [topic] Full IaC parity for Cloudflare Access — every edge authz rule in Terraform
- [status] proposed
- [priority] medium

## What we gain

- The edge authorization model becomes reproducible and reviewable end to end.
- A terraform apply or a rebuild can never silently change or lose access rules.
- Confidence that the audited posture equals the running posture.

## What to do

1. Reconcile live CF Access apps/policies against provision/cloudflare/access.tf — especially the auth/id issuer hostnames.
2. Import any dashboard-only apps into Terraform state and codify their intended policies.
3. Add a read-only terraform plan drift check in CI to catch future divergence.
4. Verify: a clean plan with no diff against live; login flows unaffected.

## Options

1. Import existing + codify
2. Recreate under Terraform where import is messy

## Related

- relates_to [[cloudflare]]
- relates_to [[iam]]
