---
title: AD-006-helmfile-bootstrap
type: decision
permalink: home-ops/docs/decisions/ad-006-helmfile-bootstrap
decision_id: AD-006
topic: Helmfile-based bootstrap, retiring Ansible K3s
status: active
decided_at: '2025-10-01'
decision: The current `provision/kubernetes` (Ansible + xanmanning.k3s role) is retired.
  The new cluster bootstrap runs through a `kubernetes/bootstrap/helmfile.d/` chain.
rationale: 'Talos self-installs (talosctl apply-config + bootstrap) — no host-prep
  Ansible needed The post-Talos Kubernetes setup (Cilium, CoreDNS, cert-manager, ESO,
  Flux) is simpler and more reproducible declaratively via helmfile Helmfile `needs:`
  chain gives a deterministic install order: Cilium → CoreDNS → cert-manager → ESO
  → onepassword-connect → Flux CRDs installed out-of-band (`00-crds.yaml`) eliminate
  the `dependsOn` web on the Flux side'
tradeoffs: Part of the Ansible knowledge is "lost" — but it was K3s-specific and no
  longer relevant Helmfile + minijinja + op-inject tooling has to be learned
related_areas:
- talos-cluster
- flux-gitops
---

# AD-006 — Helmfile-based bootstrap, retiring Ansible K3s

## Metadata (observation-form, schema validation)

- [decision_id] AD-006
- [status] active
- [decided_at] 2025-10-01
- [topic] Helmfile-based bootstrap, retiring Ansible K3s

## Decision

The current `provision/kubernetes` (Ansible + xanmanning.k3s role) is retired. The new cluster bootstrap runs through a `kubernetes/bootstrap/helmfile.d/` chain.

## Rationale

- Talos self-installs (talosctl apply-config + bootstrap) — no host-prep Ansible needed
- The post-Talos Kubernetes setup (Cilium, CoreDNS, cert-manager, ESO, Flux) is simpler and more reproducible declaratively via helmfile
- Helmfile `needs:` chain gives a deterministic install order: Cilium → CoreDNS → cert-manager → ESO → onepassword-connect → Flux
- CRDs installed out-of-band (`00-crds.yaml`) eliminate the `dependsOn` web on the Flux side

## Tradeoffs

- Part of the Ansible knowledge is "lost" — but it was K3s-specific and no longer relevant
- Helmfile + minijinja + op-inject tooling has to be learned

## Related

- relates_to [[talos-cluster]]
- relates_to [[flux-gitops]]
