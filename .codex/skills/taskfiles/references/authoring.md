# Authoring

Use this reference when adding or reshaping Task definitions.

## File Shape

- root `Taskfile.yml` currently acts as the index and shared var holder
- child task files under `.taskfiles/` use the Task schema comment and `version: "3"`
- prefer clear `desc` text because `task list` depends on it

## Common Patterns In This Repo

- shared paths and env vars come from root vars like `ROOT_DIR`, `KUBERNETES_DIR`, `ANSIBLE_DIR`, and `TERRAFORM_DIR`
- use `dir:` when a task should run from a specific subtree
- use `preconditions:` for tools, files, and cluster objects
- use `requires:` or explicit vars when user input is mandatory
- use `interactive: true` only for truly interactive flows such as temporary debug shells
- keep namespaced task names consistent with the domain include, for example `fx:reconcile` or `tf:plan:cloudflare`

## Command Design

- prefer wrapping the canonical command already used by the repo
- keep shell logic small and readable
- if a task depends on resource names in manifests, inspect those files before renaming anything
- when a domain already has a task namespace, extend it rather than inventing a parallel one
- if no task exists for an operation, inspect the nearest task domain before adding a new namespace or command flow
