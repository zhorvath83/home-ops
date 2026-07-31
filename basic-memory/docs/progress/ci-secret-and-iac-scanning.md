---
title: ci-secret-and-iac-scanning
type: note
permalink: home-ops/docs/progress/ci-secret-and-iac-scanning
---

# ci-secret-and-iac-scanning — execution progress

## Metadata (observation-form)

- [topic] Execution state for the ci-secret-and-iac-scanning roadmap
- [status] done
- [roadmap] [[ci-secret-and-iac-scanning]] (docs/roadmap)
- [priority] low
- [created] 2026-07-31

## Execution model (decided with human, 2026-07-31)

- [decision] Scope: **gitleaks only**. The roadmap's companion trivy/IaC job was dropped
  after research showed it is structurally incapable of finding anything in this repo
  (evidence below). The human chose this over shipping a guaranteed-green drift-guard.
- [decision] Delivery: direct commits to `main` (repo norm; Flux watches refs/heads/main).
  CI-only change, zero cluster impact.

## The roadmap's IaC premise was wrong (evidence)

The roadmap expected the first trivy run to surface pre-existing findings such as
`backup-immutability-object-lock` and `cloudflare-api-token-migration`. It cannot:

- [evidence] trivy 0.72.0 ships terraform checks for **aws, azure, cloudstack, digitalocean,
  github, google, kubernetes, nifcloud, openstack, oracle** only
  (`policies/cloud/policies/` in the checks bundle). There is **no cloudflare and no ovh**
  provider coverage — the 2 grep hits for "cloudflare" in the whole bundle are both false
  positives (cloudfront / nifcloud strings). This repo's only providers are cloudflare, ovh
  and pocket-id.
- [evidence] `trivy config provision/` produced **153 successes, 0 failures** across the three
  root modules. `checkov 3.3.8 -d provision --framework terraform` produced **1 passed,
  0 failed**; checkov has **0** Cloudflare checks (its provider prefixes cover ALI, ANSIBLE,
  ARGO, AWS, AZURE, BCW, BITBUCKET, CIRCLECI, DIO, DOCKER, GCP, GHA, GIT, GITHUB, GITLAB, GLB,
  K, LIN, NCP, OCI, OPENAPI, OPENSTACK, PAN, SECRET, TC, TF, YC — no cloudflare, no ovh).
- [evidence] `trivy config kubernetes/` produced **18459 successes, 0 failures** over 293
  detected config files. The tree is pure Flux CRs: `grep '^kind:'` yields Kustomization 153,
  HelmRelease 56, CiliumNetworkPolicy 35, OCIRepository 28, ExternalSecret 27 and so on, with
  **zero** raw Deployment/Pod/StatefulSet/DaemonSet. Trivy's KSV workload checks have nothing
  to bind to.

Conclusion: an IaC-misconfiguration gate over this repo's *source* is a guaranteed-zero check.

## Where the real IaC signal lives (surveyed, deliberately NOT gated)

`flux-local build all --enable-helm --skip-crds kubernetes/flux/cluster` renders the charts
into real workloads (58 Deployment, 6 DaemonSet, 1 StatefulSet, 1 CronJob, 4 Job).
`trivy config` on that rendered output produced **755 failures across 45 check classes**.

- [observation] 616 of 755 sit in platform/infra namespaces, i.e. inside third-party charts:
  cilium DaemonSet 111, democratic-csi-node 87, hubble-ui 29, k8tz 17. Only 139 touch
  self-authored app namespaces.
- [observation] The CRITICAL class is entirely context-blind: KSV-0041 fires as
  "ClusterRole 'cert-manager-cainjector' shouldn't have access to manage resource 'secrets'"
  — managing secrets is precisely cert-manager's function. Same for
  external-secrets-cert-controller and cilium-operator.
- [decision] Not usable as a blocking gate: permanently red, and the ignore file would need
  re-curation on every chart bump. Belongs in its own hardening roadmap item, scoped to the
  139 self-authored findings.

