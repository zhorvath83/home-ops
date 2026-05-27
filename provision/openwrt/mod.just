set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

openwrt_host := '192.168.1.1'
openwrt_local_backup_dir := '/mnt/sda1/backups'
openwrt_local_backup_script := '/etc/luci-uploads/openwrt-backup-local.sh'
openwrt_local_package_list_script := '/etc/luci-uploads/list-installed-user-packages-apk.sh'
openwrt_local_reinstall_script := '/etc/luci-uploads/reinstall-user-packages-apk.sh'
# NAS_MOUNT_SCRIPT is defined in .mise.toml and resolves to the
# personal helper script path (absolute, $HOME-expanded). Override the
# env var if the personal scripts repo lives elsewhere.
nas_share_mount_script_on_mac := env_var('NAS_MOUNT_SCRIPT')
openwrt_backup_dir_on_mac := '/Volumes/backups/openwrt'

# Shared SSH/scp prefixes — recipes are separate scripts, so a bash function
# would not survive across them; a justfile-level string variable does.
ssh_opts := "-o ConnectTimeout=10 -o StrictHostKeyChecking=ask"
ssh_router := "ssh " + ssh_opts + " root@" + openwrt_host
scp_router := "scp -q " + ssh_opts + " -p root@" + openwrt_host

[private]
[script]
default:
    just -l openwrt

[private]
[script]
backup:
    LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC="{{ nas_share_mount_script_on_mac }}"
    BACKUP_PARENT_DIR="$(dirname "{{ openwrt_backup_dir_on_mac }}")"
    if [ ! -d "${BACKUP_PARENT_DIR}" ]; then
      if [ ! -x "${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}" ]; then
        printf '%s\n' "OpenWrt backup parent directory is missing: ${BACKUP_PARENT_DIR}"
        printf '%s\n' "NAS share mount script is not executable: ${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}"
        exit 1
      fi

      printf '%s\n' "OpenWrt backup parent directory is missing: ${BACKUP_PARENT_DIR}"
      echo "Attempting to mount NAS shares locally before copying backups"
      "${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}"
    fi

    if [ ! -d "${BACKUP_PARENT_DIR}" ]; then
      printf '%s\n' "OpenWrt backup parent directory is still missing: ${BACKUP_PARENT_DIR}"
      echo "Refusing to create it automatically to avoid writing to the wrong disk."
      exit 1
    fi

    mkdir -p "{{ openwrt_backup_dir_on_mac }}"
    echo "Running OpenWrt backup on {{ openwrt_host }}"
    {{ ssh_router }} '
      {{ openwrt_local_package_list_script }} >/dev/null
      {{ openwrt_local_backup_script }}
    '

    BACKUP_FILE="$(
      {{ ssh_router }} \
        "ls -1t {{ openwrt_local_backup_dir }}/backup-*.tar.gz | head -n 1"
    )"

    if [ -z "${BACKUP_FILE}" ]; then
      printf '%s\n' "Unable to locate the latest OpenWrt backup in {{ openwrt_local_backup_dir }}"
      exit 1
    fi

    printf '%s\n' "Copying ${BACKUP_FILE} to {{ openwrt_backup_dir_on_mac }}"
    {{ scp_router }}:${BACKUP_FILE} "{{ openwrt_backup_dir_on_mac }}/"
    echo "Latest OpenWrt backup copied successfully."

