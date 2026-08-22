#!/usr/bin/env bash
# debt: recyclarr v8 does not support overriding quality_profile.language via YAML; both profiles
# are variants of the guide-backed SQP-1, so both receive language="Original" on every sync (TRaSH
# guide) and Radarr's own default is Original (QualityProfileService.cs:263) — there is no
# declarative path to either language this reconciler sets. Remove this script (and the helmrelease
# command wrapper) when recyclarr ships a language YAML override.
#
# Per profile, idempotently right after each recyclarr sync:
#   [SQP] SQP-1 (2160p) -> Any        so the Hungarian CF can score HUN dubs instead of being
#                                     hard-gated by "Original Language (French) is wanted, but
#                                     found Hungarian"
#   HUN-only            -> Hungarian  a score-independent second gate on top of the profile's
#                                     min_format_score=24000 (LanguageSpecification rejects every
#                                     release whose parsed languages lack Hungarian)
#
# Runtime: recyclarr pod (Alpine) — bash + BusyBox wget + bash /dev/tcp; no curl/jq available, so
# GET uses wget and the PUT is sent over a raw /dev/tcp socket. The host/port must match the
# radarr base_url in /config/recyclarr.yml.
set -euo pipefail

RADARR_HOST="radarr.downloads.svc.cluster.local"  # must match /config/recyclarr.yml radarr.base_url
RADARR_PORT="7878"

: "${RADARR_API_KEY:?RADARR_API_KEY env not set}"
API_BASE="http://${RADARR_HOST}:${RADARR_PORT}/api/v3"
HDR="X-Api-Key: ${RADARR_API_KEY}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Language ids are Radarr's own (Language.cs): Any = -1, Hungarian = 22 — the same 22 the
# home-ops-hungarian-language CF matches on.
setProfileLanguage() {
  local profile_name="$1" lang_id="$2" lang_name="$3"
  local name_line profile_id got_name body_len put_status verify_lang

  # Locate the profile id by name. Radarr pretty-prints JSON; in each top-level object the
  # 4-space-indent "name" precedes the 4-space-indent "id", and nested ids (items[].quality.id) sit
  # at deeper indent, so the first ^    "id": after the matching name line is the profile id.
  wget -qO "$tmp/arr.json" --header "$HDR" "${API_BASE}/qualityProfile"
  name_line=$(grep -nF "    \"name\": \"${profile_name}\"" "$tmp/arr.json" | head -1 | cut -d: -f1)
  if [ -z "$name_line" ]; then
    echo "ERROR: Radarr quality profile '${profile_name}' not found" >&2
    return 1
  fi
  profile_id=$(awk -v n="$name_line" 'NR>n && /^    "id": [0-9]/ {match($0,/[0-9]+/); print substr($0,RSTART,RLENGTH); exit}' "$tmp/arr.json")
  if [ -z "$profile_id" ]; then
    echo "ERROR: could not extract id for '${profile_name}'" >&2
    return 1
  fi

  # GET the single profile and guard against id drift (the extracted id must still name it).
  wget -qO "$tmp/prof.json" --header "$HDR" "${API_BASE}/qualityProfile/${profile_id}"
  got_name=$(awk -F'"' '/"name":/ {print $4; exit}' "$tmp/prof.json")
  if [ "$got_name" != "$profile_name" ]; then
    echo "ERROR: id=${profile_id} resolved to '${got_name}', expected '${profile_name}'" >&2
    return 1
  fi

  # Rewrite the language field. The profile has exactly one "language": {...} (flat object);
  # collapse newlines so the multi-line block matches a single sed, then PUT it back whole.
  tr -d '\n' < "$tmp/prof.json" \
    | sed "s/\"language\":[[:space:]]*{[^}]*}/\"language\":{\"id\":${lang_id},\"name\":\"${lang_name}\"}/" \
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
    2*) echo "PUT /qualityProfile/${profile_id} -> ${put_status} (language set to ${lang_name})" ;;
    *) echo "ERROR: PUT returned status '${put_status}' for '${profile_name}'" >&2; return 1 ;;
  esac

  # Verify the language actually landed.
  wget -qO "$tmp/verify.json" --header "$HDR" "${API_BASE}/qualityProfile/${profile_id}"
  verify_lang=$(awk '/"language":/ {f=1; next} f && /"name":/ {gsub(/.*"name": *"|" *.*/,""); print; exit}' "$tmp/verify.json")
  if [ "$verify_lang" != "$lang_name" ]; then
    echo "ERROR: post-PUT language is '${verify_lang}', expected '${lang_name}'" >&2
    return 1
  fi
  echo "OK: '${profile_name}' language=${verify_lang}"
}

setProfileLanguage "[SQP] SQP-1 (2160p)" "-1" "Any"
setProfileLanguage "HUN-only" "22" "Hungarian"
