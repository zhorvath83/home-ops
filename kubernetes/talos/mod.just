set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos recipes (schematic, install, apply-node, upgrade, reset, …) will be
# populated when implementing docs/migration/02-talos-bootstrap.md. For now
# only a default listing recipe exists so the root .justfile mod import
# resolves.

[private]
[script]
default:
    just -l talos
