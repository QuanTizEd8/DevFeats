"""Tests for ospkg manifest option generation utilities."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from proman.manifest_util import (
    escape_devcontainer_default,
    generate_dep_trigger_specs,
    serialize_manifest,
)
from proman.sync.install_script import _shell_val
from proman.sync.pipeline import _generate_metadata_json


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


def test_serialize_manifest_preserves_dollar_signs() -> None:
    """Canonical manifest YAML keeps shell $ unescaped for install.bash defaults."""
    out = serialize_manifest(
        {
            "apt": {
                "scripts": 'if [[ -n "${_libdir}" ]]; then\n  true\nfi\n',
                "repos": ["baseurl=https://example/rpm/$releasever/$basearch"],
            },
        },
    )
    assert "${_libdir}" in out
    assert "$releasever" in out
    assert r"\$" not in out


def test_serialize_manifest_preserves_double_quotes() -> None:
    """Canonical manifest YAML keeps embedded double quotes unescaped."""
    out = serialize_manifest({"apt": {"scripts": 'echo "hello"\n'}})
    assert 'echo "hello"' in out
    assert r"\"" not in out


def test_escape_devcontainer_default_dollar_and_quote() -> None:
    """Devcontainer defaults escape $ and " but not already-escaped sequences."""
    raw = 'scripts: |\n  _libdir="$(find /usr/lib)"\n'
    escaped = escape_devcontainer_default(raw)
    assert r"_libdir=\"\$(find /usr/lib)\"" in escaped
    assert escape_devcontainer_default(r"\${PATH}") == r"\${PATH}"


def test_escape_devcontainer_default_env_file_roundtrip(tmp_path: Path) -> None:
    """Escaped defaults survive devcontainer-features.env sourcing."""
    raw = serialize_manifest(
        {
            "apt": {
                "scripts": (
                    "_libdir=\"$(find /usr/lib -type d -name '*-linux-*'"
                    ' 2>/dev/null | head -1)"\n'
                ),
            },
        },
    )
    escaped = escape_devcontainer_default(raw)
    env_file = tmp_path / "devcontainer-features.env"
    env_file.write_text(f'TEST_MANIFEST="{escaped}"\n', encoding="utf-8")
    bash_script = f"""
set -eu
# shellcheck source=/dev/null
. "{env_file}"
printf '%s' "$TEST_MANIFEST"
"""
    proc = subprocess.run(
        ["bash", "-c", bash_script],
        check=False,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout == raw


def test_install_bash_default_roundtrip_for_manifest() -> None:
    """Standalone install.bash defaults use clean YAML without devcontainer escapes."""
    raw = serialize_manifest({"apt": {"scripts": 'x="${_libdir}"\n'}})
    rhs = _shell_val(raw, "string")
    bash_script = f"""
set -eu
TEST_MANIFEST={rhs}
printf '%s' "$TEST_MANIFEST"
"""
    proc = subprocess.run(
        ["bash", "-c", bash_script],
        check=False,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout == raw


def test_generate_metadata_json_escapes_all_string_defaults() -> None:
    """devcontainer-feature.json escapes string defaults; metadata stays canonical."""
    manifest = serialize_manifest({"apt": {"scripts": 'x="${_libdir}"\n'}})
    metadata = {
        "options": {
            "ospkg_manifest_base_run": {
                "type": "string",
                "default": manifest,
            },
            "runtime_path": {
                "type": "string",
                "default": "${PATH}",
            },
            "zsh_cache_dir": {
                "type": "string",
                "default": "${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh",
            },
            "if_exists": {
                "type": "string",
                "default": "skip",
            },
        },
    }
    out = json.loads(
        _generate_metadata_json(metadata)[Path("devcontainer-feature.json")],
    )
    assert r"\${_libdir}" in out["options"]["ospkg_manifest_base_run"]["default"]
    assert out["options"]["runtime_path"]["default"] == r"\${PATH}"
    assert (
        out["options"]["zsh_cache_dir"]["default"]
        == r"\${XDG_CACHE_HOME:-\$HOME/.cache}/oh-my-zsh"
    )
    assert out["options"]["if_exists"]["default"] == "skip"


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
