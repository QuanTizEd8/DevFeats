"""Tests for proman.metadata — the central feature metadata module."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from proman.const import export_profile_d, feat_share_dir
from proman.metadata import (
    _feature_vars,
    _substitute_vars,
    augment_metadata,
    load_all,
    load_derived_options,
    load_one,
    normalize_lifecycle_command_keys,
    read_metadata,
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


# ── load_one ──────────────────────────────────────────────────────────


def test_load_one_sets_id_and_oci_ref(
    features_dir: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """load_one sets ``id`` and ``_oci_ref`` on the returned dict."""
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: _FAKE_OWNER_REPO)
    candidates = sorted(features_dir.glob("*/metadata.yaml"))
    assert candidates, "No real features found — check features/ directory."
    feat_id = candidates[0].parent.name
    result = load_one(feat_id, features_dir)
    assert result is not None, f"load_one failed for '{feat_id}'"
    assert result["id"] == feat_id
    assert result["_oci_ref"] == f"ghcr.io/testowner/testrepo/{feat_id}"


def test_load_one_missing_feature(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Returns None when the feature directory has no metadata.yaml."""
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: _FAKE_OWNER_REPO)
    features = tmp_path / "features"
    (features / "ghost").mkdir(parents=True)
    (features / "shared-options.yaml").write_text("{}", encoding="utf-8")
    result = load_one("ghost", features)
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
    assert vars_["_FEAT_SHARE_DIR"] == feat_share_dir(
        "install-foo", "myowner", "myrepo"
    )
    assert vars_["_EXPORT_PROFILE_D"] == export_profile_d(
        "install-foo", "myowner", "myrepo"
    )
    assert vars_["PROJECT_OWNER"] == "myowner"
    assert vars_["PROJECT_NAME"] == "myrepo"
    assert vars_["PROJECT_NAMESPACE"] == "myowner/myrepo"
    assert vars_["PROJECT_SLUG"] == "myowner-myrepo"


def test_substitute_vars_string() -> None:
    """@@VAR@@ tokens in plain strings are replaced."""
    vars_ = {"_FEAT_SHARE_DIR": "/usr/local/share/o/r/feat"}
    result = _substitute_vars("@@_FEAT_SHARE_DIR@@/entrypoint.sh", vars_)
    assert result == "/usr/local/share/o/r/feat/entrypoint.sh"


def test_substitute_vars_nested_dict_and_list() -> None:
    """Substitution recurses into dict keys, values, and list items."""
    vars_ = {"_FEAT_SHARE_DIR": "/share/o/r/f"}
    obj = {
        "@@_FEAT_SHARE_DIR@@": "key-was-expanded",
        "entrypoint": "@@_FEAT_SHARE_DIR@@/run.sh",
        "env": {"PATH": "@@_FEAT_SHARE_DIR@@/bin:$PATH"},
        "cmds": ["sh @@_FEAT_SHARE_DIR@@/a.sh", "echo done"],
        "num": 42,
    }
    result = _substitute_vars(obj, vars_)
    assert isinstance(result, dict)
    assert result["/share/o/r/f"] == "key-was-expanded"
    assert "@@_FEAT_SHARE_DIR@@" not in result
    assert result["entrypoint"] == "/share/o/r/f/run.sh"
    assert result["env"]["PATH"] == "/share/o/r/f/bin:$PATH"
    assert result["cmds"][0] == "sh /share/o/r/f/a.sh"
    assert result["cmds"][1] == "echo done"
    assert result["num"] == 42  # non-string scalar unchanged


def test_normalize_lifecycle_short_keys() -> None:
    """Short YAML keys are prefixed with owner-repo--feature--."""
    md: dict = {
        "onCreateCommand": {"run": {"command": "true", "description": "noop"}},
    }
    normalize_lifecycle_command_keys(md, "install-bar", "myowner", "myrepo")
    assert list(md["onCreateCommand"].keys()) == ["myowner-myrepo--install-bar--run"]


def test_normalize_lifecycle_strips_legacy_repo_slug() -> None:
    """Keys that already embed --<feature-id>-- use PROJECT_SLUG instead."""
    md: dict = {
        "onCreateCommand": {
            "devfeats--install-bar--task": {"command": "true", "description": "noop"},
        },
    }
    normalize_lifecycle_command_keys(md, "install-bar", "quantized8", "devfeats")
    assert list(md["onCreateCommand"].keys()) == [
        "quantized8-devfeats--install-bar--task",
    ]


def test_normalize_lifecycle_idempotent() -> None:
    """Keys that already use the canonical prefix are unchanged."""
    key = "quantized8-devfeats--install-bar--task"
    md: dict = {"onCreateCommand": {key: {"command": "true", "description": "noop"}}}
    normalize_lifecycle_command_keys(md, "install-bar", "quantized8", "devfeats")
    assert list(md["onCreateCommand"].keys()) == [key]


def test_normalize_lifecycle_non_string_key_unchanged() -> None:
    """Non-string mapping keys are passed through (YAML edge case)."""
    md: dict = {"onCreateCommand": {123: {"command": "true", "description": "noop"}}}  # type: ignore[dict-item]
    normalize_lifecycle_command_keys(md, "install-bar", "o", "r")
    assert md["onCreateCommand"][123]["command"] == "true"  # type: ignore[index]


def test_normalize_lifecycle_wrong_block_type() -> None:
    """Non-dict lifecycle values are left as-is."""
    md: dict = {"onCreateCommand": "not-a-mapping"}
    normalize_lifecycle_command_keys(md, "install-bar", "o", "r")
    assert md["onCreateCommand"] == "not-a-mapping"


def test_load_one_substitutes_feature_vars(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """@@_FEAT_SHARE_DIR@@, @@_EXPORT_PROFILE_D@@, and @@PROJECT_*@@ are expanded."""
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: ("myowner", "myrepo"))
    features = tmp_path / "features"
    feat_id = "install-bar"
    feat_dir = features / feat_id
    feat_dir.mkdir(parents=True)
    raw = {
        "version": "1.0.0",
        "name": "Bar",
        "description": "Test @@PROJECT_SLUG@@.",
        "keywords": [],
        "options": {},
        "entrypoint": "@@_FEAT_SHARE_DIR@@/entrypoint.sh ${containerWorkspaceFolder}",
        "containerEnv": {"PATH": "@@_FEAT_SHARE_DIR@@/bin:$PATH"},
        "documentationURL": "https://github.com/@@PROJECT_NAMESPACE@@",
        "onCreateCommand": {
            "run": {"command": "sh @@_FEAT_SHARE_DIR@@/on-create.sh || true"},
        },
    }
    (feat_dir / "metadata.yaml").write_text(yaml.dump(raw), encoding="utf-8")
    (features / "shared-options.yaml").write_text("{}", encoding="utf-8")
    result = load_one(feat_id, features)
    assert result is not None
    expected_share = "/usr/local/share/myowner/myrepo/install-bar"
    assert result["entrypoint"] == (
        f"{expected_share}/entrypoint.sh ${{containerWorkspaceFolder}}"
    )
    assert result["containerEnv"]["PATH"] == f"{expected_share}/bin:$PATH"
    expected_lc_key = "myowner-myrepo--install-bar--run"
    assert list(result["onCreateCommand"].keys()) == [expected_lc_key]
    assert result["onCreateCommand"][expected_lc_key]["command"] == (
        f"sh {expected_share}/on-create.sh || true"
    )
    assert result["description"] == "Test myowner-myrepo."
    assert result["documentationURL"] == "https://github.com/myowner/myrepo"
