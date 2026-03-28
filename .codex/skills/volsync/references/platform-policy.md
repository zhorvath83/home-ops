# Platform Policy

Use this reference when changing cluster-wide backup behavior.

## Default Model

- the shared component defines default schedule, retention, and storage behavior
- the VolSync platform subtree defines operator resources and jitter policy

## Scheduling Policy

- backup timing is a platform concern by default, not an app concern
- the normal model is shared schedule plus cluster-level jitter for mover jobs
- do not introduce per-app schedule overrides just to spread start times when the jitter policy already covers the need
- reserve explicit app-level overrides for genuine exceptions such as unusually large backups or strict quiet windows

When changing timing behavior, inspect both the component defaults and the jitter policy together.
