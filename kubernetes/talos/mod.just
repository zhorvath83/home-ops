set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

talos_dir := justfile_dir() + '/kubernetes/talos'

# controller_node: resolved by ./_resolve-controller.sh (single source of
# truth, shared with kubernetes/bootstrap/mod.just). `set lazy` defers
# evaluation until a recipe actually uses it. Backticks run with cwd =
# this mod's directory, so the relative path is stable.
controller_node := `bash ./_resolve-controller.sh`

# nodes: derive node *names* from kubernetes/talos/nodes/<name>.yaml.j2 — filesystem-based so it works pre-bootstrap.
# Backticks run with cwd = this mod's directory (kubernetes/talos), so reach into the sibling nodes/ tree directly.
# Single-line output is critical; `tr` flattens newlines to spaces for shell `for` consumption.
nodes := `find ./nodes -maxdepth 1 -name '*.yaml.j2' -exec basename {} .yaml.j2 \; 2>/dev/null | tr '\n' ' '`

[private]
[script]
default:
    just -l talos

[group('image')]
[doc('Generate Talos factory schematic ID by POSTing schematic.yaml to factory.talos.dev')]
[script]
gen-schematic-id:
    curl -fsSL -X POST --data-binary @{{ talos_dir }}/schematic.yaml \
      https://factory.talos.dev/schematics \
      | jq -r .id

[group('setup')]
[doc('Generate Talos cluster secrets and store them as a 1Password API Credential item (one-time per cluster)')]
[script]
gen-secrets vault="HomeOps" item="talos":
    if op item get "{{ item }}" --vault "{{ vault }}" >/dev/null 2>&1; then
        just log error "1Password item already exists" vault "{{ vault }}" item "{{ item }}"
        echo "To regenerate (DESTRUCTIVE — invalidates any cluster using these secrets):" >&2
        echo "    op item delete '{{ item }}' --vault '{{ vault }}'" >&2
        exit 1
    fi
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
    tmp="${tmpdir}/talos-secrets.yaml"
    just log info "Generating Talos secrets bundle"
    talosctl gen secrets -o "${tmp}"
    # `extract` must `return 1` (not `exit 1`): the helper is invoked via
    # `$(extract …)` command substitution, which runs in a subshell, so an
    # `exit` would only kill that subshell. The caller chains `|| exit 1`
    # so an empty/null value aborts the whole recipe instead of silently
    # writing the bad value into the 1Password item.
    extract() {
        local path=$1 value
        value="$(yq -r "${path}" "${tmp}")"
        if [ -z "${value}" ] || [ "${value}" = "null" ]; then
            just log error "Empty value in secrets bundle" path "${path}"
            return 1
        fi
        printf '%s' "${value}"
    }
    machine_ca_crt="$(extract '.certs.os.crt')" || exit 1
    machine_ca_key="$(extract '.certs.os.key')" || exit 1
    machine_token="$(extract '.trustdinfo.token')" || exit 1
    cluster_ca_crt="$(extract '.certs.k8s.crt')" || exit 1
    cluster_ca_key="$(extract '.certs.k8s.key')" || exit 1
    cluster_aggregatorca_crt="$(extract '.certs.k8saggregator.crt')" || exit 1
    cluster_aggregatorca_key="$(extract '.certs.k8saggregator.key')" || exit 1
    cluster_serviceaccount_key="$(extract '.certs.k8sserviceaccount.key')" || exit 1
    cluster_etcd_ca_crt="$(extract '.certs.etcd.crt')" || exit 1
    cluster_etcd_ca_key="$(extract '.certs.etcd.key')" || exit 1
    cluster_id="$(extract '.cluster.id')" || exit 1
    cluster_secret="$(extract '.cluster.secret')" || exit 1
    cluster_token="$(extract '.secrets.bootstraptoken')" || exit 1
    cluster_secretboxencryptionsecret="$(extract '.secrets.secretboxencryptionsecret')" || exit 1
    just log info "Creating 1Password item" vault "{{ vault }}" item "{{ item }}"
    op item create \
        --category="API Credential" \
        --vault="{{ vault }}" \
        --title="{{ item }}" \
        "MACHINE_CA_CRT[password]=${machine_ca_crt}" \
        "MACHINE_CA_KEY[password]=${machine_ca_key}" \
        "MACHINE_TOKEN[password]=${machine_token}" \
        "CLUSTER_CA_CRT[password]=${cluster_ca_crt}" \
        "CLUSTER_CA_KEY[password]=${cluster_ca_key}" \
        "CLUSTER_AGGREGATORCA_CRT[password]=${cluster_aggregatorca_crt}" \
        "CLUSTER_AGGREGATORCA_KEY[password]=${cluster_aggregatorca_key}" \
        "CLUSTER_SERVICEACCOUNT_KEY[password]=${cluster_serviceaccount_key}" \
        "CLUSTER_ETCD_CA_CRT[password]=${cluster_etcd_ca_crt}" \
        "CLUSTER_ETCD_CA_KEY[password]=${cluster_etcd_ca_key}" \
        "CLUSTER_ID[password]=${cluster_id}" \
        "CLUSTER_SECRET[password]=${cluster_secret}" \
        "CLUSTER_TOKEN[password]=${cluster_token}" \
        "CLUSTER_SECRETBOXENCRYPTIONSECRET[password]=${cluster_secretboxencryptionsecret}"

