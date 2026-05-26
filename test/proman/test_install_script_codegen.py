"""Tests for install.bash codegen — bash escape sequences in Python templates."""

from __future__ import annotations

from pathlib import Path

import pytest

from proman.sync.install_script import (
    InstallScriptGenerator,
    _SPLIT_PRINTF_PERCENT_S_RE,
    _uri_chmod_mode,
    validate_generated_install_script,
)

_REPO_ROOT = Path(__file__).resolve().parents[2]
_INSTALL_CONDA_ENV = _REPO_ROOT / "src" / "install-conda-env" / "install.bash"


def test_bash_embed_templates_have_no_split_printf_percent_s() -> None:
    """Module-level _ARGPARSE_* / _TMPL_* strings must not use bare \\n inside quotes."""
    from proman.sync import install_script as mod

    for name, value in vars(mod).items():
        if not (
            isinstance(value, str)
            and (name.startswith("_ARGPARSE_") or name.startswith("_TMPL_"))
        ):
            continue
        assert not _SPLIT_PRINTF_PERCENT_S_RE.search(value), name


def test_validate_generated_install_script_rejects_split_printf() -> None:
    bad = "mapfile -t X < <(printf '%s\n    ' \"${X}\")"
    with pytest.raises(ValueError, match="literal line break"):
        validate_generated_install_script(bad)


def test_validate_generated_install_script_accepts_correct_printf() -> None:
    good = "mapfile -t X < <(printf '%s\\n' \"${X}\")"
    validate_generated_install_script(good)


def test_uri_chmod_mode_from_metadata() -> None:
    assert _uri_chmod_mode({"chmod": "600"}) == "600"
    assert _uri_chmod_mode({"chmod": "+x"}) == "+x"
    assert _uri_chmod_mode({"chmod_exec": True}) == "+x"
    assert _uri_chmod_mode(True) is None


def test_uri_chmod_mode_rejects_invalid() -> None:
    with pytest.raises(ValueError, match="chmod"):
        _uri_chmod_mode({"chmod": "rm -rf /"})


def test_uri_resolution_without_installer_dir_uses_matdir_fallback() -> None:
    """Features with installer_dir: false must not reference unset INSTALLER_DIR."""
    gen = InstallScriptGenerator()
    block = gen._generate_argparse_uri_resolution(
        {
            "env_files": {"type": "array", "_uri": True},
            "post_env_script": {"type": "string", "_uri": {"chmod": "+x"}},
        }
    )
    assert "argparse__resolve_uri_options" in block
    assert "_DF_URI_SPECS" in block
    assert "${INSTALLER_DIR}/uri/" not in block
    assert "env_files\tENV_FILES\tarray\t" in block
    assert "post_env_script\tPOST_ENV_SCRIPT\tstring\t+x" in block


@pytest.mark.skipif(
    not _INSTALL_CONDA_ENV.is_file(),
    reason="run 'pixi run proman-sync' to populate src/install-conda-env/install.bash",
)
def test_synced_install_conda_env_passes_escape_validation() -> None:
    """Regression: db42a06b broke printf '%s\\n' into a literal line break in output."""
    script = _INSTALL_CONDA_ENV.read_text(encoding="utf-8")
    validate_generated_install_script(script)
    # URI resolution must run before path validations.
    assert "# Resolve URI-capable option values" in script
    assert "argparse__resolve_uri_options" in script
    assert "_DF_URI_SPECS" in script
    assert "\t+x" in script
    assert "argparse__split_lines ENV_DIRS" in script
    assert "argparse__validate_path_array ENV_DIRS" in script
    assert "argparse__validate_path_array ENV_FILES" in script
    assert not _SPLIT_PRINTF_PERCENT_S_RE.search(script)
