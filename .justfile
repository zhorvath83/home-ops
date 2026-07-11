#!/usr/bin/env -S just --justfile

set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[group('cluster-bootstrap')]
mod cluster-bootstrap "kubernetes/bootstrap"

[group('k8s')]
mod k8s "kubernetes"

[group('talos')]
mod talos "kubernetes/talos"

[group('volsync')]
mod volsync "kubernetes/volsync"

[group('omv')]
mod omv "provision/openmediavault"

[group('cloudflare')]
mod cloudflare "provision/cloudflare"

[group('ovh')]
mod ovh "provision/ovh"

[group('openwrt')]
mod openwrt "provision/openwrt"

# `default` must be the first recipe so that bare `just` (no args) lists
# the recipe groups instead of falling through to the next-defined recipe.
[private]
[script]
default:
    just -l

# OpenWRT provisioning lives in the private my-scripts-and-configs repo
# (declarative Ansible flow with secret-adjacent topology). This shim forwards `just openwrt <recipe> [args]` to the private repo.
# [group: 'openwrt']
# [script]
# openwrt *args:
#     cd "${HOME}/Projects/personal/my-scripts-and-configs" && just openwrt {{ args }}

[private]
[script]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[private]
[script]
template file *args:
    minijinja-cli "{{ file }}" {{ args }} | op inject
