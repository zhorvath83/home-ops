set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# Default Age key location — overridden by SOPS_AGE_KEY_FILE env var.
default_age_key_file := env('HOME') + '/.config/sops/age/keys.txt'

[private]
[script]
default:
    just -l sops

# Shared `.sops.yaml` presence check. Used as a `dependency: _check-config`
# prerequisite so recipes don't repeat the same guard inline. Exits non-zero
# on failure, which propagates to the dependent recipe under `set -e`.
[private]
[script]
_check-config:
    [ -f .sops.yaml ] || { echo "Missing SOPS config file (.sops.yaml)" >&2; exit 1; }

[doc('Decrypt and re-encrypt every *.sops.yaml file in the working tree')]
[script]
re-encrypt: _check-config
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-{{ default_age_key_file }}}"
    [ -f "${SOPS_AGE_KEY_FILE}" ] || { echo "Missing SOPS Age key file at ${SOPS_AGE_KEY_FILE} (set SOPS_AGE_KEY_FILE if it lives elsewhere)" >&2; exit 1; }
    find . -type f -name '*.sops.yaml' ! -name '.sops.yaml' | while read -r f; do
      echo "Re-encrypting ${f}"
      sops --decrypt --in-place "${f}"
      sops --encrypt --in-place "${f}"
    done

[doc('Regenerate SOPS MAC for any kubernetes/**.sops.yaml where decryption fails with rc=51')]
[script]
fix-mac: _check-config
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-{{ default_age_key_file }}}"
    [ -f "${SOPS_AGE_KEY_FILE}" ] || { echo "Missing SOPS Age key file at ${SOPS_AGE_KEY_FILE} (set SOPS_AGE_KEY_FILE if it lives elsewhere)" >&2; exit 1; }
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
encrypt-file file: _check-config
    [ -f "{{ file }}" ] || { echo "File does not exist: {{ file }}" >&2; exit 1; }
    sops --encrypt --in-place "{{ file }}"

[doc('Decrypt a SOPS-encrypted file in place (just sops decrypt-file path/to/file.sops.yaml)')]
[script]
decrypt-file file: _check-config
    [ -f "{{ file }}" ] || { echo "File does not exist: {{ file }}" >&2; exit 1; }
    sops --decrypt --in-place "{{ file }}"
