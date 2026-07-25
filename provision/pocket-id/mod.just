set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

tf_dir := justfile_dir() + '/provision/pocket-id'
cluster_settings := justfile_dir() + '/kubernetes/components/common/vars/cluster-settings.yaml'
# Shared `op run + terraform` prefix — every recipe wraps a single
# terraform subcommand with the same 1Password env injection.
tf := "op run --no-masking --env-file=./.env -- terraform"

[private]
[script]
default:
    just -l pocket-id

[doc('terraform init -upgrade (TF_VAR_* injected from ./.env via op run)')]
[script]
init:
    cd {{ tf_dir }} && {{ tf }} init -upgrade

[doc('Cross-check clients.yaml against the gateway-oidc consumers in the ks.yaml tree')]
[script]
lint:
    {{ tf_dir }}/lint.sh

[doc('terraform plan (lint runs first)')]
[script]
plan: lint
    cd {{ tf_dir }} && {{ tf }} plan

[doc('terraform apply + sync client secrets to the HomeOps/pocket-id-clients 1Password item')]
[script]
apply: lint
    cd {{ tf_dir }} && {{ tf }} apply
    just pocket-id sync-secrets

[doc('Mint a fresh secret for one client by recreating it (positional arg: app) — the app is locked out until Flux resyncs')]
[script]
rotate app:
    cd {{ tf_dir }}
    gum confirm "Rotate the Pocket ID client secret for '$1'?" || { just log info "Aborted"; exit 0; }
    {{ tf }} apply -replace="pocketid_client.this[\"$1\"]"
    just pocket-id sync-secrets

[doc('Push the client secrets from terraform state into 1Password (implied by apply/rotate)')]
[script]
sync-secrets:
    cd {{ tf_dir }}
    op item get pocket-id-clients --vault HomeOps >/dev/null 2>&1 \
      || op item create --category "Secure Note" --title pocket-id-clients --vault HomeOps >/dev/null
    secrets="$({{ tf }} output -json client_secrets)"
    fields=()
    while IFS= read -r app; do
      [ -n "${app}" ] || continue
      # Pre-fetch so jq's non-zero exit on a missing value aborts the recipe instead of
      # being swallowed inside the `op item edit` argument list.
      value="$(printf '%s' "${secrets}" | jq -er --arg k "${app}" '.[$k]')" || exit 1
      fields+=("${app}_client_secret[password]=${value}")
    done < <(printf '%s' "${secrets}" | jq -r 'keys[]')
    [ "${#fields[@]}" -gt 0 ] || { just log error "No client secrets in state — refusing to report success"; exit 1; }
    op item edit pocket-id-clients --vault HomeOps "${fields[@]}" >/dev/null
    just log info "Synced ${#fields[@]} client secrets to HomeOps/pocket-id-clients"

[doc('Report clients whose group restriction is off — catches clients created outside Terraform')]
[script]
audit:
    cd {{ tf_dir }}
    export POCKETID_URL="https://idm.$(yq -r '.data.PUBLIC_DOMAIN' {{ cluster_settings }})"
    op run --no-masking --env-file=./.env -- bash -euo pipefail -c '
      # -g: the pagination[limit] brackets are a curl glob without it.
      clients="$(curl -sfg -H "X-API-KEY: ${TF_VAR_POCKETID_API_TOKEN}" \
        "${POCKETID_URL}/api/oidc/clients?pagination[limit]=200")"
      printf "%s" "${clients}" | jq -e ".pagination.totalItems == (.data | length)" >/dev/null \
        || { printf "\033[31m✗\033[0m response truncated — raise the pagination limit\n"; exit 1; }
      unrestricted="$(printf "%s" "${clients}" \
        | jq -r ".data[] | select(.isGroupRestricted == false or .allowedUserGroupsCount == 0) | .name")"
      if [ -n "${unrestricted}" ]; then
        printf "\033[31m✗\033[0m clients open to every account:\n%s\n" "${unrestricted}"
        exit 1
      fi
      printf "\033[32m✓\033[0m all %s clients are group-restricted\n" \
        "$(printf "%s" "${clients}" | jq -r ".pagination.totalItems")"
    '

[doc('terraform force-unlock <id> (TF_VAR_* injected from ./.env via op run)')]
[script]
unlock id:
    cd {{ tf_dir }} && {{ tf }} force-unlock {{ id }}