[group('setup')]
[doc('Generate talosconfig from 1Password secrets (one-time, after gen-secrets)')]
[script]
gen-talosconfig endpoint="https://192.168.1.11:6443" cluster="main" node=controller_node:
    : "${TALOSCONFIG:?env TALOSCONFIG required (set by .mise.toml)}"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
    # Reconstruct the Talos secrets bundle from 1Password (same fields as
    # gen-secrets pushed). Talos expects base64-encoded cert/key strings,
    # which is exactly how 1Password stores them.
    cat > "${tmpdir}/secrets.yaml.j2" <<'EOF'
    cluster:
      id: op://HomeOps/talos/CLUSTER_ID
      secret: op://HomeOps/talos/CLUSTER_SECRET
    secrets:
      bootstraptoken: op://HomeOps/talos/CLUSTER_TOKEN
      secretboxencryptionsecret: op://HomeOps/talos/CLUSTER_SECRETBOXENCRYPTIONSECRET
    trustdinfo:
      token: op://HomeOps/talos/MACHINE_TOKEN
    certs:
      etcd:
        crt: op://HomeOps/talos/CLUSTER_ETCD_CA_CRT
        key: op://HomeOps/talos/CLUSTER_ETCD_CA_KEY
      k8s:
        crt: op://HomeOps/talos/CLUSTER_CA_CRT
        key: op://HomeOps/talos/CLUSTER_CA_KEY
      k8saggregator:
        crt: op://HomeOps/talos/CLUSTER_AGGREGATORCA_CRT
        key: op://HomeOps/talos/CLUSTER_AGGREGATORCA_KEY
      k8sserviceaccount:
        key: op://HomeOps/talos/CLUSTER_SERVICEACCOUNT_KEY
      os:
        crt: op://HomeOps/talos/MACHINE_CA_CRT
        key: op://HomeOps/talos/MACHINE_CA_KEY
    EOF
    op inject -i "${tmpdir}/secrets.yaml.j2" -o "${tmpdir}/secrets.yaml"
    just log info "Generating talosconfig" cluster "{{ cluster }}" endpoint "{{ endpoint }}"
    talosctl gen config "{{ cluster }}" "{{ endpoint }}" \
      --with-secrets "${tmpdir}/secrets.yaml" \
      --output-types talosconfig \
      --output "${TALOSCONFIG}" \
      --force
    just log info "Setting talosctl endpoint and node" node "{{ node }}"
    talosctl config endpoint "{{ node }}"
    talosctl config node "{{ node }}"
    just log info "Talosconfig written" file "${TALOSCONFIG}"

[group('image')]
[doc('Download Talos metal-amd64 installer ISO (uses TALOS_VERSION env)')]
[script]
download-image:
    : "${TALOS_VERSION:?env TALOS_VERSION required (e.g. v1.13.2)}"
    sid="$(just talos gen-schematic-id)"
    out="{{ talos_dir }}/talos-${TALOS_VERSION}-${sid:0:8}.iso"
    just log info "Downloading Talos installer ISO" version "${TALOS_VERSION}" schematic "${sid}" out "${out}"
    curl -fsSL -o "${out}" \
      "https://factory.talos.dev/image/${sid}/${TALOS_VERSION}/metal-amd64.iso"

