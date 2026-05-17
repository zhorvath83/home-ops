#!/usr/bin/env python3
"""
Update Cloudflare IP ranges in the cluster-scoped CiliumCIDRGroup manifest.

Fetches the current Cloudflare IP ranges from the public API and rewrites the
`spec.externalCIDRs` list of the CiliumCIDRGroup that the cloudflare-tunnel
CiliumNetworkPolicy references via `toCIDRSet.cidrGroupRef`.

YAML formatting, top-level document marker, and comments are preserved.
"""

from __future__ import annotations

import logging
import os
import sys
from dataclasses import dataclass
from typing import Any

import requests
from ruamel.yaml import YAML

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

CLOUDFLARE_API_URL = "https://api.cloudflare.com/client/v4/ips"
REQUEST_TIMEOUT = 30

CIDRGROUP_FILE = os.getenv(
    "CIDRGROUP_FILE",
    "kubernetes/apps/networking/cloudflare-tunnel/app/ciliumcidrgroup.yaml",
)


@dataclass
class UpdateResult:
    file_path: str
    added: set[str]
    removed: set[str]
    total: int

    @property
    def has_changes(self) -> bool:
        return bool(self.added or self.removed)


def create_yaml_handler() -> YAML:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)
    yaml.explicit_start = True
    yaml.width = 4096
    return yaml


def fetch_cloudflare_networks() -> list[str]:
    logger.info("Fetching Cloudflare IP ranges from API...")
    response = requests.get(CLOUDFLARE_API_URL, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()
    data = response.json()

    if not data.get("success"):
        errors = data.get("errors", [])
        raise ValueError(f"Cloudflare API returned error: {errors}")

    result = data.get("result", {})
    ipv4_cidrs = result.get("ipv4_cidrs", [])
    ipv6_cidrs = result.get("ipv6_cidrs", [])

    if not ipv4_cidrs and not ipv6_cidrs:
        raise ValueError("Cloudflare API returned no IP ranges")

    all_cidrs = ipv4_cidrs + ipv6_cidrs
    logger.info(
        "Fetched %d IPv4 and %d IPv6 ranges (%d total)",
        len(ipv4_cidrs),
        len(ipv6_cidrs),
        len(all_cidrs),
    )
    return all_cidrs


def load_yaml_file(file_path: str) -> tuple[Any, YAML]:
    yaml = create_yaml_handler()
    with open(file_path, encoding="utf-8") as f:
        content = yaml.load(f)
    return content, yaml


def save_yaml_file(file_path: str, content: Any, yaml: YAML) -> None:
    with open(file_path, "w", encoding="utf-8") as f:
        yaml.dump(content, f)


def update_cidrgroup(cloudflare_cidrs: list[str]) -> UpdateResult:
    logger.info("Updating CiliumCIDRGroup: %s", CIDRGROUP_FILE)
    group, yaml = load_yaml_file(CIDRGROUP_FILE)

    kind = group.get("kind")
    if kind != "CiliumCIDRGroup":
        raise ValueError(
            f"Expected kind CiliumCIDRGroup in {CIDRGROUP_FILE}, got {kind!r}"
        )

    spec = group.get("spec")
    if spec is None or "externalCIDRs" not in spec:
        raise ValueError(
            f"CiliumCIDRGroup in {CIDRGROUP_FILE} has no spec.externalCIDRs"
        )

    current_cidrs = set(spec["externalCIDRs"])
    new_cidrs = set(cloudflare_cidrs)
    added = new_cidrs - current_cidrs
    removed = current_cidrs - new_cidrs

    spec["externalCIDRs"] = list(cloudflare_cidrs)
    save_yaml_file(CIDRGROUP_FILE, group, yaml)

    return UpdateResult(
        file_path=CIDRGROUP_FILE,
        added=added,
        removed=removed,
        total=len(cloudflare_cidrs),
    )


def print_result(result: UpdateResult) -> None:
    print(f"\n=== {result.file_path} ===")
    print(f"Total CIDRs: {result.total}")
    if result.added:
        print(f"Added: {', '.join(sorted(result.added))}")
    if result.removed:
        print(f"Removed: {', '.join(sorted(result.removed))}")
    if not result.has_changes:
        print("No changes")


def main() -> int:
    try:
        cloudflare_cidrs = fetch_cloudflare_networks()
        result = update_cidrgroup(cloudflare_cidrs)
        print_result(result)
        print("\n=== Summary ===")
        print(f"Files updated: {1 if result.has_changes else 0}/1")
        return 0
    except requests.RequestException as e:
        logger.error("Failed to fetch Cloudflare networks: %s", e)
        return 1
    except ValueError as e:
        logger.error("Validation error: %s", e)
        return 1
    except FileNotFoundError as e:
        logger.error("File not found: %s", e)
        return 1
    except Exception as e:
        logger.exception("Unexpected error: %s", e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
