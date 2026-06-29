"""Tests for checks.yaml helpers."""

from __future__ import annotations

import pytest
from proman.test.checks import install_failure_patterns


def test_install_failure_patterns_collects_patterns() -> None:
    """Collect pattern substrings from install_failure checks in a test group."""
    checks = {
        "invalid_method": {
            "checks": [
                {
                    "kind": "install_failure",
                    "title": "invalid method rejected",
                    "pattern": "Invalid value for 'method'",
                },
            ],
        },
    }
    assert install_failure_patterns(checks, ["invalid_method"]) == [
        "Invalid value for 'method'",
    ]


def test_install_failure_patterns_requires_pattern() -> None:
    """install_failure checks without pattern raise KeyError."""
    checks = {
        "fail_fast_true": {
            "checks": [
                {"kind": "install_failure", "title": "feature exits non-zero"},
            ],
        },
    }
    with pytest.raises(KeyError, match="pattern"):
        install_failure_patterns(checks, ["fail_fast_true"])