## What shipped

`.github/workflows/security-scan.yaml` — job `Gitleaks`, triggers `workflow_dispatch` plus
`pull_request` (main) plus `push` (main), `permissions: contents: read`, concurrency group
matching the flux-local convention.

Two design points that are not obvious:

- [decision] **The version is read from `.mise.toml` at runtime** with a small `sed`
  extraction rather than pinned a second time in the workflow. `.mise.toml` already pins
  `aqua:zricethezav/gitleaks = 8.30.1` and Renovate maintains it, and the same binary backs
  the `gitleaks protect --staged` pre-commit hook — so the CI lane and the local lane cannot
  drift apart. Single source of truth.
- [decision] **Plain binary download, not an action or container.** Rejected alternatives:
  - `gitleaks/gitleaks-action` is **proprietary** (its action.yml carries a Gitleaks LLC
    "All Rights Reserved" notice and a commercial EULA) and gates organizations behind a
    license-key secret.
  - `jdx/mise-action` looked DRY-est but is **fragile**: a failing template shell-out inside
    `.mise.toml`'s `[env]` aborts mise outright (verified — mise errors with a tera template
    trace, it does not warn-and-continue), and `.mise.toml` derives `GITHUB_TOKEN` from a
    `gh auth token` shell-out, which has no reason to succeed on a runner. Plus CI would need
    `mise trust` handling.
  - A `docker://` container step would match the flux-local convention, but a root container
    step against a uid-1001 workspace risks git's dubious-ownership refusal, and the local
    docker daemon was down so the claim could not be settled empirically. Not shipped on a guess.

## Bug found and fixed by the adversarial review pass

The first draft verified the download by piping a `grep` of the checksums file into
`sha256sum -c -`. That is **unsafe**:

- [evidence] GitHub's default shell is `/usr/bin/bash -e {0}` — confirmed in the live run log.
  There is **no pipefail**, so the pipeline's status is `sha256sum`'s alone, and `bash -e`
  does not abort on a failing non-final pipeline member.
- [evidence] Local test: when `grep` matches nothing (the case where a future release renames
  the asset), the pipeline exits **0** — verification is silently skipped while the job goes green.

Replaced with an explicit `awk` extraction, an empty-guard, and a string comparison of the
expected and actual digests. All three branches were then tested end-to-end against the real
8.30.1 artifacts: happy path verified OK; renamed asset correctly failed; byte-appended archive
correctly failed; the extracted file is a real `ELF 64-bit LSB executable, x86-64`.

## .gitleaksignore and its residual risk

Two entries, both `generic-api-key` false positives in files deleted years ago, each matching
a secret *name* rather than a value:

- `40450123…:provision/kubernetes/inventory/group_vars/kubernetes/os.yml:generic-api-key:6` —
  an Ansible 1Password lookup naming the item that holds an SSH **public** key.
- `ea47d333…:cluster/core/longhorn-system/longhorn-system-helm-release.yaml:generic-api-key:52` —
  a Longhorn `backupTargetCredentialSecret` value, which is a Kubernetes Secret name.

- [observation] A reviewer flagged that a PR could add a fingerprint to hide a secret it
  introduces. Measured: fingerprints have the shape `commit:file:rule:line`, so they are
  **commit-SHA scoped**. Test — the correct fingerprint suppressed 1 of 2 findings; the same
  line with only the 40-hex commit SHA zeroed suppressed **nothing** (2 of 2 remained). An entry
  therefore cannot be written ahead of a commit whose SHA is not yet final, which is the normal
  case under squash/rebase merges. Residual risk is real but narrow, and a `.gitleaksignore`
  diff is conspicuous in review.

## Verification (all executed)

- [verified] Local full history with the allowlist: 7858 commits, "no leaks found", exit 0.
- [verified] Acceptance test — randomly generated secrets planted in a throwaway repo, scanned
  with the **exact** CI command: "leaks found: 2", **exit 1**.
