set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
[script]
default:
    just -l sops

[doc('Decrypt and re-encrypt every *.sops.yaml file in the working tree')]
[script]
re-encrypt:
    if [ ! -f .sops.yaml ]; then
      echo "Missing SOPS config file (.sops.yaml)" >&2
      exit 1
    fi
    if [ -z "${SOPS_AGE_KEY_FILE:-}" ] || [ ! -f "${SOPS_AGE_KEY_FILE}" ]; then
      echo "Missing SOPS Age key file (SOPS_AGE_KEY_FILE)" >&2
      exit 1
    fi
    find . -type f -name '*.sops.yaml' ! -name '.sops.yaml' | while read -r f; do
      echo "Re-encrypting ${f}"
      sops --decrypt --in-place "${f}"
      sops --encrypt --in-place "${f}"
    done

[doc('Regenerate SOPS MAC for any kubernetes/**.sops.yaml where decryption fails with rc=51')]
[script]
fix-mac:
    if [ ! -f .sops.yaml ]; then
      echo "Missing SOPS config file (.sops.yaml)" >&2
      exit 1
    fi
    if [ -z "${SOPS_AGE_KEY_FILE:-}" ] || [ ! -f "${SOPS_AGE_KEY_FILE}" ]; then
      echo "Missing SOPS Age key file (SOPS_AGE_KEY_FILE)" >&2
      exit 1
    fi
    command -v vim >/dev/null || { echo "vim is required" >&2; exit 1; }
    find ./kubernetes -name '*.sops.yaml' | while read -r file; do
      sops -d "${file}" >/dev/null 2>&1 && rc=$? || rc=$?
      if [ "$rc" -eq 51 ]; then
        echo "Regenerating SOPS MAC for: ${file}"
        EDITOR="vim -es +'norm Go' +':wq'" sops --ignore-mac "${file}"
      fi
    done

[doc('Encrypt a file in place (just sops encrypt-file path/to/file.yaml)')]
[script]
encrypt-file file:
    if [ ! -f .sops.yaml ]; then
      echo "Missing SOPS config file (.sops.yaml)" >&2
      exit 1
    fi
    if [ ! -f "{{ file }}" ]; then
      echo "File does not exist: {{ file }}" >&2
      exit 1
    fi
    sops --encrypt --in-place "{{ file }}"

[doc('Decrypt a SOPS-encrypted file in place (just sops decrypt-file path/to/file.sops.yaml)')]
[script]
decrypt-file file:
    if [ ! -f .sops.yaml ]; then
      echo "Missing SOPS config file (.sops.yaml)" >&2
      exit 1
    fi
    if [ ! -f "{{ file }}" ]; then
      echo "File does not exist: {{ file }}" >&2
      exit 1
    fi
    sops --decrypt --in-place "{{ file }}"