[group('image')]
[doc('Burn Talos installer ISO to USB (interactive picker if no device given)')]
[script]
burn-image device="" iso="":
    # 1. Resolve ISO
    img="{{ iso }}"
    if [ -z "${img}" ]; then
        img="$(ls -t {{ talos_dir }}/talos-*.iso 2>/dev/null | head -1)"
    fi
    if [ -z "${img}" ] || [ ! -f "${img}" ]; then
        just log error "ISO not found" path "${img:-<none under kubernetes/talos>}"
        echo "Run 'just talos download-image' first, or pass an ISO path as the second argument." >&2
        exit 1
    fi
    # 2. Resolve target — interactive picker if device omitted
    target="{{ device }}"
    if [ -z "${target}" ]; then
        case "$(uname -s)" in
            Darwin)
                # External physical disks only (excludes disk images, internal)
                opts=""
                for d in $(diskutil list external physical 2>/dev/null | grep -E '^/dev/' | awk '{print $1}'); do
                    info=$(diskutil info "${d}")
                    size=$(echo "${info}" | awk -F: '/Disk Size/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
                    name=$(echo "${info}" | awk -F: '/Device \/ Media Name/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
                    opts+="${d} — ${size} | ${name}"$'\n'
                done
                ;;
            Linux)
                opts=$(lsblk -dnpo NAME,SIZE,MODEL,TRAN,RM 2>/dev/null \
                  | awk '($4=="usb"||$5=="1") {printf "%s — %s | %s\n", $1, $2, $3}')
                ;;
            *) just log error "Unsupported OS"; exit 1 ;;
        esac
        if [ -z "${opts}" ]; then
            just log error "No external/removable disks found — plug in a USB and retry"
            exit 1
        fi
        choice=$(printf '%s' "${opts}" | gum choose --header "Select target USB device (will be WIPED)")
        [ -z "${choice}" ] && { just log info "Aborted"; exit 0; }
        target=$(echo "${choice}" | awk '{print $1}')
    fi
    # 3. Validate target exists + is external/USB/removable + not a disk image
    if [ ! -e "${target}" ]; then
        just log error "Device not found" device "${target}"
        exit 1
    fi
    case "$(uname -s)" in
        Darwin)
            info=$(diskutil info "${target}")
            location=$(printf '%s\n' "${info}" | awk -F: '/Device Location/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
            protocol=$(printf '%s\n' "${info}" | awk -F: '/Protocol/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
            if [ "${location}" != "External" ]; then
                just log error "Refusing — not an external disk" device "${target}" location "${location}"
                exit 1
            fi
            if [ "${protocol}" = "Disk Image" ]; then
                just log error "Refusing — target is a disk image, not physical media" device "${target}"
                exit 1
            fi
            ;;
        Linux)
            tran=$(lsblk -dnro TRAN "${target}" 2>/dev/null)
            rmv=$(lsblk -dnro RM "${target}" 2>/dev/null)
            if [ "${tran}" != "usb" ] && [ "${rmv}" != "1" ]; then
                just log error "Refusing — not USB/removable" device "${target}" transport "${tran}" removable "${rmv}"
                exit 1
            fi
            ;;
    esac
    # 4. Confirm
    just log warn "Target device will be WIPED" device "${target}" iso "${img}"
    case "$(uname -s)" in
        Darwin) diskutil info "${target}" | grep -E "Device Node|Device / Media Name|Disk Size|Protocol|Device Location|Removable Media" || true ;;
        Linux)  lsblk -o NAME,SIZE,MODEL,TRAN,RM "${target}" 2>/dev/null || true ;;
    esac
    gum confirm "Continue and WIPE ${target}?" || { just log info "Aborted"; exit 0; }
    # 5. Unmount + write + eject
    case "$(uname -s)" in
        Darwin)
            diskutil unmountDisk "${target}"
            raw="$(echo "${target}" | sed 's|/dev/disk|/dev/rdisk|')"
            just log info "Writing to ${raw} (press Ctrl+T for progress; takes a few minutes)"
            sudo dd if="${img}" of="${raw}" bs=4m
            sync
            diskutil eject "${target}"
            ;;
        Linux)
            for p in $(lsblk -nrpo NAME "${target}" | tail -n +2); do
                sudo umount "${p}" 2>/dev/null || true
            done
            just log info "Writing to ${target}"
            sudo dd if="${img}" of="${target}" bs=4M status=progress
            sync
            sudo eject "${target}" 2>/dev/null || true
            ;;
    esac
    just log info "Done — USB ready, can be removed safely"

