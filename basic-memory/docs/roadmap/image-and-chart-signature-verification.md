---
title: image-and-chart-signature-verification
type: roadmap
permalink: home-ops/docs/roadmap/image-and-chart-signature-verification
topic: Verified image & chart provenance — cosign verification + digest pinning
status: proposed
priority: high
scope: Add cosign spec.verify to the OCIRepositories whose publishers sign (Flux controllers,
  cert-manager, Cilium, …) and move critical/platform workloads from mutable tags
  to digest pins.
rationale: Signature verification and digest pinning guarantee the cluster runs exactly
  the artifact the publisher released — the supply-chain equivalent of the verified
  git source, extending that trust anchor to containers.
related_areas:
- flux-gitops
options:
- Keyless (Fulcio/Rekor OIDC identity) — no key to manage
- Key-based cosign — for publishers without keyless
---

# Verified image & chart provenance — cosign verification + digest pinning

## Metadata (observation-form, schema validation)

- [topic] Verified image & chart provenance — cosign verification + digest pinning
- [status] proposed
- [priority] high

## What we gain

- Only publisher-signed, unmodified charts/images reconcile — a re-pushed or poisoned tag is rejected.
- Immutable digests mean what was reviewed is exactly what runs, now and on every future restart.
- Extends the git provenance guarantee to the container supply chain.

## What to do

1. Inventory which OCIRepository sources publish cosign signatures (controlplaneio Flux, jetstack, cilium, …).
2. Add spec.verify (cosign; keyless/OIDC or key) to those OCIRepositories.
3. Pin critical/platform images by digest — Renovate already supports digest pinning; keep tag+digest for readability.
4. Verify: pointing a test source at an unsigned/modified tag makes reconcile fail closed.

## Options

1. Keyless (Fulcio/Rekor OIDC identity) — no key to manage
2. Key-based cosign — for publishers without keyless

## Related

- relates_to [[flux-gitops]]
- relates_to [[main-branch-protection-and-commit-signing]]

## Execution plan (research-backed)

### Current state
- No OCIRepository carries `spec.verify` (audit: all ~35 sources `verify=` empty). Example: `kubernetes/apps/flux-system/flux-instance/app/ocirepository.yaml:12-15` pins only `tag: 0.54.1` on `oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance`.
- controlplaneio-fluxcd charts/images are cosign **keyless**-signed via GitHub Actions OIDC; cert-manager (jetstack) and cilium also publish signatures.
- Renovate already manages versions via `# renovate:` annotations (e.g. ocirepository.yaml:13).

### Target state
- The OCIRepositories whose publishers sign carry `spec.verify` (cosign), so a re-pushed/poisoned chart is rejected at fetch.
- Critical/platform container images pinned by digest.

### Implementation steps
1. **Start with the flux-instance chart** (publisher is known-signed). Edit `kubernetes/apps/flux-system/flux-instance/app/ocirepository.yaml`, add under `spec`:
   ```yaml
   spec:
     verify:
       provider: cosign
       matchOIDCIdentity:
         - issuer: "^https://token\\.actions\\.githubusercontent\\.com$"
           subject: "^https://github\\.com/controlplaneio-fluxcd/.*$"
   ```
   (Keyless verification needs no secret. Confirm the exact signing identity: `cosign verify ghcr.io/controlplaneio-fluxcd/charts/flux-instance:0.54.1 --certificate-oidc-issuer=... --certificate-identity-regexp=...`.)
2. **Roll out to other signed sources** the same way: enumerate with `kubectl get ocirepository -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,URL:.spec.url`; for each, confirm the publisher signs (`cosign verify <ref>`), then add the matching `matchOIDCIdentity`. Prioritise: flux-operator, cert-manager, cilium, kube-prometheus-stack.
3. **Digest-pin critical images.** In `.renovate/` add/confirm a rule enabling `pinDigests` (or the `docker:pinDigests` preset) so Renovate appends `@sha256:…` to platform images (kube-apiserver, cilium, cert-manager, 1password/connect, grafana). Keep the human-readable tag alongside the digest.
4. Commit per conventional style: `🔒 feat(flux): cosign-verify controlplaneio OCIRepositories`.

### Verification
- `flux reconcile source oci flux-instance -n flux-system` (dangerouslyDisableSandbox) → Ready=True with a "verified signature" event: `kubectl -n flux-system describe ocirepository flux-instance | grep -i verif`.
- Negative test (staging): point a test OCIRepository at an unsigned tag → it fails with a verification error, does not fetch.

