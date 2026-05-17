#!/usr/bin/env bash
# Resolve the active control-plane node name.
#
# Shared between:
#   - kubernetes/talos/mod.just      (controller_node)
#   - kubernetes/bootstrap/mod.just  (controller)
#
# Prints the first endpoint from the active talosconfig (set by
# `talosctl config endpoint`). Falls back to the canonical control-plane
# hostname when talosconfig is absent (fresh repo clone, pre-bootstrap)
# or its endpoints list is null/empty (between `gen config --force` and
# `config endpoint` inside gen-talosconfig).
#
# Single-line output is critical — multi-line would break downstream
# template substitution and `for` loop consumption in the calling mods.
#
# CHECK ON RENAME: if the primary control-plane node ever gets renamed
# (cf. commits 8de1fa5cc / 19d5c9fe5 for the cp0-k8s -> k8s-cp0
# precedent), update FALLBACK below AND the matching filename under
# kubernetes/talos/nodes/<NAME>.yaml.j2.
set -euo pipefail

FALLBACK='k8s-cp0'

talosctl config info -o json 2>/dev/null \
  | jq -r --arg fb "${FALLBACK}" '.endpoints[0] // $fb' 2>/dev/null \
  || echo "${FALLBACK}"
