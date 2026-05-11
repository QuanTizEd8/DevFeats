"""Tests for proman.metadata — the central feature metadata module."""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest
import yaml

from proman.metadata import (
    augment_metadata,
    load_all,
    load_and_augment,
    load_derived_options,
    read_metadata,
)


# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture
def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


@pytest.fixture
def features_dir(repo_root: Path) -> Path:
    return repo_root / "features"


@pytest.fixture
def minimal_feature(tmp_path: Path) -> tuple[Path, str]:
    """A minimal valid features/ directory with one feature."""
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
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: ("testowner", "testrepo"))
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
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: ("testowner", "testrepo"))
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
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: ("testowner", "testrepo"))
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
    monkeypatch.setattr("proman.metadata.git_owner_repo", lambda: ("testowner", "testrepo"))
    features = tmp_path / "features"
    features.mkdir()
    (features / "shared-options.yaml").write_text("{}", encoding="utf-8")
    result = load_all(features)
    assert result == {}
