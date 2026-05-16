#!/usr/bin/env -S just --justfile

set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[group: 'k8s-bootstrap']
mod k8s-bootstrap "kubernetes/bootstrap"

[group: 'k8s']
mod k8s "kubernetes"

[group: 'talos']
mod talos "kubernetes/talos"

[group: 'volsync']
mod volsync "kubernetes/volsync"

[group: 'omv']
mod omv "provision/openmediavault"

[group: 'cloudflare']
mod cloudflare "provision/cloudflare"

[group: 'ovh']
mod ovh "provision/ovh"

[group: 'sops']
mod sops "provision/sops"

[group: 'openwrt']
mod openwrt "provision/openwrt"

[private]
[script]
default:
    just -l

[private]
[script]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[private]
[script]
template file *args:
    minijinja-cli "{{ file }}" {{ args }} | op inject
