# Role Bundles

Use this reference when a task maps naturally to an agent-like specialization but the repo should stay Codex-native rather than introducing a separate static agent layer.

## Current Bundles

### Designer

Use for architecture questions, tradeoff analysis, and proposal review.

- `architecture-review`
- `flux-gitops` when shared GitOps wiring is part of the design
- `networking-platform` when ingress or exposure design is involved
- `cloudflare-terraform` when Cloudflare resource shape matters

Expected output:

- context
- options
- recommendation
- high-level implementation requirements
- risks and open questions

### Implementer

Use for normal repository changes.

- combine the domain skill for the touched area
- add `taskfiles`, `versions-renovate`, or `sops-secrets` when those concerns are part of the change

Expected output:

- direct implementation
- lightweight validation
- clear statement of what changed and what remains local-only

### Troubleshooter

Use for debugging without jumping straight to mutation.

- `sre`
- `flux-gitops` for GitOps or reconcile issues
- `networking-platform` for ingress and edge failures
- `volsync` for backup and restore issues
- `external-secrets` or `sops-secrets` for secret-related failures

Expected output:

- symptom
- evidence
- root cause or ranked hypotheses
- safest remediation options

### Security Review

Use for hardening or risk review, not open-ended offensive testing by default.

- `security-review`
- start from the touched domain skill
- add `architecture-review` when the question is about blast radius or design-level exposure
- add `sre` when the issue involves an active failure or incident

Expected output:

- concrete risk
- affected components
- likely impact
- remediation

## Rules

- Prefer role bundles over inventing a new static agent definition unless the runtime actually supports it.
- Add a new dedicated skill only when the role relies on repeated procedures that do not fit existing skills cleanly.
