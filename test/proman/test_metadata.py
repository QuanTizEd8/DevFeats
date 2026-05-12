"""Tests for proman.metadata — the central feature metadata module."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from proman.const import export_profile_d, feat_share_dir
from proman.metadata import (
    augment_metadata,
    load_all,
    load_and_augment,
    load_derived_options,
    read_metadata,
    _feature_vars,
    _substitute_vars,
)

_FAKE_OWNER_REPO = ("testowner", "testrepo")

# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture
def repo_root() -> Path:
    """Return the repository root path."""
    return Path(__file__).resolve().parents[2]


@pytest.fixture
def features_dir(repo_root: Path) -> Path:
    """Return the path to the features/ directory."""
    return repo_root / "features"


@pytest.fixture
def minimal_feature(tmp_path: Path) -> tuple[Path, str]:
    """Create a minimal valid features/ directory with one feature."""
    features = tmp_path / "features"
    feat_id = "test-feature"
    feat_dir = features / feat_id
    feat_dir.mkdir(parents=True)

    metadata = {
        "version": "1.0.0",
        "name": "Test Feature",
        "description": "A minimal test feature.",
        "_long_description": "Longer text.",
        "keywords": ["test"],
        "options": {},
    }
    (feat_dir / "metadata.yaml").write_text(
        yaml.dump(metadata),
        encoding="utf-8",
    )
    # Empty shared-options.yaml
    (features / "shared-options.yaml").write_text("{}", encoding="utf-8")
    return features, feat_id


# ── read_metadata ─────────────────────────────────────────────────────────────


def test_read_metadata_missing_file(tmp_path: Path) -> None:
    """Returns 0 (skip sentinel) when metadata.yaml is absent."""
    features = tmp_path / "features"
    features.mkdir()
    (features / "no-meta").mkdir()
    result = read_metadata("no-meta", features)
    assert result == 0


def test_read_metadata_invalid_yaml(tmp_path: Path) -> None:
    """Returns 1 (error sentinel) when YAML is malformed."""
    features = tmp_path / "features"
    feat_dir = features / "bad-yaml"
    feat_dir.mkdir(parents=True)
    (feat_dir / "metadata.yaml").write_text(
        "key: [\n  invalid yaml",
        encoding="utf-8",
    )
    result = read_metadata("bad-yaml", features)
    assert result == 1


def test_read_metadata_not_a_mapping(tmp_path: Path) -> None:
    """Returns 1 when YAML parses to something other than a dict."""
    features = tmp_path / "features"
    feat_dir = features / "bad-type"
    feat_dir.mkdir(parents=True)
    (feat_dir / "metadata.yaml").write_text("- item1\n- item2\n", encoding="utf-8")
    result = read_metadata("bad-type", features)
    assert result == 1


def test_read_metadata_valid(minimal_feature: tuple[Path, str]) -> None:
    """Returns the parsed dict for a valid metadata.yaml."""
    features, feat_id = minimal_feature
    result = read_metadata(feat_id, features)
    assert isinstance(result, dict)
    assert result["name"] == "Test Feature"


# ── augment_metadata ──────────────────────────────────────────────────────────


def test_augment_metadata_adds_shared_options(tmp_path: Path) -> None:
    """Shared options are merged into the feature's options dict."""
    features = tmp_path / "features"
    features.mkdir()
    shared = {"shared_opt": {"type": "string", "default": "hello", "description": "x"}}
    (features / "shared-options.yaml").write_text(
        yaml.dump(shared),
        encoding="utf-8",
    )
    metadata: dict = {"options": {}}
    derived = load_derived_options(features)
    ok = augment_metadata("feat", metadata, derived)
    assert ok is True
    assert "shared_opt" in metadata["options"]


def test_augment_metadata_rejects_override(tmp_path: Path) -> None:
    """Returns False when a feature manually defines a derived option."""
    features = tmp_path / "features"
    features.mkdir()
    shared = {"locked_opt": {"type": "string", "default": "", "description": "x"}}
    (features / "shared-options.yaml").write_text(
        yaml.dump(shared),
        encoding="utf-8",
    )
    metadata: dict = {"options": {"locked_opt": {"type": "string", "default": "oops"}}}
    derived = load_derived_options(features)
    ok = augment_metadata("feat", metadata, derived)
    assert ok is False


# ── load_and_augment ──────────────────────────────────────────────────────────


def test_load_and_augment_sets_id_and_oci_ref(
    features_dir: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """load_and_augment sets ``id`` and ``_oci_ref`` on the returned dict."""
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: _FAKE_OWNER_REPO)
    candidates = sorted(features_dir.glob("*/metadata.yaml"))
    assert candidates, "No real features found — check features/ directory."
    feat_id = candidates[0].parent.name
    result = load_and_augment(feat_id, features_dir)
    assert result is not None, f"load_and_augment failed for '{feat_id}'"
    assert result["id"] == feat_id
    assert result["_oci_ref"] == f"ghcr.io/testowner/testrepo/{feat_id}"


