#!/usr/bin/env bash
# Route auth coverage guard, layer 2 (rendered): checks a fully rendered manifest stream
# (flate build all -o json) against the layer-1 claims, and proves every gate: envoy route
# carries a matching OIDC SecurityPolicy. Never trusts the renderer's exit code alone.
# Usage: lint-rendered.sh <rendered.json>
set -euo pipefail

rendered="${1:?usage: lint-rendered.sh <rendered.json>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
registry="${REGISTRY:-${repo_root}/provision/pocket-id/clients.yaml}"

domain="$(yq -r '.data.PUBLIC_DOMAIN' "${repo_root}/kubernetes/components/common/vars/cluster-settings.yaml")"
[ -n "${domain}" ] && [ "${domain}" != null ] || { printf '  \033[31m✗\033[0m [L2.1] PUBLIC_DOMAIN not found in cluster-settings\n'; exit 1; }

claims="$(REPO_ROOT="${repo_root}" REGISTRY="${registry}" "${here}/lint.sh" --claims-json)"
registry_json="$(yq -o=json '.' "${registry}")"

# shellcheck disable=SC2016 # jq program, not shell expansions
jq -rn \
    --arg domain "${domain}" \
    --argjson reg "${registry_json}" \
    --argjson claims "${claims}" \
    --slurpfile stream "${rendered}" '
def v($rule; $msg): "[\($rule)] \($msg)";
def sub_of: if endswith("." + $domain) then .[0:(length - ($domain | length) - 1)] else null end;
def counts: group_by(.) | map({key: .[0], value: length}) | from_entries;

[$stream[] | if type == "array" then .[] else . end | select(type == "object")] as $objs
| [$objs[] | select(.kind == "HTTPRoute")] as $routes
| [$objs[] | select(.kind == "SecurityPolicy" and .spec.oidc != null)] as $oidc
| ($reg.clients // {}) as $clients
| ($clients | to_entries | map({key: .value.subdomain, value: (.value + {app: .key})}) | from_entries) as $by_sub
| [$routes[] | . as $r | (.spec.hostnames // [])[] | {route: $r, host: ., sub: sub_of}] as $hosts
| ([$hosts[].sub | select(. != null)] | counts) as $rendered_n
| ([$claims[].sub] | counts) as $static_n
| [
    # L2.1 sanity: an empty or partial render must never pass.
    (select(($routes | length) == 0) | v("L2.1"; "rendered stream has no HTTPRoute")),
    (select(($oidc | length) == 0) | v("L2.1"; "rendered stream has no OIDC SecurityPolicy")),
    ($hosts[] | select(.host | contains("${")) | v("L2.1"; "\(.route.metadata.namespace)/\(.route.metadata.name): unsubstituted hostname \(.host)")),
    ($hosts[] | select(.sub == null and (.host | contains("${") | not))
     | v("L2.2"; "\(.route.metadata.namespace)/\(.route.metadata.name): hostname \(.host) is outside the public domain")),

    # L2.2 parity with the static claims, per subdomain and route count.
    (($rendered_n + $static_n) | keys[] as $s
     | select(($rendered_n[$s] // 0) != ($static_n[$s] // 0))
     | v("L2.2"; "\($s): \($rendered_n[$s] // 0) rendered route(s) vs \($static_n[$s] // 0) in the static scan (chart default, valuesFrom, or a dropped render)")),

    # L2.3 gate envoy: the route is targeted by a well-formed OIDC policy.
    ($hosts[] | . as $h | $by_sub[.sub // ""] | select(. != null and .gate == "envoy") as $cl
     | ([$oidc[] | select(.metadata.namespace == $h.route.metadata.namespace
                          and any(.spec.targetRefs[]?; .kind == "HTTPRoute" and .name == $h.route.metadata.name))]) as $pols
     | if ($pols | length) == 0 then
         v("L2.3"; "\($h.sub): route \($h.route.metadata.namespace)/\($h.route.metadata.name) has no OIDC SecurityPolicy targeting it (check HTTPROUTE_NAME)")
       else
         ($pols[] | select(.spec.mergeType != "StrategicMerge")
          | v("L2.3"; "\($h.sub): SecurityPolicy \(.metadata.name) lacks mergeType: StrategicMerge (it would drop the gateway-level policies)")),
         ($pols[] | select((.spec.oidc.redirectURL // "") | test("^https://\($h.sub | gsub("\\."; "\\."))\\.\($domain | gsub("\\."; "\\."))/") | not)
          | v("L2.3"; "\($h.sub): SecurityPolicy \(.metadata.name) redirectURL \(.spec.oidc.redirectURL) is not on \($h.host)"))
       end),

    # L2.4 gate native: no OIDC policy in front of an app that logs in by itself.
    ($hosts[] | . as $h | select(($by_sub[.sub // ""].gate // "") == "native")
     | $oidc[] | select(.metadata.namespace == $h.route.metadata.namespace
                        and any(.spec.targetRefs[]?; .kind == "HTTPRoute" and .name == $h.route.metadata.name))
     | v("L2.4"; "\($h.sub): gate: native route is also targeted by OIDC SecurityPolicy \(.metadata.name)"))
  ] | unique as $out
| ($out[] | "  \u001b[31m✗\u001b[0m \(.)"),
  (if ($out | length) > 0 then "FAIL"
   else "  \u001b[32m✓\u001b[0m rendered routes match the static scan; \([$hosts[] | select(($by_sub[.sub // ""].gate // "") == "envoy")] | length) gate-envoy routes carry their OIDC policy" end)
' | {
    status=0
    while IFS= read -r line; do
        if [ "${line}" = FAIL ]; then status=1; else printf '%s\n' "${line}"; fi
    done
    exit "${status}"
}