### Rollback & safety
- Remove the `spec.verify` block and reconcile. Low blast radius: a mis-specified identity makes that ONE source fail to fetch (existing running workloads keep their last-applied state until you fix it).
- Introduce it one source at a time; watch each reconcile before moving on.

### Gotchas & dependencies
- Getting `matchOIDCIdentity` regex wrong = source stuck NotReady; always validate with the `cosign verify` CLI first.
- Not every image publisher signs — only add verify where a signature actually exists.
- Complements `main-branch-protection-and-commit-signing` (git side) — together they cover both supply-chain halves.

### Effort
M (~0.5–1 day for a staged rollout across the signed sources + digest pinning).


## Discovery findings (2026-07-11)

Read-only reconnaissance done; no manifests or cluster state changed. cosign was not installed — ran ephemerally via mise/aqua (`aqua:sigstore/cosign@3.1.1`, checksum-verified) and probed every publisher against its live tag.

### Current state (verified)
- 35 OCIRepositories total; **none** carry `spec.verify`; all Ready=True.
- Enumerated with: `kubectl get ocirepository -A -o 'custom-columns=NS:.metadata.namespace,NAME:.metadata.name,URL:.spec.url,VERIFY:.spec.verify.provider,READY:.status.conditions[-1].status'`.

### Keyless-signed with confirmed GitHub-OIDC identity (ready to configure)
All share issuer regex `^https://token\.actions\.githubusercontent\.com$`. Subjects captured live via `cosign verify <ref> --certificate-identity-regexp='.*' --certificate-oidc-issuer-regexp='.*'`:

| Source (ns) | Apps affected | matchOIDCIdentity subject regex |
|---|---|---|
| flux-instance (flux-system) | 1 controlplane | `^https://github\.com/controlplaneio-fluxcd/charts/\.github/workflows/.*$` |
| flux-operator (flux-system) | 1 controlplane | same as flux-instance |
| app-template (shared component) | ~13 apps | `^https://github\.com/bjw-s-labs/helm-charts/\.github/workflows/.*$` |
| k8s-gateway (networking) | 1 | `^https://github\.com/k8s-gateway/k8s_gateway/\.github/workflows/.*$` |
| charts-mirror/* (home-operations) | 3 (external-dns, metrics-server, volsync) | `^https://github\.com/home-operations/charts-mirror/\.github/workflows/.*$` |

Observed exact subjects (for reference):
- controlplaneio: `https://github.com/controlplaneio-fluxcd/charts/.github/workflows/release.yml@refs/tags/v0.16.3`
- bjw-s app-template: `https://github.com/bjw-s-labs/helm-charts/.github/workflows/chart-release-steps.yaml@refs/heads/main`
- k8s-gateway: `https://github.com/k8s-gateway/k8s_gateway/.github/workflows/chart-release-steps.yaml@refs/heads/master`
- home-operations charts-mirror: `https://github.com/home-operations/charts-mirror/.github/workflows/app-builder.yaml@refs/heads/main`

### Signed, but identity extraction needs follow-up
cosign verifies a signature but the cert-identity block is empty (`optional: []`) — likely a non-keyless / different signing scheme; needs per-publisher digging (possibly `spec.verify.secretRef` with a public key) before configuring:
- `cilium` (quay.io/cilium/charts/cilium), `external-secrets`, `coredns`, `victoria-logs` (single + collector), `reloader`, `home-operations/charts/tuppr`.

### Unsigned — cannot add verify
- `1password/connect`, `cert-manager` ⚠️ (**roadmap assumption was wrong** — quay.io/jetstack/charts/cert-manager is NOT cosign-signed), `democratic-csi`, `grafana-operator`, `intel-gpu-resource-driver`, `snapshot-controller`, `kube-prometheus-stack`, `blackbox-exporter`, `silence-operator`, `envoy-gateway` (mirror.gcr.io).

### Decisions still open (asked, deferred)
- **Scope for first PR**: recommended minimal start = flux-instance + flux-operator only (controlplane, lowest blast radius), then expand.
- **Delivery**: recommended branch + PR + merge (Flux only verifies live after merge to main; wrong identity → that one source NotReady, running workloads keep last-applied state).

### Next actions when resuming
1. Pick scope (min flux×2 vs. all 5 clean-keyless).
2. Add `spec.verify.provider: cosign` + `matchOIDCIdentity` (issuer+subject from table) to chosen OCIRepositories.
3. Deep-dive the 6 empty-identity sources.
4. Renovate digest-pinning as a separate workstream.
5. Verify live: `flux reconcile source oci <name> -n <ns>` → Ready + "verified signature" event; negative test on a staging source.
