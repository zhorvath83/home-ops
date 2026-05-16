# Claude Project Instructions

## Project Location

Working Directory: `/Users/zhorvath83/Projects/personal/home-ops`

All file operations and git commands should be executed relative to this path.

## AI Instructions

Read the root `CLAUDE.md` first, then follow the `CLAUDE.md` files in subdirectories down to the target path. See the root `CLAUDE.md` for traversal rules.

## Cluster Access Policy

Read-only `kubectl`, `flux`, and the read-only `just k8s` / `just volsync` recipes are pre-allowed in `.claude/settings.json`. Direct inspection of Kubernetes Secret resources is denied: debug secret delivery via `ExternalSecret`, `ClusterSecretStore`, events, or dependent workloads instead. Cluster-mutating actions (`just k8s-bootstrap cluster`, `just talos get-kubeconfig`, `just talos apply-node`, `just talos upgrade-*`, `just talos reset-*`, `just talos reboot-node`, `just volsync restore`) require explicit user approval per invocation.
