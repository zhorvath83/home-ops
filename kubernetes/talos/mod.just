set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

talos_dir := justfile_dir() + '/kubernetes/talos'

# Default control plane node — fallback when no talosconfig exists yet
# (pre-bootstrap, fresh repo clone). Single hardcoded source of truth.
# Must match the filename under nodes/<NAME>.yaml.j2 AND be resolvable on
# the LAN (cp0-k8s.lan via OpenWRT dnsmasq → 192.168.1.11).
default_node := 'cp0-k8s'

# controller_node: dynamically extracted from the active talosconfig endpoint
# (set by `gen-talosconfig`). Falls back to default_node if talosconfig is
# absent. `set lazy` above defers evaluation until a recipe actually uses it.
controller_node := `talosctl config info -o yaml 2>/dev/null | yq -e '.endpoints[0]' 2>/dev/null || echo 'cp0-k8s'`

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
    extract() {
        local path=$1 value
        value="$(yq -r "${path}" "${tmp}")"
        if [ -z "${value}" ] || [ "${value}" = "null" ]; then
            just log error "Empty value in secrets bundle" path "${path}"
            exit 1
        fi
        printf '%s' "${value}"
    }
    just log info "Creating 1Password item" vault "{{ vault }}" item "{{ item }}"
    op item create \
        --category="API Credential" \
        --vault="{{ vault }}" \
        --title="{{ item }}" \
        "MACHINE_CA_CRT[password]=$(extract '.certs.os.crt')" \
        "MACHINE_CA_KEY[password]=$(extract '.certs.os.key')" \
        "MACHINE_TOKEN[password]=$(extract '.trustdinfo.token')" \
        "CLUSTER_CA_CRT[password]=$(extract '.certs.k8s.crt')" \
        "CLUSTER_CA_KEY[password]=$(extract '.certs.k8s.key')" \
        "CLUSTER_AGGREGATORCA_CRT[password]=$(extract '.certs.k8saggregator.crt')" \
        "CLUSTER_AGGREGATORCA_KEY[password]=$(extract '.certs.k8saggregator.key')" \
        "CLUSTER_SERVICEACCOUNT_KEY[password]=$(extract '.certs.k8sserviceaccount.key')" \
        "CLUSTER_ETCD_CA_CRT[password]=$(extract '.certs.etcd.crt')" \
        "CLUSTER_ETCD_CA_KEY[password]=$(extract '.certs.etcd.key')" \
        "CLUSTER_ID[password]=$(extract '.cluster.id')" \
        "CLUSTER_SECRET[password]=$(extract '.cluster.secret')" \
        "CLUSTER_TOKEN[password]=$(extract '.secrets.bootstraptoken')" \
        "CLUSTER_SECRETBOXENCRYPTIONSECRET[password]=$(extract '.secrets.secretboxencryptionsecret')"

[group('setup')]
[doc('Generate talosconfig from 1Password secrets (one-time, after gen-secrets)')]
[script]
gen-talosconfig endpoint="https://k8s.lan:6443" cluster="main" node=default_node:
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
            location=$(diskutil info "${target}" | awk -F: '/Device Location/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
            protocol=$(diskutil info "${target}" | awk -F: '/Protocol/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
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
[doc('Render Talos config for a node (base + node patch merged, op:// refs resolved). Stdout = ready-to-apply YAML; useful for dry-run before apply.')]
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
[doc('Apply Talos config to a node (pass extra talosctl flags as args, e.g. --insecure)')]
[script]
apply-node node *args:
    just talos render-config {{ node }} | talosctl -n {{ node }} apply-config -f /dev/stdin {{ args }}

[group('recovery')]
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
[doc('Reset the single-node cluster (alias for reset-node with controller_node)')]
[script]
reset-cluster:
    just talos reset-node {{ controller_node }}

[group('lifecycle')]
[doc('Reboot a Talos node (powercycle mode = full hardware reset)')]
[script]
reboot-node node:
    talosctl -n {{ node }} reboot -m powercycle

[group('lifecycle')]
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
[doc('Upgrade Kubernetes to a specific version (e.g. v1.37.0)')]
[script]
upgrade-k8s version node=controller_node:
    talosctl --nodes {{ node }} upgrade-k8s --to {{ version }}

[group('lifecycle')]
[doc('Show node health, version, NIC links and disk inventory')]
[script]
status node=controller_node:
    talosctl -n {{ node }} health
    talosctl -n {{ node }} version
    talosctl -n {{ node }} get links
    talosctl -n {{ node }} get disks
