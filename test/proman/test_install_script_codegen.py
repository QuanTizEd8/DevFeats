"""Tests for install.bash codegen — bash escape sequences in Python templates."""

from __future__ import annotations

from pathlib import Path

import pytest
from proman.manifest_util import serialize_manifest
from proman.sync import install_script as install_script_mod
from proman.sync.install_script import (
    _SPLIT_PRINTF_PERCENT_S_RE,
    InstallScriptGenerator,
    _shell_val,
    _uri_chmod_mode,
    validate_generated_install_script,
)

_REPO_ROOT = Path(__file__).resolve().parents[2]
_INSTALL_CONDA_ENV = _REPO_ROOT / "src" / "install-conda-env" / "install.bash"


def test_shell_val_plain_string() -> None:
    """Plain strings are single-quoted."""
    assert _shell_val("master", "string") == "'master'"
    assert _shell_val("disabled", "string") == "'disabled'"
    assert _shell_val("/usr/local/bin", "string") == "'/usr/local/bin'"


def test_shell_val_empty() -> None:
    """Empty string and None both produce single empty quotes."""
    assert _shell_val("", "string") == "''"
    assert _shell_val(None, "string") == "''"


def test_shell_val_boolean() -> None:
    """Boolean type produces single-quoted true/false."""
    assert _shell_val(True, "boolean") == "'true'"  # noqa: FBT003
    assert _shell_val(False, "boolean") == "'false'"  # noqa: FBT003


def test_shell_val_shell_expression_single_quoted() -> None:
    """Shell expression defaults are single-quoted to prevent bash expansion."""
    # SHORT_HOST and ZSH_VERSION are zsh-specific — unbound in bash with set -u.
    assert _shell_val("${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh", "string") == (
        "'${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh'"
    )
    assert (
        _shell_val("${ZSH_CACHE_DIR}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}", "string")
        == "'${ZSH_CACHE_DIR}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}'"
    )


def test_shell_val_shell_expression_embedded_single_quote() -> None:
    r"""Embedded single quotes are escaped via the '\\'' idiom."""
    assert _shell_val("${HOME}/it's-here", "string") == "'${HOME}/it'\\''s-here'"


def test_bash_embed_templates_have_no_split_printf_percent_s() -> None:
    r"""Template constants must not use bare ``\n`` inside single-quoted printf."""
    for name, value in vars(install_script_mod).items():
        if not (isinstance(value, str) and (name.startswith(("_ARGPARSE_", "_TMPL_")))):
            continue
        assert not _SPLIT_PRINTF_PERCENT_S_RE.search(value), name


def test_validate_generated_install_script_rejects_split_printf() -> None:
    """Validation rejects split printf forms that break escaped newlines."""
    bad = "mapfile -t X < <(printf '%s\n    ' \"${X}\")"
    with pytest.raises(ValueError, match="literal line break"):
        validate_generated_install_script(bad)


def test_validate_generated_install_script_accepts_correct_printf() -> None:
    r"""Validation accepts correctly escaped ``printf '%s\\n'`` forms."""
    good = "mapfile -t X < <(printf '%s\\n' \"${X}\")"
    validate_generated_install_script(good)


def test_uri_chmod_mode_from_metadata() -> None:
    """_uri chmod metadata values are normalized to chmod mode strings."""
    assert _uri_chmod_mode({"chmod": "600"}) == "600"
    assert _uri_chmod_mode({"chmod": "+x"}) == "+x"
    assert _uri_chmod_mode({"chmod_exec": True}) == "+x"
    truthy_uri_flag = True
    assert _uri_chmod_mode(truthy_uri_flag) is None


def test_uri_chmod_mode_rejects_invalid() -> None:
    """Invalid chmod metadata should raise ValueError."""
    with pytest.raises(ValueError, match="chmod"):
        _uri_chmod_mode({"chmod": "rm -rf /"})


def test_shell_val_multiline_uses_ansi_c() -> None:
    """Multiline string defaults use ANSI-C quoting."""
    assert _shell_val("packages:\n- jq", "string") == "$'packages:\\n- jq'"


def test_generate_argparse_multiline_default_in_cli_inits() -> None:
    """CLI init path embeds multiline defaults with ANSI-C quoting."""
    gen = InstallScriptGenerator()
    block = gen._generate_argparse(
        {"manifest": {"type": "string", "default": "packages:\n- jq"}},
    )
    assert "$'packages:\\n- jq'" in block["cli_inits"]
    assert "argparse__default MANIFEST $'packages:\\n- jq'" in block["defaults"]


def test_dep_trigger_specs_emitted() -> None:
    """Generated install.bash includes option-bound dependency trigger specs."""
    gen = InstallScriptGenerator()
    metadata = {
        "_dependencies": {"run": {"option-archive_tools": {"packages": ["zip"]}}},
        "options": {"archive_tools": {"type": "boolean"}},
    }
    block = gen._generate_dep_trigger_specs(metadata)
    assert "_FEAT_DEP_TRIGGER_SPECS=$'" in block
    assert "archive_tools\tOSPKG_MANIFEST_OPTION_ARCHIVE_TOOLS\tARCHIVE_TOOLS" in block
    assert "install_run" not in block


def test_ospkg_manifest_default_with_single_quote_uses_ansi_c_quoting() -> None:
    """Single quotes in manifest YAML defaults survive install.bash codegen."""
    gen = InstallScriptGenerator()
    manifest_default = serialize_manifest({"packages": [{"name": "it's-fine"}]})
    block = gen._generate_argparse(
        {
            "ospkg_manifest_option_demo": {
                "type": "string",
                "default": manifest_default,
            },
        },
    )
    assert manifest_default.endswith("\n")
    assert "$'packages:\\n" in block["defaults"]
    assert "it\\'s-fine" in block["defaults"]


def test_ospkg_manifest_defaults_are_canonical_in_install_bash_codegen() -> None:
    """Manifest defaults stay canonical in install.bash (no legacy escapes)."""
    gen = InstallScriptGenerator()
    manifest_default = serialize_manifest(
        {"apt": {"scripts": 'test "${_libdir}"\n'}},
    )
    block = gen._generate_argparse(
        {
            "ospkg_manifest_base_run": {
                "type": "string",
                "default": manifest_default,
            },
        },
    )
    assert "normalize_escapes" not in block
    assert "${_libdir}" in manifest_default
    assert r"\${_libdir}" not in block["defaults"]


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
    r"""Regression: generated output must keep ``printf '%s\\n'`` escaped."""
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
