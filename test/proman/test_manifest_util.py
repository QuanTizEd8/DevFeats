"""Tests for ospkg manifest option generation utilities."""

from __future__ import annotations

from proman.manifest_util import generate_dep_trigger_specs, serialize_manifest


def test_serialize_manifest_empty() -> None:
    """Empty or missing manifest content serializes to an empty string."""
    assert serialize_manifest({}) == ""
    assert serialize_manifest(None) == ""


def test_serialize_manifest_yaml() -> None:
    """Non-empty manifest dicts serialize to YAML with a trailing newline."""
    out = serialize_manifest({"packages": ["git"]})
    assert "packages:" in out
    assert "- git" in out
    assert out.endswith("\n")


def test_serialize_manifest_single_line_has_trailing_newline() -> None:
    """Even compact YAML must end with newline for inline manifest detection."""
    out = serialize_manifest({"packages": []})
    assert out == "packages: []\n"


def test_serialize_manifest_preserves_single_quotes_in_yaml() -> None:
    """YAML content with single quotes is serialized verbatim."""
    out = serialize_manifest({"packages": [{"name": "it's-fine"}]})
    assert "it's-fine" in out
    assert out.endswith("\n")


def test_generate_dep_trigger_specs_bundle() -> None:
    """Boolean option bundles emit a three-column trigger spec line."""
    metadata = {
        "_dependencies": {
            "run": {"option-archive_tools": {"packages": ["zip"]}},
        },
        "options": {"archive_tools": {"type": "boolean"}},
    }
    lines = generate_dep_trigger_specs(metadata)
    assert lines == [
        "archive_tools\tOSPKG_MANIFEST_OPTION_ARCHIVE_TOOLS\tARCHIVE_TOOLS",
    ]


def test_generate_dep_trigger_specs_skips_non_boolean() -> None:
    """Non-boolean options do not produce trigger specs."""
    metadata = {
        "_dependencies": {
            "run": {"option-jre": {"packages": ["openjdk"]}},
        },
        "options": {},
    }
    assert generate_dep_trigger_specs(metadata) == []


def test_generate_dep_trigger_specs_ignores_build_option_groups() -> None:
    """Option-bound manifests under build are ignored (run-only)."""
    metadata = {
        "_dependencies": {
            "run": {"option-sudo_access": {"packages": ["sudo"]}},
            "build": {"option-sudo_access": {"packages": ["sudo"]}},
        },
        "options": {"sudo_access": {"type": "boolean"}},
    }
    lines = generate_dep_trigger_specs(metadata)
    assert len(lines) == 1
    assert lines[0].startswith("sudo_access\t")
