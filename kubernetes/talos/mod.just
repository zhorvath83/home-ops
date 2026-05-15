set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

talos_dir := justfile_dir() + '/kubernetes/talos'

[private]
[script]
default:
    just -l talos

[doc('Generate Talos factory schematic ID by POSTing schematic.yaml to factory.talos.dev')]
[script]
gen-schematic-id:
    curl -fsSL -X POST --data-binary @{{ talos_dir }}/schematic.yaml \
      https://factory.talos.dev/schematics \
      | jq -r .id

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

[doc('Download Talos metal-amd64 installer ISO (uses TALOS_VERSION env)')]
[script]
download-image:
    : "${TALOS_VERSION:?env TALOS_VERSION required (e.g. v1.13.2)}"
    sid="$(just talos gen-schematic-id)"
    out="{{ talos_dir }}/talos-${TALOS_VERSION}-${sid:0:8}.iso"
    just log info "Downloading Talos installer ISO" version "${TALOS_VERSION}" schematic "${sid}" out "${out}"
    curl -fsSL -o "${out}" \
      "https://factory.talos.dev/image/${sid}/${TALOS_VERSION}/metal-amd64.iso"

[doc('Burn Talos installer ISO to a USB device. Interactive picker if device omitted; refuses internal disks and disk images. Optional second arg: explicit ISO path (defaults to newest under kubernetes/talos/).')]
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

# Render the merged Talos machine config for a node (base + node patch), with
# op:// references resolved. Stdout = ready-to-apply YAML. Internal helper.
[private]
[script]
render node:
    : "${TALOS_VERSION:?env TALOS_VERSION required}"
    : "${KUBERNETES_VERSION:?env KUBERNETES_VERSION required}"
    : "${IS_CONTROLPLANE:=true}"
    TALOS_SCHEMATIC_ID="$(just talos gen-schematic-id)"
    export TALOS_SCHEMATIC_ID TALOS_VERSION KUBERNETES_VERSION IS_CONTROLPLANE
    base="$(mktemp)" patch="$(mktemp)" merged="$(mktemp)"
    trap 'rm -f "${base}" "${patch}" "${merged}"' EXIT
    minijinja-cli --env "{{ talos_dir }}/machineconfig.yaml.j2" > "${base}"
    minijinja-cli --env "{{ talos_dir }}/nodes/{{ node }}.yaml.j2" > "${patch}"
    talosctl machineconfig patch "${base}" --patch "@${patch}" -o "${merged}"
    op inject -i "${merged}"

[doc('Apply Talos config to a node. mode="" for normal apply, "--insecure" for first apply on a fresh installer')]
[script]
apply-node ip node="cp0-k8s" mode="":
    just talos render {{ node }} | talosctl apply-config -n {{ ip }} -f /dev/stdin {{ mode }}

[doc('Reset a Talos node (wipe STATE + EPHEMERAL, reboot to installer)')]
[script]
reset-node ip:
    talosctl -n {{ ip }} reset \
      --system-labels-to-wipe STATE \
      --system-labels-to-wipe EPHEMERAL \
      --graceful=false \
      --reboot

[doc('Reset the single-node cluster (alias for reset-node 192.168.1.11)')]
[script]
reset-cluster:
    just talos reset-node 192.168.1.11

[doc('Bootstrap etcd on a fresh control plane (one-time, after first apply)')]
[script]
bootstrap ip="192.168.1.11":
    talosctl -n {{ ip }} bootstrap

[doc('Fetch kubeconfig from the cluster (writes to ./kubeconfig)')]
[script]
kubeconfig ip="192.168.1.11":
    talosctl -n {{ ip }} kubeconfig -f --force-context-name main {{ justfile_dir() }}/kubeconfig

[doc('Upgrade Talos OS on a node (uses TALOS_VERSION + current schematic)')]
[script]
upgrade-node ip:
    : "${TALOS_VERSION:?env TALOS_VERSION required}"
    sid="$(just talos gen-schematic-id)"
    talosctl -n {{ ip }} upgrade \
      --image "factory.talos.dev/metal-installer/${sid}:${TALOS_VERSION}"

[doc('Upgrade Kubernetes to a specific version (e.g. v1.37.0)')]
[script]
upgrade-k8s version ip="192.168.1.11":
    talosctl --nodes {{ ip }} upgrade-k8s --to {{ version }}

[doc('Show node health, version, NIC links and disk inventory')]
[script]
status ip="192.168.1.11":
    talosctl -n {{ ip }} health
    talosctl -n {{ ip }} version
    talosctl -n {{ ip }} get links
    talosctl -n {{ ip }} get disks
