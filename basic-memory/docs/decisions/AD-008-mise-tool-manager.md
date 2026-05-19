---
title: AD-008-mise-tool-manager
type: decision
permalink: home-ops/docs/decisions/ad-008-mise-tool-manager
decision_id: AD-008
topic: Adopt mise as the tool-version manager
status: active
decided_at: '2025-10-01'
decision: 'Tool versions are pinned in `.mise.toml`. Tools tracked: `talosctl`, `helmfile`,
  `kubectl`, `flux`, `just`, `op`, `minijinja-cli`, `yq`, `gum`, `sops`, `age`, `pre-commit`,
  `terraform`.'
rationale: 'All three reference repositories use mise Renovate-compatible — `.mise.toml`
  is followed by Renovate `regexManagers` Local reproducibility: anyone working on
  the repo gets unified tool versions'
tradeoffs: mise install is one extra setup step (one-time)
---

# AD-008 — Adopt mise as the tool-version manager

## Metadata (observation-form, schema validation)
- [decision_id] AD-008
- [status] active
- [decided_at] 2025-10-01
- [topic] Adopt mise as the tool-version manager

## Decision
Tool versions are pinned in `.mise.toml`. Tools tracked: `talosctl`, `helmfile`, `kubectl`, `flux`, `just`, `op`, `minijinja-cli`, `yq`, `gum`, `sops`, `age`, `pre-commit`, `terraform`.

## Rationale
- All three reference repositories use mise
- Renovate-compatible — `.mise.toml` is followed by Renovate `regexManagers`
- Local reproducibility: anyone working on the repo gets unified tool versions

## Tradeoffs
- mise install is one extra setup step (one-time)

## Related
_No AreaReference link — repo-tooling level decision._
