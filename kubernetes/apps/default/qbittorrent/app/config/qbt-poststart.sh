#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

QBT_URL="http://127.0.0.1:8080"
CONFIG_FILE="/scripts/qbt-config.json"
RETRY_INTERVAL=2
MAX_RETRIES=60


IPFILTER_FILE="/ipfilter/ipfilter.dat"
IPFILTER_URL="https://github.com/DavidMoore/ipfilter/releases/download/lists/ipfilter.dat.gz"

# --- Download ipfilter ---
echo "Downloading ipfilter.dat..."
if curl --silent --location --fail "${IPFILTER_URL}" | gunzip > "${IPFILTER_FILE}" 2>/dev/null; then
  LINE_COUNT=$(wc -l < "${IPFILTER_FILE}")
  echo "ipfilter.dat downloaded (${LINE_COUNT} lines)."
else
  echo "WARNING: Failed to download ipfilter.dat. qBittorrent will start without IP filtering."
  rm -f "${IPFILTER_FILE}"
fi


# Colors
C_GREEN='\e[32m'
C_YELLOW='\e[33m'
C_RED='\e[31m'
C_BOLD='\e[1m'
C_DIM='\e[2m'
C_RESET='\e[0m'

tag() { echo -e "${C_DIM}[qbt-poststart]${C_RESET} $*"; }
ok() { echo -e "${C_DIM}[qbt-poststart]${C_RESET} ${C_GREEN}$*${C_RESET}"; }
warn() { echo -e "${C_DIM}[qbt-poststart]${C_RESET} ${C_YELLOW}$*${C_RESET}"; }
fail() { echo -e "${C_DIM}[qbt-poststart]${C_RESET} ${C_RED}$*${C_RESET}"; }

# --- Wait for qBittorrent API ---
tag "Waiting for API..."
for i in $(seq 1 "${MAX_RETRIES}"); do
  if curl --silent --fail "${QBT_URL}/api/v2/app/version" > /dev/null 2>&1; then
    ok "API ready (attempt ${i}/${MAX_RETRIES})"
    break
  fi
  if [[ "${i}" -eq "${MAX_RETRIES}" ]]; then
    fail "API not ready after $((MAX_RETRIES * RETRY_INTERVAL))s"
    exit 1
  fi
  sleep "${RETRY_INTERVAL}"
done

# --- Apply API calls from config ---
CALL_COUNT=$(jq 'length' "${CONFIG_FILE}")
tag "${C_BOLD}Applying ${CALL_COUNT} calls...${C_RESET}"

for ((i=0; i<CALL_COUNT; i++)); do
  endpoint=$(jq -r ".[${i}].endpoint" "${CONFIG_FILE}")
  method=$(jq -r ".[${i}].method" "${CONFIG_FILE}")
  label=$(jq -r ".[${i}].label // \"${endpoint##*/}\"" "${CONFIG_FILE}")
  seq_num=$((i + 1))

  if [[ "${method}" == "json" ]]; then
    payload=$(jq -c ".[${i}].payload" "${CONFIG_FILE}")

    # Merge envVars into payload
    env_count=$(jq -r ".[${i}].envVars // {} | length" "${CONFIG_FILE}")
    if [[ "${env_count}" -gt 0 ]]; then
      while IFS=$'\t' read -r key env_var; do
        value="${!env_var:-}"
        if [[ -z "${value}" ]]; then
          warn "  ${env_var} unset, skipping ${key}"
          payload=$(echo "${payload}" | jq -c --arg k "${key}" 'del(.[$k])')
        else
          payload=$(echo "${payload}" | jq -c --arg k "${key}" --arg v "${value}" '. + {($k): $v}')
        fi
      done < <(jq -r ".[${i}].envVars | to_entries[] | [.key, .value] | @tsv" "${CONFIG_FILE}")
    fi

    http_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --request POST \
      --header "Referer: ${QBT_URL}" \
      --data-urlencode "json=${payload}" \
      "${QBT_URL}${endpoint}")
  else
    curl_args=()
    while IFS=$'\t' read -r key value; do
      curl_args+=("--data-urlencode" "${key}=${value}")
    done < <(jq -r ".[${i}].payload | to_entries[] | [.key, .value] | @tsv" "${CONFIG_FILE}")

    # Merge envVars into form args
    env_count=$(jq -r ".[${i}].envVars // {} | length" "${CONFIG_FILE}")
    if [[ "${env_count}" -gt 0 ]]; then
      while IFS=$'\t' read -r key env_var; do
        value="${!env_var:-}"
        if [[ -z "${value}" ]]; then
          warn "  ${env_var} unset, skipping ${key}"
        else
          curl_args+=("--data-urlencode" "${key}=${value}")
        fi
      done < <(jq -r ".[${i}].envVars | to_entries[] | [.key, .value] | @tsv" "${CONFIG_FILE}")
    fi

    http_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --request POST \
      --header "Referer: ${QBT_URL}" \
      "${curl_args[@]}" \
      "${QBT_URL}${endpoint}")
  fi

  # Accept 2xx and 409 (Conflict = idempotent success); reject everything else
  if [[ "${http_code}" -lt 200 || ("${http_code}" -ge 400 && "${http_code}" -ne 409) ]]; then
    fail "[${seq_num}/${CALL_COUNT}] ${label} → HTTP ${http_code} FAILED"
    exit 1
  fi

  if [[ "${http_code}" -eq 409 ]]; then
    warn "[${seq_num}/${CALL_COUNT}] ${label} → ${http_code} (exists)"
  else
    ok "[${seq_num}/${CALL_COUNT}] ${label} → ${http_code}"
  fi
done

ok "${C_BOLD}Done.${C_RESET}"
