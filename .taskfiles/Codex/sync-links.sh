#!/bin/zsh

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
  local -a repo_skill_names

  repo_skill_names=()
  for skill in "${repo_skills_dir}"/*; do
    [[ -d "${skill}" ]] || continue
    [[ -f "${skill}/SKILL.md" ]] || continue
    skill_name="${skill:t}"
    repo_skill_names+=("${skill_name}")
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
    skill_name="${link:t}"
    if (( ${repo_skill_names[(Ie)${skill_name}]} == 0 )); then
      rm "${link}"
    fi
  done
}

sync_rules() {
  local rule rule_name target link
  local -a repo_rule_names

  repo_rule_names=()
  for rule in "${repo_rules_dir}"/*.rules(N); do
    [[ -f "${rule}" ]] || continue
    rule_name="${rule:t}"
    repo_rule_names+=("${rule_name}")
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
    rule_name="${link:t}"
    if (( ${repo_rule_names[(Ie)${rule_name}]} == 0 )); then
      rm "${link}"
    fi
  done
}

sync_skills
sync_rules
