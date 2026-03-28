# Validation

Use this reference after editing Taskfiles.

## Read-Back Checklist

Read together:

1. `Taskfile.yml`
2. the touched `.taskfiles/*` file
3. any repo file paths or commands the task wraps

## Consistency Checks

- verify the namespace is included from `Taskfile.yml`
- verify task names, descriptions, and referenced vars match the intended domain
- verify file paths and task-to-manifest assumptions still match the repo layout
- verify preconditions and required vars name real tools and files

## Lightweight Validation

- `task list` is the preferred quick check for root include and description integrity
- if a domain task changed, run the smallest safe task-backed check available for that namespace when the environment permits

If validation cannot run, say whether the blocker is missing `task`, missing tools, credentials, or cluster access.
