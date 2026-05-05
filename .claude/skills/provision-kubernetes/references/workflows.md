# Workflows

Use this reference when choosing commands and validation for provisioning changes.

## Canonical Entry Points

Prefer the existing task wrappers:

- `task an:list`
- `task an:ping`
- `task an:prepare`
- `task an:install`
- other nearby `an:` tasks as needed

## Change Handling

- inventory change: favor the smallest safe listing or connectivity check
- playbook change: inspect the matching task wrapper and related templates
- dependency change: keep Python, role, and collection files aligned with each other

If validation cannot run, say whether the blocker is missing tooling, credentials, SSH reachability, or cluster access.
