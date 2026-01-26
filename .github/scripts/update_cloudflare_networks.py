#!/usr/bin/env python3
"""
Update Cloudflare IP ranges in Kubernetes manifests.

This script fetches the current Cloudflare IP ranges from their API and updates
the NetworkPolicy egress rules for cloudflare-tunnel.

The script preserves YAML formatting, comments, and structure while only updating
the relevant IP address sections.
"""

from __future__ import annotations

import logging
import os
import sys
from dataclasses import dataclass
from typing import Any

import requests
from ruamel.yaml import YAML

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(message)s",
)
logger = logging.getLogger(__name__)

# Constants
CLOUDFLARE_API_URL = "https://api.cloudflare.com/client/v4/ips"
REQUEST_TIMEOUT = 30

# File path from environment or default
NETWORKPOLICY_FILE = os.getenv(
    "NETWORKPOLICY_FILE",
    "kubernetes/apps/networking/cloudflare-tunnel/app/networkpolicy.yaml",
)


@dataclass
class UpdateResult:
    """Result of an update operation."""

    file_path: str
    added: set[str]
    removed: set[str]
    total: int

    @property
    def has_changes(self) -> bool:
        """Check if there were any changes."""
        return bool(self.added or self.removed)


def create_yaml_handler() -> YAML:
    """Create a configured YAML handler that preserves formatting."""
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)
    yaml.explicit_start = True  # Preserve "---" at start of manifest
    yaml.width = 4096  # Prevent line wrapping
    return yaml


def fetch_cloudflare_networks() -> list[str]:
    """
    Fetch current Cloudflare IP ranges from their API.

    Returns:
        List of CIDR strings (both IPv4 and IPv6).

    Raises:
        requests.RequestException: If the API request fails.
        ValueError: If the API response is invalid.
    """
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
    """
    Load a YAML file.

    Args:
        file_path: Path to the YAML file.

    Returns:
        Tuple of (parsed content, YAML handler).

    Raises:
        FileNotFoundError: If the file doesn't exist.
    """
    yaml = create_yaml_handler()
    with open(file_path, encoding="utf-8") as f:
        content = yaml.load(f)
    return content, yaml


def save_yaml_file(file_path: str, content: Any, yaml: YAML) -> None:
    """
    Save content to a YAML file.

    Args:
        file_path: Path to the YAML file.
        content: Content to save.
        yaml: YAML handler to use.
    """
    with open(file_path, "w", encoding="utf-8") as f:
        yaml.dump(content, f)


def update_networkpolicy(cloudflare_cidrs: list[str]) -> UpdateResult:
    """
    Update NetworkPolicy with Cloudflare IP ranges.

    This updates the egress rule that contains ipBlock entries for Cloudflare IPs.

    Args:
        cloudflare_cidrs: List of Cloudflare CIDR strings.

    Returns:
        UpdateResult with details of changes made.

    Raises:
        ValueError: If the NetworkPolicy structure is invalid.
    """
    logger.info("Updating NetworkPolicy: %s", NETWORKPOLICY_FILE)

    policy, yaml = load_yaml_file(NETWORKPOLICY_FILE)

    # Find the egress rule with ipBlock entries (Cloudflare IPs)
    egress_rules = policy.get("spec", {}).get("egress", [])
    cloudflare_egress_rule = None

    for rule in egress_rules:
        to_entries = rule.get("to", [])
        if to_entries and any(entry.get("ipBlock") for entry in to_entries):
            cloudflare_egress_rule = rule
            break

    if cloudflare_egress_rule is None:
        raise ValueError(
            "Could not find Cloudflare egress rule (ipBlock entries) in NetworkPolicy"
        )

    # Extract current CIDRs
    current_cidrs = {
        entry["ipBlock"]["cidr"]
        for entry in cloudflare_egress_rule["to"]
        if entry.get("ipBlock")
    }
    new_cidrs = set(cloudflare_cidrs)

    # Calculate changes
    added = new_cidrs - current_cidrs
    removed = current_cidrs - new_cidrs

    # Update the rule with new CIDRs
    cloudflare_egress_rule["to"] = [
        {"ipBlock": {"cidr": cidr}} for cidr in cloudflare_cidrs
    ]

    save_yaml_file(NETWORKPOLICY_FILE, policy, yaml)

    return UpdateResult(
        file_path=NETWORKPOLICY_FILE,
        added=added,
        removed=removed,
        total=len(cloudflare_cidrs),
    )


def print_result(result: UpdateResult) -> None:
    """Print update result in a formatted way."""
    print(f"\n=== {result.file_path} ===")
    print(f"Total CIDRs: {result.total}")

    if result.added:
        print(f"Added: {', '.join(sorted(result.added))}")
    if result.removed:
        print(f"Removed: {', '.join(sorted(result.removed))}")
    if not result.has_changes:
        print("No changes")


def main() -> int:
    """
    Main entry point.

    Returns:
        Exit code (0 for success, 1 for error).
    """
    try:
        # Fetch Cloudflare IPs
        cloudflare_cidrs = fetch_cloudflare_networks()

        # Update NetworkPolicy
        result = update_networkpolicy(cloudflare_cidrs)

        # Print result
        print_result(result)

        # Summary
        print(f"\n=== Summary ===")
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
