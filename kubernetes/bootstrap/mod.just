set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# Bootstrap recipes (stage chain) will be populated when implementing
# docs/migration/04-bootstrap-helmfile.md. For now only a default listing
# recipe exists so the root .justfile mod import resolves.

[private]
[script]
default:
    just -l k8s-bootstrap
