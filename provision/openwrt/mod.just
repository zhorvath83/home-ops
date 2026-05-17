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
nas_share_mount_script_on_mac := '~/Projects/personal/my-scripts-and-configs/macOS/btt-scripts/nas-share-mount.sh'
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

[doc('Run OpenWrt maintenance: copy latest backup locally, then interactive sysupgrade (force=true|false)')]
[script]
maintain force="false":
    set -eu

    LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC="$(eval printf '%s' "{{ nas_share_mount_script_on_mac }}")"
    BACKUP_PARENT_DIR="$(dirname "{{ openwrt_backup_dir_on_mac }}")"
    if [ ! -d "${BACKUP_PARENT_DIR}" ]; then
      if [ ! -x "${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}" ]; then
        echo "OpenWrt backup parent directory is missing: ${BACKUP_PARENT_DIR}"
        echo "NAS share mount script is not executable: ${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}"
        exit 1
      fi

      echo "OpenWrt backup parent directory is missing: ${BACKUP_PARENT_DIR}"
      echo "Attempting to mount NAS shares locally before copying backups"
      "${LOCAL_NAS_SHARE_MOUNT_SCRIPT_ON_MAC}"
    fi

    if [ ! -d "${BACKUP_PARENT_DIR}" ]; then
      echo "OpenWrt backup parent directory is still missing: ${BACKUP_PARENT_DIR}"
      echo "Refusing to create it automatically to avoid writing to the wrong disk."
      exit 1
    fi

    mkdir -p "{{ openwrt_backup_dir_on_mac }}"
    echo "Running OpenWrt maintenance on {{ openwrt_host }}"
    {{ ssh_router }} '
      set -eu
      {{ openwrt_local_package_list_script }} >/dev/null
      {{ openwrt_local_backup_script }}
    '

    BACKUP_FILE="$(
      {{ ssh_router }} \
        "ls -1t {{ openwrt_local_backup_dir }}/backup-*.tar.gz | head -n 1"
    )"

    if [ -z "${BACKUP_FILE}" ]; then
      echo "Unable to locate the latest OpenWrt backup in {{ openwrt_local_backup_dir }}"
      exit 1
    fi

    echo "Copying ${BACKUP_FILE} to {{ openwrt_backup_dir_on_mac }}"
    {{ scp_router }}:${BACKUP_FILE} "{{ openwrt_backup_dir_on_mac }}/"
    echo "Latest OpenWrt backup copied successfully."

    echo
    echo "Starting OpenWrt attended sysupgrade workflow"
    just openwrt upgrade "{{ force }}"