- [verified] The roadmap's own suggested test would have misled: the canonical AWS
  documentation example credential pair is **not** flagged, because gitleaks' default config
  allowlists known example values. A planted secret must be randomly generated to be a valid test.
- [verified] `actionlint`, `zizmor --offline` ("No findings to report"), `yamllint` and
  `yamlfmt -lint` all pass; the full `pre-commit run` on the staged change is green.
- [verified] Live run `30665606262` on commit `e407b9269` (push to main): **success** in 23s —
  "7604 commits scanned", "scanned ~7.72 MB in 1.88s", "no leaks found".

## Follow-ups (not implemented)

- [followup] **GitHub native secret scanning is DISABLED on a PUBLIC repo.** The repo API
  reports `private: false` with secret scanning, push protection and non-provider patterns all
  disabled. For a public repo these are free, cover the whole history, and push protection
  blocks the secret **before it lands** — a strictly stronger control than any post-hoc CI job.
  Left for the human to decide: it is a repo-settings change, not code.
- [followup] Rendered-manifest hardening: the 139 self-authored findings out of the 755 survey.
  A first-pass triage (via a local LLM, spot-checked and partly wrong — it invented a
  `--detect-binary` flag that gitleaks 8.30.1 does not have, and mis-sorted memory-limit
  checks) suggested roughly 15 check classes are closable via HelmRelease values. Needs its own item.
- [followup] Required-status-check wiring still depends on
  [[main-branch-protection-and-commit-signing]].
- [followup] Tag pushes are not scanned. The repo currently has **0 tags** and no release
  process, so this is theoretical; revisit if tagging is ever adopted.
- [followup] `flux-local` printed a deprecation notice — it is sunsetted in favour of `flate`
  and `konflate`. Unrelated to this item but it affects the existing flux-local workflow.

## Relations

- implements [[ci-secret-and-iac-scanning]]
- relates_to [[flux-gitops]]
- relates_to [[main-branch-protection-and-commit-signing]]


## GitHub native secret scanning enabled (2026-07-31, follow-up closed)

Enabled via `gh api --method PATCH repos/zhorvath83/home-ops` with a
`security_and_analysis` body. Verified state:

- [done] `secret_scanning: enabled`
- [done] `secret_scanning_push_protection: enabled` — blocks a matching secret at push time,
  before it lands. This is now the strongest control in the chain; the gitleaks job is the
  backstop behind it.
- [verified] `GET /repos/zhorvath83/home-ops/secret-scanning/alerts` returns `[]` — the
  endpoint is live (proving scanning is actually active) with zero alerts, consistent with the
  gitleaks full-history result.

Two things did NOT get enabled, deliberately or by API limitation:

- [observation] `secret_scanning_non_provider_patterns` **cannot be set through the API** on
  this user-owned repo. The repo PATCH returns HTTP 200 and silently leaves the field
  `disabled` (retried twice, including after `secret_scanning` was already on, so it is not a
  same-call ordering problem). Neither `repos/{owner}/{repo}/code-security-configuration` nor a
  user-level `code-security/configurations` endpoint exists to carry it. It is UI-only:
  Settings → Code security → Secret scanning. **Low impact**: generic high-entropy detection is
  exactly what the gitleaks `generic-api-key` rule already covers in CI — it is the rule that
  produced both historical findings in `.gitleaksignore`.
- [decision] `secret_scanning_validity_checks` left **disabled**. It sends candidate secrets to
  the issuing provider to test whether they are still live; that is an outbound-data decision,
  not a free win, and it was never part of the agreed scope.

- [observation] Push protection was **not** verified by attempting to push a planted secret.
  Doing so on a PUBLIC repo risks writing a junk commit into permanent history if the control
  failed to engage — the exact outcome the control exists to prevent. Enablement is verified via
  the API state instead. Friction risk is low: this repo delivers all secrets via 1Password/ESO,
  so no plaintext credential is ever committed.
