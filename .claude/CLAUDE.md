# Claude Project Instructions

## Project Location
Working Directory: `/Users/zhorvath83/Projects/personal/home-ops`

All file operations and git commands should be executed relative to this path.

## AI Instructions
Read and follow the `AGENTS.md` hierarchy starting from the repository root. See `AGENTS.md` for traversal rules.

## Cluster Access Policy
Read-only `kubectl`, `flux`, and the `task fx:*` and `task vs:*` inspection wrappers are pre-allowed in `.claude/settings.json`. Direct inspection of Kubernetes Secret resources is denied: debug secret delivery via `ExternalSecret`, `ClusterSecretStore`, events, or dependent workloads instead. Cluster-mutating actions (`task fx:install`, `task ku:kubeconfig`) require explicit user approval per invocation.
