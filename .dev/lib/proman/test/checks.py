"""Extract runner-only metadata from validated checks data."""

from __future__ import annotations

from typing import Any


def install_failure_patterns(
    checks_data: dict[str, Any],
    test_scripts: list[str],
) -> list[str]:
    """Return expected install stderr/stdout substrings from install_failure checks."""
    patterns: list[str] = []
    for ts in test_scripts:
        test_id = ts.removesuffix(".sh") if ts.endswith(".sh") else ts
        group = checks_data.get(test_id, {})
        patterns.extend(
            str(item["pattern"])
            for item in group.get("checks", [])
            if item.get("kind") == "install_failure"
        )
    return patterns
