#!/usr/bin/env bash
# debt: recyclarr v8 does not support overriding quality_profile.language via YAML; the
# guide-backed SQP-1 profile receives language="Original" on every sync (TRaSH guide) and Radarr's
# own default is Original (QualityProfileService.cs:263), so there is no declarative path to
# language="Any". This reconciler idempotently sets SQP-1's Preferred Language to "Any" right after
# each recyclarr sync so the Hungarian CF (+9900) can score HUN dubs instead of being hard-gated
# by the "Original Language (French) is wanted, but found Hungarian" rejection. Remove this script
# (and the helmrelease container) when recyclarr ships a language YAML override.
#
# Runtime: alpine/k8s container (bash + curl + jq), started after the recyclarr sync init
# container succeeded. JSON is parsed with jq, never by text layout: Radarr 7.0.2 switched API
# responses from indented to compact JSON (Radarr commit 479b6f2a1).
set -euo pipefail

RADARR_HOST="radarr.downloads.svc.cluster.local"  # must match /config/recyclarr.yml radarr.base_url
RADARR_PORT="7878"
PROFILE_NAME="[SQP] SQP-1 (2160p)"
ANY_ID="-1"     # Radarr language "Any" (verified live via GET /api/v3/language)
ANY_NAME="Any"

: "${RADARR_API_KEY:?RADARR_API_KEY env not set}"
API_BASE="http://${RADARR_HOST}:${RADARR_PORT}/api/v3"

# Call the Radarr API, print the response body, exit 1 with a message on a transport error or non-2xx.
api() {
  local method="$1" path="$2" data="${3:-}" resp code body
  local args=(-sS -X "$method" -H "X-Api-Key: ${RADARR_API_KEY}" -w '\n%{http_code}')
  [ -n "$data" ] && args+=(-H "Content-Type: application/json" --data-binary "$data")
  if ! resp=$(curl "${args[@]}" "${API_BASE}${path}" 2>&1); then
    echo "ERROR: ${method} ${path} -> request failed: ${resp}" >&2
    exit 1
  fi
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if ! [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    echo "ERROR: ${method} ${path} -> HTTP ${code}: ${body:0:300}" >&2
    exit 1
  fi
  printf '%s' "$body"
}

# Parse with jq; exit 1 with a message instead of a silent set -e abort on invalid JSON.
jqOrDie() {
  local label="$1" input="$2"; shift 2
  local out
  if ! out=$(jq -er "$@" <<<"$input" 2>&1); then
    echo "ERROR: ${label}: ${out:-no match}" >&2
    exit 1
  fi
  printf '%s' "$out"
}

profiles=$(api GET /qualityProfile)
# shellcheck disable=SC2016 # $n, $id, $name are jq --arg bindings, not shell variables
ids=$(jqOrDie "profile lookup" "$profiles" --arg n "$PROFILE_NAME" '[.[] | select(.name == $n) | .id] | if length == 0 then error("quality profile not found") else map(tostring) | join(" ") end')
if [ "$(wc -w <<<"$ids")" -ne 1 ]; then
  echo "ERROR: '${PROFILE_NAME}' matches several profiles (ids: ${ids})" >&2
  exit 1
fi
profile_id="$ids"

profile=$(api GET "/qualityProfile/${profile_id}")
current=$(jqOrDie "language read" "$profile" '.language.name // "unset"')
if [ "$current" = "$ANY_NAME" ]; then
  echo "OK: '${PROFILE_NAME}' (id=${profile_id}) language already ${ANY_NAME}, nothing to do"
  exit 0
fi

# shellcheck disable=SC2016 # $n, $id, $name are jq --arg bindings, not shell variables
updated=$(jqOrDie "language rewrite" "$profile" --argjson id "$ANY_ID" --arg name "$ANY_NAME" '.language = {id: $id, name: $name}')
api PUT "/qualityProfile/${profile_id}" "$updated" >/dev/null
echo "PUT /qualityProfile/${profile_id} -> 2xx (language ${current} -> ${ANY_NAME})"

verify=$(jqOrDie "verify read" "$(api GET "/qualityProfile/${profile_id}")" '.language.name // "unset"')
if [ "$verify" != "$ANY_NAME" ]; then
  echo "ERROR: post-PUT language is '${verify}', expected '${ANY_NAME}'" >&2
  exit 1
fi
echo "OK: '${PROFILE_NAME}' language=${verify}"
