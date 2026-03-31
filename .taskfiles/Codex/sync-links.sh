#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(git rev-parse --show-toplevel)}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

repo_skills_dir="${ROOT_DIR}/.codex/skills"
repo_rules_dir="${ROOT_DIR}/.codex/rules"
codex_skills_dir="${CODEX_HOME}/skills"
codex_rules_dir="${CODEX_HOME}/rules"

mkdir -p "${codex_skills_dir}" "${codex_rules_dir}"

sync_skills() {
  local skill skill_name target link

  for skill in "${repo_skills_dir}"/*; do
    [[ -d "${skill}" ]] || continue
    [[ -f "${skill}/SKILL.md" ]] || continue
    skill_name="${skill##*/}"
    link="${codex_skills_dir}/${skill_name}"
    if [[ -e "${link}" && ! -L "${link}" ]]; then
      echo "Refusing to replace non-symlink skill path: ${link}" >&2
      exit 1
    fi
    ln -sfn "${skill}" "${link}"
  done

  for link in "${codex_skills_dir}"/*; do
    [[ -L "${link}" ]] || continue
    target="$(readlink "${link}")"
    [[ "${target}" == "${repo_skills_dir}/"* ]] || continue
    skill_name="${link##*/}"
    if [[ ! -f "${repo_skills_dir}/${skill_name}/SKILL.md" ]]; then
      rm "${link}"
    fi
  done
}

sync_rules() {
  local rule rule_name target link

  for rule in "${repo_rules_dir}"/*.rules; do
    [[ -f "${rule}" ]] || continue
    rule_name="${rule##*/}"
    link="${codex_rules_dir}/${rule_name}"
    if [[ -e "${link}" && ! -L "${link}" ]]; then
      echo "Refusing to replace non-symlink rule path: ${link}" >&2
      exit 1
    fi
    ln -sfn "${rule}" "${link}"
  done

  for link in "${codex_rules_dir}"/*; do
    [[ -L "${link}" ]] || continue
    target="$(readlink "${link}")"
    [[ "${target}" == "${repo_rules_dir}/"* ]] || continue
    rule_name="${link##*/}"
    if [[ ! -f "${repo_rules_dir}/${rule_name}" ]]; then
      rm "${link}"
    fi
  done
}

sync_skills
sync_rules
