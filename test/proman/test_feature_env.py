"""Tests for proman.feature_env — metadata-backed path resolution."""

from __future__ import annotations

from pathlib import Path

import proman.config as cfg
import pytest
import yaml
from proman.feature_env import (
    activation_profile_d_filename,
    clear_caches,
    resolved_env_vars,
)
from proman.metadata import MetadataLoader

_MINIMAL_SHARED = """\
_lifecycle_key_prefix: myowner-test--
_env_vars:
  _FEAT_ID:                        ${{ id }}$
  _FEAT_VERSION:                   ${{ version }}$
  _FEAT_NAME:                      ${{ name }}$
  _FEAT_SHARE_DIR_ROOT:            /usr/local/share/myowner/test/${{ id }}$
  _FEAT_SHARE_DIR_NONROOT:         ${HOME}/.local/share/myowner/test/${{ id }}$
  _FEAT_LIFECYCLE_DIR:             ${{ _env_vars._FEAT_SHARE_DIR_ROOT }}$/lifecycle-hooks
  _FEAT_PROFILE_D_FILE:            99-myowner--test--${{ id }}$.sh
  _FEAT_ACTIVATION_PROFILE_D_FILE: myowner-test-${{ id }}$-prefix-activation.sh
options:
  shared_opt:
    type: string
    default: hello
    description: Injected shared option.
"""

_MINIMAL_MAIN = """\
name: Test
name_slug: test
owner: myowner
owner_slug: myowner
namespace: myowner/test
repo_url: https://github.com/myowner/test
oci_base: ghcr.io/myowner/test
path:
  features: features
  library: lib
  shared_metadata: features/metadata.shared.yaml
  metadata_schema: features/metadata.schema.json
filename:
  feature_metadata: metadata.yaml
features:
  lifecycle_hook_keys:
    - onCreateCommand
"""


def _minimal_feature_metadata() -> dict:
    return {
        "version": "1.0.0",
        "name": "Test Feature",
        "description": "Short description.",
        "_long_description": "Longer description for docs.",
        "keywords": ["test"],
        "options": {},
    }


def _write_test_repo(tmp_path: Path) -> Path:
    proman_dir = tmp_path / ".config" / "proman"
    proman_dir.mkdir(parents=True)
    (proman_dir / "_main.yaml").write_text(_MINIMAL_MAIN, encoding="utf-8")

    features = tmp_path / "features"
    features.mkdir()
    (features / "metadata.shared.yaml").write_text(_MINIMAL_SHARED, encoding="utf-8")

    schema_src = (
        Path(__file__).resolve().parents[2] / "features" / "metadata.schema.json"
    )
    (features / "metadata.schema.json").write_text(
        schema_src.read_text(encoding="utf-8"),
        encoding="utf-8",
    )

    feat_dir = features / "install-foo"
    feat_dir.mkdir()
    (feat_dir / "metadata.yaml").write_text(
        yaml.dump(_minimal_feature_metadata()),
        encoding="utf-8",
    )
    return tmp_path


@pytest.fixture(autouse=True)
def _reset_caches() -> None:
    cfg._config = None
    clear_caches()


def test_resolved_env_vars_from_shared_metadata(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """All _env_vars keys are resolved to their final values."""
    _write_test_repo(tmp_path)
    monkeypatch.setattr("proman.config.git_repo_root", lambda: tmp_path)
    cfg._config = None
    clear_caches()

    env = resolved_env_vars("install-foo")
    assert env["_FEAT_ID"] == "install-foo"
    assert env["_FEAT_VERSION"] == "1.0.0"
    assert env["_FEAT_SHARE_DIR_ROOT"] == "/usr/local/share/myowner/test/install-foo"
    assert env["_FEAT_LIFECYCLE_DIR"] == (
        "/usr/local/share/myowner/test/install-foo/lifecycle-hooks"
    )
    assert env["_FEAT_PROFILE_D_FILE"] == "99-myowner--test--install-foo.sh"
    assert env["_FEAT_ACTIVATION_PROFILE_D_FILE"] == (
        "myowner-test-install-foo-prefix-activation.sh"
    )


def test_activation_profile_d_uses_config_slugs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _write_test_repo(tmp_path)
    monkeypatch.setattr("proman.config.git_repo_root", lambda: tmp_path)
    cfg._config = None
    clear_caches()
    assert activation_profile_d_filename("install-foo", "prefix") == (
        "myowner-test-install-foo-prefix-activation.sh"
    )


def test_setup_shim_matches_repo_config() -> None:
    """Sanity check: setup-shim _env_vars are fully resolved against the real repo."""
    env = resolved_env_vars("setup-shim")
    assert env["_FEAT_ID"] == "setup-shim"
    assert env["_FEAT_SHARE_DIR_ROOT"].endswith("/setup-shim")
    assert (
        env["_FEAT_LIFECYCLE_DIR"] == env["_FEAT_SHARE_DIR_ROOT"] + "/lifecycle-hooks"
    )
    assert env["_FEAT_PROFILE_D_FILE"].endswith(".sh")
    # Verify MetadataLoader and resolved_env_vars agree
    meta = MetadataLoader().load("setup-shim")["setup-shim"]["_env_vars"]
    assert env["_FEAT_SHARE_DIR_ROOT"] == meta["_FEAT_SHARE_DIR_ROOT"]
    assert env["_FEAT_PROFILE_D_FILE"] == meta["_FEAT_PROFILE_D_FILE"]