[doc('Wait for the OpenWrt router and package feeds, then rerun the saved user package reinstall script')]
[script]
reinstall-packages:
    set -eu

    # wait_for <label> <attempts> <delay_seconds> <ready_msg> <wait_msg> <check_cmd…>
    # Polls until <check_cmd> exits 0 or attempts are exhausted.
    wait_for() {
      local label="$1" attempts="$2" delay_seconds="$3" ready_msg="$4" wait_msg="$5"
      shift 5
      local attempt=1
      while [ "${attempt}" -le "${attempts}" ]; do
        if "$@" >/dev/null 2>&1; then
          echo "${label}: ${ready_msg}"
          return 0
        fi
        echo "${label}: ${wait_msg} (${attempt}/${attempts})..."
        sleep "${delay_seconds}"
        attempt=$((attempt + 1))
      done
      echo "${label}: did not become ready in time."
      return 1
    }

    check_router() {
      {{ ssh_router }} 'ubus call system board >/dev/null'
    }
    check_package_repos() {
      {{ ssh_router }} '
        set -eu
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
      set -eu
      if [ ! -x '{{ openwrt_local_reinstall_script }}' ]; then
        echo 'Reinstall script is missing or not executable: {{ openwrt_local_reinstall_script }}'
        exit 1
      fi
      '{{ openwrt_local_reinstall_script }}'
    "

[doc('Interactively upgrade OpenWrt with attended sysupgrade through owut (force=true|false)')]
[script]
upgrade force="false":
    set -eu

    # run_owut <subcmd> <version_to>
    # `check` is invoked with `2>&1` by the caller so awk can scan
    # WARNING:/ERROR: lines on stdout; `blob` keeps stderr separate so the
    # JSON body stays clean for the curl POST.
    run_owut() {
      local subcmd="$1" version_to="$2"
      {{ ssh_router }} "
        set -eu
        if ! command -v owut >/dev/null 2>&1; then
          echo 'owut is not installed on the router'
          exit 1
        fi
        owut ${subcmd} --version-to '${version_to}'
      "
    }

    asu_request_preflight() {
      version_to="$1"
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
          echo "ASU preflight: build request accepted (${request_hash})."
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
      echo "ASU preflight failed for ${version_to} (HTTP ${http_status})."
      if [ -n "${detail}" ]; then
        echo "${detail}"
      fi
      return 1
    }

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
    BRANCH_VERSION="$(
      printf '%s' "${OVERVIEW_JSON}" \
        | jq -r --arg branch "${CURRENT_BRANCH}" '
            [.branches[$branch].versions[]? | select(contains("-") | not)]
            | sort_by(split(".") | map(tonumber))
            | last
          '
    )"
    NEXT_STABLE_BRANCH="$(
      if [ "${CURRENT_BRANCH}" != "SNAPSHOT" ]; then
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
      fi
    )"
    NEXT_STABLE_VERSION="$(
      if [ -n "${NEXT_STABLE_BRANCH}" ]; then
        printf '%s' "${OVERVIEW_JSON}" \
          | jq -r --arg branch "${NEXT_STABLE_BRANCH}" '
              [.branches[$branch].versions[]? | select(contains("-") | not)]
              | sort_by(split(".") | map(tonumber))
              | last
            '
      fi
    )"

    if [ -z "${CURRENT_VERSION}" ] || [ -z "${CURRENT_BRANCH}" ] || [ -z "${BRANCH_VERSION}" ] || [ "${CURRENT_VERSION}" = "null" ] || [ "${BRANCH_VERSION}" = "null" ]; then
      echo "Unable to determine current OpenWrt version or available upgrade versions."
      exit 1
    fi

    OPTION_COUNT=0
    TARGET_VERSION=""
    TARGET_LABEL=""
    TARGET_KIND=""
    OPTION_1_VERSION=""
    OPTION_1_LABEL=""
    OPTION_1_KIND=""
    OPTION_2_VERSION=""
    OPTION_2_LABEL=""
    OPTION_2_KIND=""
    FORCE_FLAG=""

    echo "Current OpenWrt version: ${CURRENT_VERSION}"
    echo "Current OpenWrt branch: ${CURRENT_BRANCH}"
    echo
    echo "Available upgrade targets:"
    echo "  0) Cancel"

    if [ "${CURRENT_VERSION}" != "${BRANCH_VERSION}" ]; then
      OPTION_COUNT=$((OPTION_COUNT + 1))
      if [ "${OPTION_COUNT}" -eq 1 ]; then
        OPTION_1_VERSION="${BRANCH_VERSION}"
        OPTION_1_LABEL="Current branch latest"
        OPTION_1_KIND="branch"
      else
        OPTION_2_VERSION="${BRANCH_VERSION}"
        OPTION_2_LABEL="Current branch latest"
        OPTION_2_KIND="branch"
      fi
      echo "  ${OPTION_COUNT}) ${BRANCH_VERSION}  [Current branch latest]"
    fi

    if [ -n "${NEXT_STABLE_VERSION}" ] && [ "${NEXT_STABLE_VERSION}" != "null" ] && [ "${NEXT_STABLE_VERSION}" != "${BRANCH_VERSION}" ] && [ -n "${NEXT_STABLE_BRANCH}" ]; then
      OPTION_COUNT=$((OPTION_COUNT + 1))
      if [ "${OPTION_COUNT}" -eq 1 ]; then
        OPTION_1_VERSION="${NEXT_STABLE_VERSION}"
        OPTION_1_LABEL="Next stable major"
        OPTION_1_KIND="major"
      else
        OPTION_2_VERSION="${NEXT_STABLE_VERSION}"
        OPTION_2_LABEL="Next stable major"
        OPTION_2_KIND="major"
      fi
      echo "  ${OPTION_COUNT}) ${NEXT_STABLE_VERSION}  [Next stable major]"
    fi

    if [ "${OPTION_COUNT}" -eq 0 ]; then
      echo "No upgrade target is available."
      exit 0
    fi

    echo
    printf "Select target version [0-%s]: " "${OPTION_COUNT}"
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

    case "${SELECTION}" in
      1)
        TARGET_VERSION="${OPTION_1_VERSION}"
        TARGET_LABEL="${OPTION_1_LABEL}"
        TARGET_KIND="${OPTION_1_KIND}"
        ;;
      2)
        TARGET_VERSION="${OPTION_2_VERSION}"
        TARGET_LABEL="${OPTION_2_LABEL}"
        TARGET_KIND="${OPTION_2_KIND}"
        ;;
      *)
        echo "Unsupported selection."
        exit 1
        ;;
    esac

    echo
    echo "Selected target:"
    echo "  Version: ${TARGET_VERSION}"
    echo "  Kind: ${TARGET_LABEL}"
    if [ "${TARGET_KIND}" = "major" ]; then
      echo
      echo "WARNING: Major upgrades are riskier than current-branch upgrades."
    fi

    CHECK_OUTPUT="$(run_owut check "${TARGET_VERSION}" 2>&1)"

    SAFETY_LINE="$(
      printf '%s\n' "${CHECK_OUTPUT}" \
        | awk '/^It is / {print; exit}'
    )"
    WARNING_LINE="$(
      printf '%s\n' "${CHECK_OUTPUT}" \
        | awk '/^WARNING: / {print; exit}'
    )"
    ERROR_LINE="$(
      printf '%s\n' "${CHECK_OUTPUT}" \
        | awk '/^ERROR: / {print; exit}'
    )"
    FAILURE_SUMMARY="$(
      printf '%s\n' "${CHECK_OUTPUT}" \
        | awk '/^There are currently package build failures/ {print; exit}'
    )"

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

    if [ "{{ force }}" = "true" ]; then
      FORCE_FLAG="--force"
    fi

    if printf '%s\n%s\n' "${WARNING_LINE}" "${ERROR_LINE}" | grep -qi 'package downgrades'; then
      if [ -z "${FORCE_FLAG}" ]; then
        echo
        printf "Package downgrades detected by owut. Continue with forced upgrade? [y/N]: "
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
    echo "Checking ASU build availability for ${TARGET_VERSION}"
    asu_request_preflight "${TARGET_VERSION}"

    echo
    printf "Proceed with OpenWrt attended sysupgrade to %s? [y/N]: " "${TARGET_VERSION}"
    read -r CONFIRM

    case "${CONFIRM}" in
      y|Y|yes|YES)
        ;;
      *)
        echo "Cancelled."
        exit 0
        ;;
    esac

    echo "Starting attended sysupgrade to ${TARGET_VERSION}"
    set +e
    {{ ssh_router }} \
      "owut upgrade --verbose ${FORCE_FLAG} --version-to '${TARGET_VERSION}'"
    OWUT_SSH_STATUS=$?
    set -e

    case "${OWUT_SSH_STATUS}" in
      0|255)
        ;;
      *)
        echo "owut upgrade command failed before reboot with exit status ${OWUT_SSH_STATUS}"
        exit 1
        ;;
    esac

    echo "Waiting for router recovery and package feeds before reinstalling user packages"
    just openwrt reinstall-packages

    echo "Final router version:"
    {{ ssh_router }} 'ubus call system board' \
      | jq -r '"Version: \(.release.version)", "Revision: \(.release.revision)"'
