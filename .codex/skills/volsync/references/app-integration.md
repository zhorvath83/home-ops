# App Integration

Use this reference when wiring backups into an application workload.

## Standard Model

- the shared backup model lives in `kubernetes/components/volsync/`
- app workloads opt in through the Flux `components:` hook
- app-specific values usually come from `postBuild.substitute`

Common knobs include:

- `APP`
- `APP_UID`
- `APP_GID`
- `VOLSYNC_CAPACITY`
- `VOLSYNC_CACHE`
- `VOLSYNC_COMPRESSION`
- `VOLSYNC_PARALLELISM`
- `VOLSYNC_SCHEDULE`
- retention overrides and storage-class overrides when truly needed

## Rules

- prefer the shared component over app-local backup manifests
- treat `APP_UID` and `APP_GID` as the ownership source of truth when the workload uses VolSync
- only add schedule overrides for real exceptions, not for routine staggering