def test_load_and_augment_missing_feature(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Returns None when the feature directory has no metadata.yaml."""
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: _FAKE_OWNER_REPO)
    features = tmp_path / "features"
    (features / "ghost").mkdir(parents=True)
    (features / "shared-options.yaml").write_text("{}", encoding="utf-8")
    result = load_and_augment("ghost", features)
    assert result is None


# ── load_all ─────────────────────────────────────────────────────────────────


def test_load_all_returns_all_valid_features(
    features_dir: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """load_all returns a non-empty dict keyed by feature IDs."""
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: _FAKE_OWNER_REPO)
    all_meta = load_all(features_dir)
    assert len(all_meta) > 0
    for feat_id, meta in all_meta.items():
        assert meta["id"] == feat_id
        assert "_oci_ref" in meta


def test_load_all_empty_features_dir(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """load_all returns an empty dict when no metadata.yaml files exist."""
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: _FAKE_OWNER_REPO)
    features = tmp_path / "features"
    features.mkdir()
    (features / "shared-options.yaml").write_text("{}", encoding="utf-8")
    result = load_all(features)
    assert result == {}


# ── _feature_vars / _substitute_vars ─────────────────────────────────────────


def test_feature_vars_delegates_to_const() -> None:
    """_feature_vars returns values produced by the canonical const formulas."""
    vars_ = _feature_vars("install-foo", "myowner", "myrepo")
    assert vars_["_FEAT_SHARE_DIR"] == feat_share_dir("install-foo", "myowner", "myrepo")
    assert vars_["_EXPORT_PROFILE_D"] == export_profile_d("install-foo", "myowner", "myrepo")


def test_substitute_vars_string() -> None:
    """@@VAR@@ tokens in plain strings are replaced."""
    vars_ = {"_FEAT_SHARE_DIR": "/usr/local/share/o/r/feat"}
    result = _substitute_vars("@@_FEAT_SHARE_DIR@@/entrypoint.sh", vars_)
    assert result == "/usr/local/share/o/r/feat/entrypoint.sh"


def test_substitute_vars_nested_dict_and_list() -> None:
    """Substitution recurses into dict values and list items; keys are untouched."""
    vars_ = {"_FEAT_SHARE_DIR": "/share/o/r/f"}
    obj = {
        "@@_FEAT_SHARE_DIR@@": "key-is-not-touched",
        "entrypoint": "@@_FEAT_SHARE_DIR@@/run.sh",
        "env": {"PATH": "@@_FEAT_SHARE_DIR@@/bin:$PATH"},
        "cmds": ["sh @@_FEAT_SHARE_DIR@@/a.sh", "echo done"],
        "num": 42,
    }
    result = _substitute_vars(obj, vars_)
    assert isinstance(result, dict)
    assert "@@_FEAT_SHARE_DIR@@" in result  # key unchanged
    assert result["entrypoint"] == "/share/o/r/f/run.sh"
    assert result["env"]["PATH"] == "/share/o/r/f/bin:$PATH"
    assert result["cmds"][0] == "sh /share/o/r/f/a.sh"
    assert result["cmds"][1] == "echo done"
    assert result["num"] == 42  # non-string scalar unchanged


def test_load_and_augment_substitutes_feature_vars(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """@@_FEAT_SHARE_DIR@@ and @@_EXPORT_PROFILE_D@@ are expanded in metadata values."""
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: ("myowner", "myrepo"))
    features = tmp_path / "features"
    feat_id = "install-bar"
    feat_dir = features / feat_id
    feat_dir.mkdir(parents=True)
    raw = {
        "version": "1.0.0",
        "name": "Bar",
        "description": "Test.",
        "keywords": [],
        "options": {},
        "entrypoint": "@@_FEAT_SHARE_DIR@@/entrypoint.sh ${containerWorkspaceFolder}",
        "containerEnv": {"PATH": "@@_FEAT_SHARE_DIR@@/bin:$PATH"},
        "onCreateCommand": {
            "run": {"command": "sh @@_FEAT_SHARE_DIR@@/on-create.sh || true"},
        },
    }
    (feat_dir / "metadata.yaml").write_text(yaml.dump(raw), encoding="utf-8")
    (features / "shared-options.yaml").write_text("{}", encoding="utf-8")
    result = load_and_augment(feat_id, features)
    assert result is not None
    expected_share = "/usr/local/share/myowner/myrepo/install-bar"
    assert result["entrypoint"] == (
        f"{expected_share}/entrypoint.sh ${{containerWorkspaceFolder}}"
    )
    assert result["containerEnv"]["PATH"] == f"{expected_share}/bin:$PATH"
    assert result["onCreateCommand"]["run"]["command"] == (
        f"sh {expected_share}/on-create.sh || true"
    )
