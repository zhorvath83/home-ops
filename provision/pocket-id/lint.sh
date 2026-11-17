#!/usr/bin/env bash
# Route auth coverage guard, layer 1 (static): every hostname published under kubernetes/
# must be owned by a Pocket ID client in clients.yaml or by a justified exemption, and a
# gate: envoy client must be wired to the gateway-oidc component. Rules: provision/pocket-id/CLAUDE.md.
# Usage: lint.sh [--claims-json]   (--claims-json prints the resolved route claims for lint-rendered.sh)
set -euo pipefail

repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
registry="${REGISTRY:-${repo_root}/provision/pocket-id/clients.yaml}"
mode="${1:-check}"

cd "${repo_root}"

yaml_files() {
    find kubernetes -type f \( -name '*.yaml' -o -name '*.yml' \) -print0
}

# Fail closed: a file the parser cannot read could hide a route.
if ! parse_errors="$(yaml_files | xargs -0 yq -o=json -I0 'true' 2>&1 >/dev/null)"; then
    printf '  \033[31m✗\033[0m [PARSE] %s\n' "${parse_errors}"
    exit 1
fi

# Schema-agnostic discovery: any map with a hostnames list or parentRefs, in any document kind.
routes="$(yaml_files | xargs -0 yq -o=json -I0 '
    .. | select(tag == "!!map" and ((.hostnames | tag) == "!!seq" or (.parentRefs | tag) == "!!seq"))
    | {"file": filename,
       "hostnames": (.hostnames // []),
       "parents": [(.parentRefs // [])[] | {"name": (.name // ""), "section": (.sectionName // "")}],
       "rules": ((.rules // []) | length),
       "backends": ([(.rules // [])[] | select(has("backendRefs"))] | length)}
' | jq -c 'select(.file != null)')"

kustomizations="$(yaml_files | xargs -0 yq -o=json -I0 '
    select(tag == "!!map" and .kind == "Kustomization" and ((.apiVersion // "") | test("^kustomize.toolkit.fluxcd.io/")))
    | {"file": filename,
       "path": ((.spec.path // "") | sub("^\./"; "") | sub("/$"; "")),
       "components": (.spec.components // []),
       "subst": (.spec.postBuild.substitute // {})}
')"

registry_json="$(yq -o=json '.' "${registry}")"

# shellcheck disable=SC2016 # jq program, not shell expansions
jq -rn \
    --argjson reg "${registry_json}" \
    --slurpfile routes <(printf '%s\n' "${routes}") \
    --slurpfile kss <(printf '%s\n' "${kustomizations}") \
    --arg mode "${mode}" '
def subst($s):
  gsub("\\$\\{PUBLIC_DOMAIN\\}"; "\u0001")
  | [., null]
  | until(.[0] == .[1];
      [(.[0] | gsub("\\$\\{(?<n>[A-Z0-9_]+)(:=(?<d>[^${}]*))?\\}";
          if $s[.n] != null then ($s[.n] | tostring) elif .d != null then .d else "${\(.n)}" end)),
       .[0]])
  | .[0]
  | gsub("\u0001"; "${PUBLIC_DOMAIN}");
def oidc: (.components // []) | any(test("components/gateway-oidc/?$"));
def nonempty: type == "string" and length > 0;
def v($rule; $where; $msg): {level: "error", text: "[\($rule)] \($where): \($msg)"};
def w($rule; $where; $msg): {level: "warn", text: "[\($rule)] \($where): \($msg)"};

($reg.clients // {}) as $clients
| ($reg.exempt // {}) as $exempt
| ($clients | to_entries | map({key: .value.subdomain, value: (.value + {app: .key})}) | from_entries) as $by_sub

# Resolve each route against its owner Kustomization (longest spec.path prefix of the file).
| [$routes[] | . as $r
   | ([$kss[] | .path as $p | select($p != "" and ($r.file | startswith($p + "/")))] | max_by(.path | length)) as $owner
   | . + {owner: $owner, hosts: [.hostnames[] | tostring | subst($owner.subst // {})]}] as $resolved

| [$resolved[] | . as $r | .hosts[]
   | capture("^(?<sub>\\*|[a-z0-9]([a-z0-9-]*[a-z0-9])?)\\.\\$\\{PUBLIC_DOMAIN\\}$") as $m
   | $r + {sub: $m.sub, host: .}] as $claims

| if $mode == "--claims-json" then
    [$claims[] | {sub, file, nhosts: (.hosts | length)}]
  else
  ([
    # Ownership of the route file itself.
    ($resolved[] | select(.owner == null and (.hosts | length) > 0)
     | v("OWN"; .file; "no Flux Kustomization spec.path contains this file; its substitutions cannot be resolved")),

    # R1 host form, after substitution.
    ($resolved[] | select(.owner != null) | .file as $f | .hosts[]
     | select(test("^(\\*|[a-z0-9]([a-z0-9-]*[a-z0-9])?)\\.\\$\\{PUBLIC_DOMAIN\\}$") | not)
     | v("R1"; $f; "hostname \(.) is not <sub>.${PUBLIC_DOMAIN} after substitution (unresolved variable or foreign domain)")),

    # R7 catch-all routes may only attach to the plain-HTTP listener.
    ($resolved[] | select((.hosts | length) == 0 and any(.parents[]; .section != "http"))
     | v("R7"; .file; "route without hostnames attaches to a non-http listener; it would catch every host")),

    # Registry consistency.
    ($clients | to_entries | group_by(.value.subdomain)[] | select(length > 1)
     | v("REG"; "clients.yaml"; "subdomain \(.[0].value.subdomain) is claimed by several clients: \(map(.key) | join(", "))")),
    ($exempt | keys[] | select($by_sub[.] != null)
     | v("REG"; "clients.yaml"; "\(.) is listed in both clients and exempt")),
    ($exempt | to_entries[] | .key as $k | .value
     | (select((.reason | nonempty) | not) | v("REG"; "exempt.\($k)"; "reason is mandatory")),
       (select((.control | nonempty) | not) | v("REG"; "exempt.\($k)"; "control is mandatory")),
       (select(((.gateways // []) | length) == 0) | v("REG"; "exempt.\($k)"; "gateways must list at least one gateway")),
       (select(.temporary == true and ((.tracking | nonempty) | not)) | v("REG"; "exempt.\($k)"; "temporary exemption needs a tracking BM permalink"))),
    # An empty list reaches the API as not group-restricted (provider gap), so every account could authorize.
    ($clients | to_entries[] | select(((.value.groups // []) | length) == 0)
     | v("REG"; "clients.\(.key)"; "no allowed group, Pocket ID would let every account authorize")),
    ($clients | to_entries[] | .key as $k | (.value.groups // [])[] | . as $g
     | select(($reg.groups // {}) | has($g) | not)
     | v("REG"; "clients.\($k)"; "references undefined group \(.)")),

    # R2 ownership.
    ($claims[] | select($by_sub[.sub] == null and $exempt[.sub] == null)
     | v("R2"; .file; "\(.sub) is not claimed by any client or exemption in clients.yaml")),

    # R3 gate envoy wiring.
    ($claims[] | . as $c | $by_sub[.sub] | select(. != null and .gate == "envoy") as $cl
     | ($c.owner.subst // {}) as $s
     | (select(($c.owner | oidc) | not)
        | v("R3"; $c.file; "\($c.sub) belongs to gate: envoy client \($cl.app) but its Kustomization does not include components/gateway-oidc")),
       (select(($c.owner | oidc) and ($s.APP != $cl.app or (($s.APP_SUBDOMAIN // $s.APP) != $cl.subdomain)))
        | v("R3"; $c.file; "\($c.sub): Kustomization APP/APP_SUBDOMAIN (\($s.APP)/\($s.APP_SUBDOMAIN // $s.APP)) does not match client \($cl.app)/\($cl.subdomain)")),
       (select(($c.hosts | length) != 1)
        | v("R3"; $c.file; "\($c.sub): a gateway-oidc route must carry exactly one hostname (single-host redirectURL)"))),
    ($claims | group_by(.sub)[] | select(length > 1 and ($by_sub[.[0].sub].gate // "") == "envoy")
     | v("R3"; (map(.file) | unique | join(", ")); "\(.[0].sub) is published by more than one route; the SecurityPolicy targets only one")),
    ($kss[] | select(oidc) | . as $k
     | select(($clients[$k.subst.APP // ""].gate // "") != "envoy")
     | v("R3"; .file; "includes components/gateway-oidc but APP \($k.subst.APP) has no gate: envoy client in clients.yaml")),

    # R4 gate native: no double gate.
    ($claims[] | select(($by_sub[.sub].gate // "") == "native" and (.owner | oidc))
     | v("R4"; .file; "\(.sub) is a gate: native client but its Kustomization also includes components/gateway-oidc")),

    # R5 exemption scope.
    ($claims[] | . as $c | $exempt[.sub] | select(. != null) as $e
     | ($c.parents[] | select(.name as $n | any(($e.gateways // [])[]; . == $n) | not)
        | v("R5"; $c.file; "\($c.sub) attaches to \(.name), not listed in exempt.\($c.sub).gateways")),
       (select($e.redirect_only == true and ($c.rules == 0 or $c.backends > 0))
        | v("R5"; $c.file; "\($c.sub) is redirect_only but the route has a backend (or no redirect rule)")),
       (select($e.redirect_only == true and any($c.parents[]; .section != "http"))
        | v("R5"; $c.file; "\($c.sub) is redirect_only but attaches to a non-http listener"))),

    # R6 no stale registry entries.
    ([$claims[].sub] | unique) as $claimed
    | (($clients | to_entries[] | select(.value.subdomain as $s | any($claimed[]; . == $s) | not)
        | v("R6"; "clients.\(.key)"; "subdomain \(.value.subdomain) is not published by any route")),
       ($exempt | keys[] | select(. as $s | any($claimed[]; . == $s) | not)
        | v("R6"; "exempt.\(.)"; "not published by any route"))),

    # Temporary exemptions stay visible on every run.
    ($exempt | to_entries[] | select(.value.temporary == true)
     | w("TEMP"; .key; "temporary exemption, tracked in \(.value.tracking // "?")"))
  ] | unique_by(.text)) as $out
  | ($out[] | if .level == "error" then "  \u001b[31m✗\u001b[0m \(.text)" else "  \u001b[33m!\u001b[0m \(.text)" end),
    (if any($out[]; .level == "error") then "FAIL"
     else "  \u001b[32m✓\u001b[0m clients.yaml and the kubernetes route tree agree (\($claims | length) host claims)" end)
  end
' | {
    if [ "${mode}" = "--claims-json" ]; then
        cat
    else
        status=0
        while IFS= read -r line; do
            if [ "${line}" = FAIL ]; then status=1; else printf '%s\n' "${line}"; fi
        done
        exit "${status}"
    fi
}