[group('config')]
[doc('Render Talos config for a node (base + node patch merged). Useful for dry-run before apply.')]
[script]
render-config node:
    : "${TALOS_VERSION:?env TALOS_VERSION required}"
    : "${KUBERNETES_VERSION:?env KUBERNETES_VERSION required}"
    : "${IS_CONTROLPLANE:=true}"
    TALOS_SCHEMATIC_ID="$(just talos gen-schematic-id)"
    export TALOS_SCHEMATIC_ID TALOS_VERSION KUBERNETES_VERSION IS_CONTROLPLANE
    base="$(mktemp)" patch="$(mktemp)"
    trap 'rm -f "${base}" "${patch}"' EXIT
    # `op inject` must run BEFORE `talosctl machineconfig patch`, otherwise
    # the latter rejects the op://… placeholders as malformed base64 in the
    # cert/key fields. (No op://… refs in node patches today, so the patch
    # file does not need op inject.)
    minijinja-cli --env "{{ talos_dir }}/machineconfig.yaml.j2" | op inject > "${base}"
    minijinja-cli --env "{{ talos_dir }}/nodes/{{ node }}.yaml.j2" > "${patch}"
    talosctl machineconfig patch "${base}" --patch "@${patch}"

[group('config')]
[confirm('Apply Talos config to ' + node + ' [y|N] ?')]
[doc('Apply Talos config to a node (pass extra talosctl flags as args, e.g. --insecure). Bypass prompt via `just --yes talos apply-node ...` (used internally by the bootstrap chain).')]
[script]
apply-node node *args:
    just talos render-config {{ node }} | talosctl -n {{ node }} apply-config -f /dev/stdin {{ args }}

[group('config')]
[doc('Apply Talos config to every node defined under nodes/*.yaml.j2 (per-node confirm prompt via apply-node)')]
[script]
apply-cluster *args:
    for n in {{ nodes }}; do
      just talos apply-node "$n" {{ args }}
    done

[group('config')]
[doc('Print whether a node is a controlplane (from its rendered machineconfig)')]
[script]
machine-controller node=controller_node:
    just talos render-config "{{ node }}" | yq -e 'select(.machine) | (.machine.type == "controlplane") // ""'

[group('config')]
[doc('Print the Talos install image used by a node (from its rendered machineconfig)')]
[script]
machine-image node=controller_node:
    just talos render-config "{{ node }}" | yq -e 'select(.machine) | .machine.install.image'

[group('recovery')]
[confirm('Reset node ' + node + ' (wipes STATE + EPHEMERAL + u-local-hostpath) [y|N] ?')]
[doc('Reset a Talos node (wipe STATE + EPHEMERAL + u-local-hostpath, reboot to installer)')]
[script]
reset-node node:
    talosctl -n {{ node }} reset \
      --system-labels-to-wipe STATE \
      --system-labels-to-wipe EPHEMERAL \
      --system-labels-to-wipe u-local-hostpath \
      --graceful=false \
      --reboot

[group('recovery')]
[doc('Reset every node defined under nodes/*.yaml.j2 (per-node confirm prompt via reset-node)')]
[script]
reset-cluster:
    for n in {{ nodes }}; do
      just talos reset-node "$n"
    done

[group('lifecycle')]
[doc('Reboot a Talos node (powercycle mode = full hardware reset)')]
[script]
reboot-node node:
    talosctl -n {{ node }} reboot -m powercycle

[group('lifecycle')]
[confirm('Shutdown node ' + node + ' [y|N] ?')]
[doc('Shutdown a Talos node (force). Pass extra talosctl flags as additional args.')]
[script]
shutdown-node node *args:
    talosctl -n {{ node }} shutdown --force {{ args }}

