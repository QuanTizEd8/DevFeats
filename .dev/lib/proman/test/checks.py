"""Load checks.yaml and extract runner-only metadata."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

import yaml

if TYPE_CHECKING:
    from pathlib import Path


def load_checks(checks_path: Path) -> dict[str, Any]:
    """Load a feature checks.yaml file."""
    with checks_path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def install_failure_patterns(
    checks_data: dict[str, Any],
    test_scripts: list[str],
) -> list[str]:
    """Return expected install stderr/stdout substrings from install_failure checks."""
    patterns: list[str] = []
    for ts in test_scripts:
        test_id = ts.removesuffix(".sh") if ts.endswith(".sh") else ts
        group = checks_data.get(test_id, {})
        for item in group.get("checks", []):
            if item.get("kind") == "install_failure":
                patterns.append(str(item["pattern"]))
    return patterns