[private]
[script]
reinstall-packages:
    # wait_for <label> <attempts> <delay_seconds> <ready_msg> <wait_msg> <check_cmd…>
    # Polls until <check_cmd> exits 0 or attempts are exhausted.
    wait_for() {
      local label="$1" attempts="$2" delay_seconds="$3" ready_msg="$4" wait_msg="$5"
      shift 5
      local attempt=1
      while [ "${attempt}" -le "${attempts}" ]; do
        if "$@" >/dev/null 2>&1; then
          printf '%s\n' "${label}: ${ready_msg}"
          return 0
        fi
        printf '%s\n' "${label}: ${wait_msg} (${attempt}/${attempts})..."
        sleep "${delay_seconds}"
        attempt=$((attempt + 1))
      done
      printf '%s\n' "${label}: did not become ready in time."
      return 1
    }

    check_router() {
      {{ ssh_router }} 'ubus call system board >/dev/null'
    }
    check_package_repos() {
      {{ ssh_router }} '
        command -v apk >/dev/null 2>&1
        apk update >/dev/null 2>&1
      '
    }

    wait_for "Router availability check" 60 5 \
      "router is reachable again." "waiting for router" check_router
    wait_for "Package repository check" 60 5 \
      "package repositories are reachable." "waiting for WAN and package repositories" check_package_repos

    echo "Running OpenWrt reinstall script"
    {{ ssh_router }} "
      if [ ! -x '{{ openwrt_local_reinstall_script }}' ]; then
        echo 'Reinstall script is missing or not executable: {{ openwrt_local_reinstall_script }}'
        exit 1
      fi
      '{{ openwrt_local_reinstall_script }}'
    "