[group('setup')]
[doc('Bootstrap etcd on a fresh control plane (one-time, after first apply)')]
[script]
bootstrap node=controller_node:
    talosctl -n {{ node }} bootstrap

[group('setup')]
[doc('Fetch kubeconfig from the cluster (writes to ./kubeconfig)')]
[script]
get-kubeconfig node=controller_node:
    talosctl -n {{ node }} kubeconfig -f --force-context-name main {{ justfile_dir() }}/kubeconfig

[group('lifecycle')]
[confirm('Upgrade Talos OS on ' + node + ' [y|N] ?')]
[doc('Upgrade Talos OS on a node (uses TALOS_VERSION + current schematic, powercycle reboot, 10m timeout)')]
[script]
upgrade-node node=controller_node:
    : "${TALOS_VERSION:?env TALOS_VERSION required}"
    sid="$(just talos gen-schematic-id)"
    talosctl -n {{ node }} upgrade \
      --image "factory.talos.dev/metal-installer/${sid}:${TALOS_VERSION}" \
      -m powercycle \
      --timeout=10m

[group('lifecycle')]
[confirm('Upgrade Kubernetes control plane on ' + node + ' to ' + env_var('KUBERNETES_VERSION') + ' [y|N] ?')]
[doc('Upgrade Kubernetes on a node to the version pinned in mise.toml (KUBERNETES_VERSION)')]
[script]
upgrade-k8s node=controller_node:
    : "${KUBERNETES_VERSION:?env KUBERNETES_VERSION required}"
    talosctl --nodes {{ node }} upgrade-k8s --to "${KUBERNETES_VERSION}"

[group('lifecycle')]
[doc('Show node health, version, NIC links and disk inventory')]
[script]
status node=controller_node:
    talosctl -n {{ node }} health
    talosctl -n {{ node }} version
    talosctl -n {{ node }} get links
    talosctl -n {{ node }} get disks

[group('lifecycle')]
[doc('Dump Talos diagnostics to a log file (services, events, logs, dmesg, resources)')]
[script]
diag node=controller_node:
    out="talos-diag.log"
    rm -f "${out}"
    {
      echo '=========================================='
      echo "Talos diagnostics — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "Node: {{ node }}"
      echo '=========================================='
    } > "${out}"

    section() {
      echo "==> $1" >&2
      printf '\n### %s ###\n' "$1" >> "${out}"
    }
    # run <label> <cmd> [args...] — header + redirected execution + failure marker.
    # For commands that need a pipeline (e.g. talosctl dmesg | tail), wrap the
    # pipeline in a tiny shell function and pass the function name as <cmd>.
    run() {
      local label=$1; shift
      section "${label}"
      "$@" >> "${out}" 2>&1 || echo "(failed)" >> "${out}"
    }

    run "service" talosctl -n {{ node }} service

    # `talosctl events --tail=N` streams indefinitely after the initial dump,
    # and Talos rejects --tail combined with --duration. macOS has no
    # timeout(1), so we run events in the background and send SIGINT after 5 s
    # (SIGINT is the signal talosctl handles cleanly on Ctrl+C).
    section "events (last 200, bounded 5s)"
    talosctl -n {{ node }} events --tail=200 >> "${out}" 2>&1 &
    events_pid=$!
    ( sleep 5; kill -INT "${events_pid}" 2>/dev/null ) &
    killer_pid=$!
    wait "${events_pid}" 2>/dev/null || true
    kill "${killer_pid}" 2>/dev/null || true
    wait "${killer_pid}" 2>/dev/null || true

    run "machined logs (last 200)" talosctl -n {{ node }} logs --tail=200 machined
    run "controller-runtime logs (last 200)" talosctl -n {{ node }} logs --tail=200 controller-runtime

    dmesg_tail() { talosctl -n {{ node }} dmesg 2>&1 | tail -200; }
    run "dmesg (last 200)" dmesg_tail

    run "volumestatuses" talosctl -n {{ node }} get volumestatuses
    run "hostnamestatus"  talosctl -n {{ node }} get hostnamestatus
    run "linkstatus"      talosctl -n {{ node }} get linkstatus

    echo "==> done: ${out} ($(wc -l < "${out}" | tr -d ' ') lines)" >&2
