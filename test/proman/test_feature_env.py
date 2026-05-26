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
    share_dir_root,
    shell_profile_d_filename,
)
from proman.metadata import MetadataLoader

_MINIMAL_SHARED = """\
_lifecycle_key_prefix: myowner-test--
_env_vars:
  share_dir_root: /usr/local/share/myowner/test/${{ id }}$
  share_dir_nonroot: ${HOME}/.local/share/myowner/test/${{ id }}$
  lifecycle_script_dir: /usr/local/share/myowner/test/${{ id }}$/lifecycle-hooks
  shell_profile_d_filename: 99-myowner--test--${{ id }}$.sh
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
    yield
    cfg._config = None
    clear_caches()


def test_resolved_env_vars_from_shared_metadata(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """share_dir_root and shell_profile_d_filename match filled _env_vars."""
    _write_test_repo(tmp_path)
    monkeypatch.setattr("proman.config.git_repo_root", lambda: tmp_path)
    cfg._config = None
    clear_caches()

    env = resolved_env_vars("install-foo")
    assert env["share_dir_root"] == "/usr/local/share/myowner/test/install-foo"
    assert env["shell_profile_d_filename"] == "99-myowner--test--install-foo.sh"
    assert share_dir_root("install-foo") == env["share_dir_root"]
    assert shell_profile_d_filename("install-foo") == env["shell_profile_d_filename"]


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
    """Sanity check against the real devfeats tree (no path drift)."""
    meta = MetadataLoader().load("setup-shim")["setup-shim"]["_env_vars"]
    assert share_dir_root("setup-shim") == meta["share_dir_root"]
    assert shell_profile_d_filename("setup-shim") == meta["shell_profile_d_filename"]