[doc('Back up the router, run interactive attended sysupgrade via owut, then reinstall user packages (force=true|false)')]
[script]
upgrade force="false":
    # latest_stable_in_branch <branch>
    # Returns the highest non-prerelease version listed under the given branch
    # in the sysupgrade.openwrt.org overview.
    latest_stable_in_branch() {
      local branch="$1"
      printf '%s' "${OVERVIEW_JSON}" \
        | jq -r --arg branch "${branch}" '
            [.branches[$branch].versions[]? | select(contains("-") | not)]
            | sort_by(split(".") | map(tonumber))
            | last
          '
    }

    # first_check_line <pattern>
    # Returns the first CHECK_OUTPUT line matching <pattern>, or empty.
    first_check_line() {
      local pattern="$1"
      printf '%s\n' "${CHECK_OUTPUT}" \
        | awk -v pat="${pattern}" '$0 ~ pat {print; exit}'
    }

    # add_option <version> <label> <kind>
    # Appends an upgrade choice to the parallel OPTION_* arrays and prints
    # the menu line. Index is 1-based to match the user-facing prompt.
    add_option() {
      OPTION_VERSION+=("$1")
      OPTION_LABEL+=("$2")
      OPTION_KIND+=("$3")
      printf '  %d) %s  [%s]\n' "${#OPTION_VERSION[@]}" "$1" "$2"
    }

    # run_owut <subcmd> <version_to>
    # `check` is invoked with `2>&1` by the caller so awk can scan
    # WARNING:/ERROR: lines on stdout; `blob` keeps stderr separate so the
    # JSON body stays clean for the curl POST.
    run_owut() {
      local subcmd="$1" version_to="$2"
      {{ ssh_router }} "
        if ! command -v owut >/dev/null 2>&1; then
          echo 'owut is not installed on the router'
          exit 1
        fi
        owut ${subcmd} --version-to '${version_to}'
      "
    }

    asu_request_preflight() {
      local version_to="$1"
      local response_file build_blob http_status request_hash detail
      response_file="$(mktemp "${TMPDIR:-/tmp}/home-ops-openwrt-asu-response.XXXXXX")"
      build_blob="$(run_owut blob "${version_to}")"

      http_status="$(
        curl -sS \
          -o "${response_file}" \
          -w '%{http_code}' \
          -H 'Content-Type: application/json' \
          -d "${build_blob}" \
          'https://sysupgrade.openwrt.org/api/v1/build'
      )"

      if [ "${http_status}" = "200" ] || [ "${http_status}" = "202" ]; then
        request_hash="$(jq -r '.request_hash // empty' "${response_file}")"
        if [ -n "${request_hash}" ]; then
          printf '%s\n' "ASU preflight: build request accepted (${request_hash})."
        else
          echo "ASU preflight: build request accepted."
        fi
        rm -f "${response_file}"
        return 0
      fi

      detail="$(
        jq -r '.detail // .message // empty' "${response_file}" 2>/dev/null
      )"
      if [ -z "${detail}" ]; then
        detail="$(tr '\n' ' ' < "${response_file}" | sed 's/[[:space:]]\+/ /g')"
      fi

      rm -f "${response_file}"
      printf '%s\n' "ASU preflight failed for ${version_to} (HTTP ${http_status})."
      if [ -n "${detail}" ]; then
        printf '%s\n' "${detail}"
      fi
      return 1
    }

    just openwrt backup

    echo
    echo "Starting OpenWrt attended sysupgrade workflow"

    BOARD_JSON="$(
      {{ ssh_router }} 'ubus call system board'
    )"
    CURRENT_VERSION="$(printf '%s' "${BOARD_JSON}" | jq -r '.release.version')"

    case "${CURRENT_VERSION}" in
      SNAPSHOT|*-SNAPSHOT|*SNAPSHOT*)
        CURRENT_BRANCH="SNAPSHOT"
        ;;
      *)
        CURRENT_BRANCH="$(printf '%s' "${CURRENT_VERSION}" | grep -Eo '^[0-9]+\.[0-9]+' || true)"
        ;;
    esac

    OVERVIEW_JSON="$(curl -fsSL https://sysupgrade.openwrt.org/json/v1/overview.json)"
    BRANCH_VERSION="$(latest_stable_in_branch "${CURRENT_BRANCH}")"

    NEXT_STABLE_BRANCH=""
    if [ "${CURRENT_BRANCH}" != "SNAPSHOT" ]; then
      NEXT_STABLE_BRANCH="$(
        printf '%s' "${OVERVIEW_JSON}" \
          | jq -r --arg branch "${CURRENT_BRANCH}" '
              [.branches
               | to_entries[]
               | select((.key | test("^[0-9]+\\.[0-9]+$")))
               | {key: .key, parts: (.key | split(".") | map(tonumber))}]
              | sort_by(.parts)
              | map(select(.parts > ($branch | split(".") | map(tonumber))))
              | (.[0].key // empty)
            '
      )"
    fi

    NEXT_STABLE_VERSION=""
    if [ -n "${NEXT_STABLE_BRANCH}" ]; then
      NEXT_STABLE_VERSION="$(latest_stable_in_branch "${NEXT_STABLE_BRANCH}")"
    fi

    if [ -z "${CURRENT_VERSION}" ] || [ -z "${CURRENT_BRANCH}" ] || [ -z "${BRANCH_VERSION}" ] || [ "${CURRENT_VERSION}" = "null" ] || [ "${BRANCH_VERSION}" = "null" ]; then
      echo "Unable to determine current OpenWrt version or available upgrade versions."
      exit 1
    fi

    declare -a OPTION_VERSION=() OPTION_LABEL=() OPTION_KIND=()

    printf '%s\n' "Current OpenWrt version: ${CURRENT_VERSION}"
    printf '%s\n' "Current OpenWrt branch: ${CURRENT_BRANCH}"
    echo
    echo "Available upgrade targets:"
    echo "  0) Cancel"

    if [ "${CURRENT_VERSION}" != "${BRANCH_VERSION}" ]; then
      add_option "${BRANCH_VERSION}" "Current branch latest" "branch"
    fi

    if [ -n "${NEXT_STABLE_VERSION}" ] && [ "${NEXT_STABLE_VERSION}" != "null" ] && [ "${NEXT_STABLE_VERSION}" != "${BRANCH_VERSION}" ] && [ -n "${NEXT_STABLE_BRANCH}" ]; then
      add_option "${NEXT_STABLE_VERSION}" "Next stable major" "major"
    fi

    OPTION_COUNT="${#OPTION_VERSION[@]}"

    if [ "${OPTION_COUNT}" -eq 0 ]; then
      echo "No upgrade target is available."
      exit 0
    fi

    echo
    printf 'Select target version [0-%s]: ' "${OPTION_COUNT}"
    read -r SELECTION

    if [ "${SELECTION}" = "0" ]; then
      echo "Cancelled."
      exit 0
    fi

    case "${SELECTION}" in
      ''|*[!0-9]*)
        echo "Invalid selection."
        exit 1
        ;;
    esac

    if [ "${SELECTION}" -lt 1 ] || [ "${SELECTION}" -gt "${OPTION_COUNT}" ]; then
      echo "Selection out of range."
      exit 1
    fi

    SELECTED_INDEX=$((SELECTION - 1))
    TARGET_VERSION="${OPTION_VERSION[${SELECTED_INDEX}]}"
    TARGET_LABEL="${OPTION_LABEL[${SELECTED_INDEX}]}"
    TARGET_KIND="${OPTION_KIND[${SELECTED_INDEX}]}"

    echo
    echo "Selected target:"
    printf '%s\n' "  Version: ${TARGET_VERSION}"
    printf '%s\n' "  Kind: ${TARGET_LABEL}"
    if [ "${TARGET_KIND}" = "major" ]; then
      echo
      echo "WARNING: Major upgrades are riskier than current-branch upgrades."
    fi

    CHECK_OUTPUT="$(run_owut check "${TARGET_VERSION}" 2>&1)"

    SAFETY_LINE="$(first_check_line '^It is ')"
    WARNING_LINE="$(first_check_line '^WARNING: ')"
    ERROR_LINE="$(first_check_line '^ERROR: ')"
    FAILURE_SUMMARY="$(first_check_line '^There are currently package build failures')"

    echo
    echo "Preflight summary:"
    if [ -n "${SAFETY_LINE}" ]; then
      printf '%s\n' "  ${SAFETY_LINE}"
    else
      echo "  No explicit safety summary returned by owut."
    fi
    if [ -n "${WARNING_LINE}" ]; then
      printf '%s\n' "  ${WARNING_LINE}"
    fi
    if [ -n "${ERROR_LINE}" ]; then
      printf '%s\n' "  ${ERROR_LINE}"
    fi
    if [ -n "${FAILURE_SUMMARY}" ]; then
      printf '%s\n' "  ${FAILURE_SUMMARY}"
    fi

    FORCE_FLAG=""
    if [ "{{ force }}" = "true" ]; then
      FORCE_FLAG="--force"
    fi

    if printf '%s\n%s\n' "${WARNING_LINE}" "${ERROR_LINE}" | grep -qi 'package downgrades'; then
      if [ -z "${FORCE_FLAG}" ]; then
        echo
        printf 'Package downgrades detected by owut. Continue with forced upgrade? [y/N]: '
        read -r FORCE_CONFIRM

        case "${FORCE_CONFIRM}" in
          y|Y|yes|YES)
            FORCE_FLAG="--force"
            ;;
          *)
            echo "Cancelled."
            exit 1
            ;;
        esac
      fi

      echo
      echo "Force mode enabled: proceeding despite package downgrade warnings."
    fi

    echo
    printf '%s\n' "Checking ASU build availability for ${TARGET_VERSION}"
    asu_request_preflight "${TARGET_VERSION}"

    echo
    printf 'Proceed with OpenWrt attended sysupgrade to %s? [y/N]: ' "${TARGET_VERSION}"
    read -r CONFIRM

    case "${CONFIRM}" in
      y|Y|yes|YES)
        ;;
      *)
        echo "Cancelled."
        exit 0
        ;;
    esac

    printf '%s\n' "Starting attended sysupgrade to ${TARGET_VERSION}"
    set +e
    {{ ssh_router }} \
      "owut upgrade --verbose ${FORCE_FLAG} --version-to '${TARGET_VERSION}'"
    OWUT_SSH_STATUS=$?
    set -e

    case "${OWUT_SSH_STATUS}" in
      0|255)
        ;;
      *)
        printf '%s\n' "owut upgrade command failed before reboot with exit status ${OWUT_SSH_STATUS}"
        exit 1
        ;;
    esac

    echo "Waiting for router recovery and package feeds before reinstalling user packages"
    just openwrt reinstall-packages

    echo "Final router version:"
    {{ ssh_router }} 'ubus call system board' \
      | jq -r '"Version: \(.release.version)", "Revision: \(.release.revision)"'
