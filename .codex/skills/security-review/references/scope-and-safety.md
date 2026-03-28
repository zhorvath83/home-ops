# Scope And Safety

Use this reference to keep security work aligned with the repo's operating model.

## Default Scope

- review exposure and trust boundaries
- review hardening regressions and exceptions
- review secret handling and credential scope
- review whether misuse would be detected

## Safety Rules

- no destructive testing
- no credential exfiltration
- no data loss or denial-of-service
- no direct mutation of protected environments just to probe a hypothesis
- for live clusters, prefer repo-state review plus read-only reconnaissance unless the user explicitly asks for more

## Evidence Standard

- prefer real repo state and live configuration over generic checklists
- distinguish theoretical concern from practical exploitability
- call out when a finding depends on an assumption that has not been verified
