#!/bin/sh
# Downloads pinned GGUF files from HuggingFace into /models and verifies their sha256.
# Each line of /config/models.conf: <repo> <revision> <file> <sha256>
set -eu

# Prune GGUFs no longer listed, so the PVC holds only the current candidates.
listed="$(awk '!/^#/ && NF { print $3 }' /config/models.conf)"
for path in /models/*.gguf; do
  [ -e "${path}" ] || continue
  name="$(basename "${path}")"
  if ! echo "${listed}" | grep -qxF "${name}"; then
    echo ">> ${name}: no longer listed, removing"
    rm -f "${path}" "${path}.verified"
  fi
done

while read -r repo revision file sha256; do
  case "${repo}" in "" | "#"*) continue ;; esac
  target="/models/${file}"
  marker="${target}.verified"

  if [ -f "${marker}" ] && [ "$(cat "${marker}")" = "${sha256}" ]; then
    echo ">> ${file}: verified, skipping"
    continue
  fi

  # Same file name, different pin: never resume on top of the old bytes.
  if [ -f "${marker}" ]; then
    echo ">> ${file}: pin changed, discarding the old file"
    rm -f "${target}"
  fi

  echo ">> ${file}: downloading ${repo}@${revision}"
  rm -f "${marker}"
  # A resume of an already complete file can fail; the checksum below decides.
  curl --fail --location --retry 5 --retry-all-errors --continue-at - \
    --output "${target}" \
    "https://huggingface.co/${repo}/resolve/${revision}/${file}" ||
    echo ">> ${file}: download failed, verifying what is on disk"

  if ! echo "${sha256}  ${target}" | sha256sum -c -; then
    echo "error: ${file} sha256 mismatch, removing" >&2
    rm -f "${target}"
    exit 1
  fi
  echo "${sha256}" > "${marker}"
done < /config/models.conf
