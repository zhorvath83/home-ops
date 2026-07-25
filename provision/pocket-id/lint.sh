#!/usr/bin/env bash
# Cross-checks clients.yaml against the Flux ks.yaml tree so an app can never carry the
# gateway-oidc component without a matching Pocket ID client, or the other way round.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
registry="${repo_root}/provision/pocket-id/clients.yaml"
status=0

fail() {
    printf '  \033[31m✗\033[0m %s\n' "$1"
    status=1
}

declare -A registry_sub
while IFS=$'\t' read -r app sub; do
    registry_sub["${app}"]="${sub}"
done < <(yq -r '.clients | to_entries[] | select(.value.gate == "envoy") | [.key, .value.subdomain] | @tsv' "${registry}")

declare -A ks_sub
while IFS=$'\t' read -r app sub; do
    [ -n "${app}" ] || continue
    ks_sub["${app}"]="${sub}"
done < <(
    find "${repo_root}/kubernetes/apps" -name ks.yaml -print0 |
        xargs -0 yq -r '
            select(.kind == "Kustomization")
            | select(((.spec.components // []) | map(select(test("gateway-oidc"))) | length) > 0)
            | [.spec.postBuild.substitute.APP,
               (.spec.postBuild.substitute.APP_SUBDOMAIN // .spec.postBuild.substitute.APP)]
            | @tsv
        '
)

for app in "${!ks_sub[@]}"; do
    if [ -z "${registry_sub[${app}]+x}" ]; then
        fail "${app}: uses the gateway-oidc component but has no 'gate: envoy' entry in clients.yaml"
    elif [ "${registry_sub[${app}]}" != "${ks_sub[${app}]}" ]; then
        fail "${app}: subdomain mismatch — clients.yaml '${registry_sub[${app}]}' vs ks.yaml '${ks_sub[${app}]}'"
    fi
done

for app in "${!registry_sub[@]}"; do
    if [ -z "${ks_sub[${app}]+x}" ]; then
        fail "${app}: declared 'gate: envoy' in clients.yaml but no ks.yaml pulls in the gateway-oidc component"
    fi
done

# Mirrors the Terraform precondition: an empty group list disables Pocket ID's group
# restriction entirely, so it must be caught before apply too.
while IFS= read -r app; do
    fail "${app}: no allowed group — Pocket ID would let every account authorize"
done < <(yq -r '.clients | to_entries[] | select((.value.groups // []) | length == 0) | .key' "${registry}")

known_groups="$(yq -r '.groups | keys | .[]' "${registry}")"
# shellcheck disable=SC2016 # $a is a yq binding, not a shell variable
while IFS=$'\t' read -r app group; do
    [ -n "${group}" ] || continue
    grep -qxF "${group}" <<<"${known_groups}" || fail "${app}: references undefined group '${group}'"
done < <(yq -r '.clients | to_entries[] | .key as $a | (.value.groups // [])[] | [$a, .] | @tsv' "${registry}")

if [ "${status}" -eq 0 ]; then
    printf '  \033[32m✓\033[0m clients.yaml and the ks.yaml tree agree\n'
fi
exit "${status}"
