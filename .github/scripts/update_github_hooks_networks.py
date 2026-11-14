#!/usr/bin/env python3
"""
Update GitHub webhook source ranges in the flux-webhook route SecurityPolicy.

Fetches `hooks` from https://api.github.com/meta and rewrites
`spec.authorization.rules[0].principal.clientCIDRs` of the SecurityPolicy.
YAML formatting, top-level document marker, and comments are preserved.
"""

from __future__ import annotations

import logging
import os
import sys
from typing import Any

import requests
from ruamel.yaml import YAML

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

GITHUB_META_URL = "https://api.github.com/meta"
REQUEST_TIMEOUT = 30
RULE_NAME = "allow-github-hooks"

POLICY_FILE = os.getenv(
    "POLICY_FILE",
    "kubernetes/apps/flux-system/flux-instance/app/github/securitypolicy.yaml",
)


def create_yaml_handler() -> YAML:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)
    yaml.explicit_start = True
    yaml.width = 4096
    return yaml


def fetch_github_hooks() -> list[str]:
    logger.info("Fetching GitHub hooks ranges from %s", GITHUB_META_URL)
    response = requests.get(GITHUB_META_URL, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()
    hooks = response.json().get("hooks", [])
    if not hooks:
        raise ValueError("GitHub meta API returned no hooks ranges")
    logger.info("Fetched %d hooks ranges", len(hooks))
    return hooks


def update_policy(hooks: list[str]) -> tuple[set[str], set[str]]:
    yaml = create_yaml_handler()
    with open(POLICY_FILE, encoding="utf-8") as f:
        policy: Any = yaml.load(f)

    if policy.get("kind") != "SecurityPolicy":
        raise ValueError(f"Expected kind SecurityPolicy in {POLICY_FILE}")
    rules = policy["spec"]["authorization"]["rules"]
    rule = next((r for r in rules if r.get("name") == RULE_NAME), None)
    if rule is None:
        raise ValueError(f"No authorization rule named {RULE_NAME!r} in {POLICY_FILE}")

    principal = rule["principal"]
    current = set(principal["clientCIDRs"])
    new = set(hooks)
    principal["clientCIDRs"] = list(hooks)
    with open(POLICY_FILE, "w", encoding="utf-8") as f:
        yaml.dump(policy, f)
    return new - current, current - new


def main() -> int:
    try:
        added, removed = update_policy(fetch_github_hooks())
    except requests.RequestException as e:
        logger.error("Failed to fetch GitHub meta: %s", e)
        return 1
    except (ValueError, KeyError) as e:
        logger.error("Validation error: %s", e)
        return 1
    except FileNotFoundError as e:
        logger.error("File not found: %s", e)
        return 1
    print(f"=== {POLICY_FILE} ===")
    if added:
        print(f"Added: {', '.join(sorted(added))}")
    if removed:
        print(f"Removed: {', '.join(sorted(removed))}")
    if not (added or removed):
        print("No changes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
