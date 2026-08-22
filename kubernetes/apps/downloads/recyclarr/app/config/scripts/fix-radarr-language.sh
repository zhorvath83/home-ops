#!/usr/bin/env bash
# debt: recyclarr v8 does not support overriding quality_profile.language via YAML; the
# guide-backed SQP-1 profile receives language="Original" on every sync (TRaSH guide) and Radarr's
# own default is Original (QualityProfileService.cs:263), so there is no declarative path to
# language="Any". This reconciler idempotently sets SQP-1's Preferred Language to "Any" right after
# each recyclarr sync so the Hungarian CF (+9900) can score HUN dubs instead of being hard-gated
# by the "Original Language (French) is wanted, but found Hungarian" rejection. Remove this script
# (and the helmrelease command wrapper) when recyclarr ships a language YAML override.
#
# Runtime: recyclarr pod (Alpine) — bash + BusyBox wget + bash /dev/tcp; no curl/jq available, so
# GET uses wget and the PUT is sent over a raw /dev/tcp socket. The host/port must match the
# radarr base_url in /config/recyclarr.yml.
set -euo pipefail

RADARR_HOST="radarr.downloads.svc.cluster.local"  # must match /config/recyclarr.yml radarr.base_url
RADARR_PORT="7878"
PROFILE_NAME="[SQP] SQP-1 (2160p)"
ANY_ID="-1"     # Radarr language "Any" (verified live via GET /api/v3/language)
ANY_NAME="Any"

: "${RADARR_API_KEY:?RADARR_API_KEY env not set}"
API_BASE="http://${RADARR_HOST}:${RADARR_PORT}/api/v3"
HDR="X-Api-Key: ${RADARR_API_KEY}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Locate SQP-1's profile id by name. Radarr pretty-prints JSON; in each top-level object the
# 4-space-indent "name" precedes the 4-space-indent "id", and nested ids (items[].quality.id) sit
# at deeper indent, so the first ^    "id": after the matching name line is the profile id.
wget -qO "$tmp/arr.json" --header "$HDR" "${API_BASE}/qualityProfile"
name_line=$(grep -nF "    \"name\": \"${PROFILE_NAME}\"" "$tmp/arr.json" | head -1 | cut -d: -f1)
if [ -z "$name_line" ]; then
  echo "ERROR: Radarr quality profile '${PROFILE_NAME}' not found" >&2
  exit 1
fi
profile_id=$(awk -v n="$name_line" 'NR>n && /^    "id": [0-9]/ {match($0,/[0-9]+/); print substr($0,RSTART,RLENGTH); exit}' "$tmp/arr.json")
if [ -z "$profile_id" ]; then
  echo "ERROR: could not extract id for '${PROFILE_NAME}'" >&2
  exit 1
fi

# GET the single profile and guard against id drift (the extracted id must still name SQP-1).
wget -qO "$tmp/prof.json" --header "$HDR" "${API_BASE}/qualityProfile/${profile_id}"
got_name=$(awk -F'"' '/"name":/ {print $4; exit}' "$tmp/prof.json")
if [ "$got_name" != "$PROFILE_NAME" ]; then
  echo "ERROR: id=${profile_id} resolved to '${got_name}', expected '${PROFILE_NAME}'" >&2
  exit 1
fi

# Rewrite the language field to "Any". The profile has exactly one "language": {...} (flat
# object); collapse newlines so the multi-line block matches a single sed, then PUT it back whole.
tr -d '\n' < "$tmp/prof.json" \
  | sed "s/\"language\":[[:space:]]*{[^}]*}/\"language\":{\"id\":${ANY_ID},\"name\":\"${ANY_NAME}\"}/" \
  > "$tmp/put.json"

# PUT the modified profile over a raw TCP socket (BusyBox wget cannot do PUT).
body_len=$(wc -c < "$tmp/put.json" | tr -d '[:space:]')
put_status=$(
  exec 3<>/dev/tcp/"${RADARR_HOST}"/"${RADARR_PORT}" 2>/dev/null || { echo CONNECT_FAIL; exit; }
  printf 'PUT /api/v3/qualityProfile/%s HTTP/1.1\r\nHost: %s\r\n%s\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n' \
    "$profile_id" "$RADARR_HOST" "$HDR" "$body_len" >&3
  cat "$tmp/put.json" >&3
  IFS=' ' read -r _ code _ <&3
  printf '%s' "$code"
)
case "$put_status" in
  2*) echo "PUT /qualityProfile/${profile_id} -> ${put_status} (language set to ${ANY_NAME})" ;;
  *) echo "ERROR: PUT returned status '${put_status}'" >&2; exit 1 ;;
esac

# Verify the language actually landed on "Any".
wget -qO "$tmp/verify.json" --header "$HDR" "${API_BASE}/qualityProfile/${profile_id}"
verify_lang=$(awk '/"language":/ {f=1; next} f && /"name":/ {gsub(/.*"name": *"|" *.*/,""); print; exit}' "$tmp/verify.json")
if [ "$verify_lang" != "$ANY_NAME" ]; then
  echo "ERROR: post-PUT language is '${verify_lang}', expected '${ANY_NAME}'" >&2
  exit 1
fi
echo "OK: '${PROFILE_NAME}' language=${verify_lang}"
