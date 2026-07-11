# Claude Project Instructions

## Project Location

Working Directory: `/Users/zhorvath83/Projects/personal/home-ops`

All file operations and git commands should be executed relative to this path.

## AI Instructions

Read the root `CLAUDE.md` first, then follow the `CLAUDE.md` files in subdirectories down to the target path. See the root `CLAUDE.md` for traversal rules.

## Cluster Access Policy

Read-only `kubectl`, `flux`, and the read-only `just k8s` / `just volsync` recipes are pre-allowed in `.claude/settings.json`. Direct inspection of Kubernetes Secret resources is denied: debug secret delivery via `ExternalSecret`, `ClusterSecretStore`, events, or dependent workloads instead. Cluster-mutating actions (`just cluster-bootstrap cluster`, `just talos get-kubeconfig`, `just talos apply-node`, `just talos upgrade-*`, `just talos reset-*`, `just talos reboot-node`, `just volsync restore`) require explicit user approval per invocation.

**Cluster commands run OUTSIDE the sandbox.** Anything reaching the cluster API (`192.168.1.11:6443`) or the Hubble relay (`127.0.0.1:4245`) — `kubectl`, `flux`, `talosctl`, and the `just k8s` / `just volsync` / `just talos` recipes — needs `dangerouslyDisableSandbox: true`. The sandbox network allowlist is domain-only and blocks these (symptom: `operation not permitted` or `dial tcp … connect`). These families are also listed in `sandbox.excludedCommands` so they bypass the sandbox automatically; the permission allow/deny list still governs what may run.

**Hubble flow analysis uses the existing recipes — do NOT hand-roll `hubble observe`.** `just k8s hubble-live-capture <secs>` records cluster-wide flows to `/tmp/hubble-live.jsonl`; `just k8s hubble-analyze <label> <verdict> <direction>` re-slices that capture (e.g. `just k8s hubble-analyze k8s:app.kubernetes.io/name=backrest DROPPED egress`); `just k8s hubble-status` checks the relay. Discover module recipes with `just <group> --list` (e.g. `just k8s --list`) — the bare `just --list` shows only top-level recipes, not module ones.
