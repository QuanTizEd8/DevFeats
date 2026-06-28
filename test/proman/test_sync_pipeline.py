"""Tests for proman.sync.pipeline helpers."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from proman.sync.pipeline import (
    _gather_metadata_files,
    _generate_feature_devcontainer_json,
    _merge_feature_files,
)


def _minimal_metadata() -> dict:
    return {
        "id": "install-ripgrep-all",
        "version": "0.1.0",
        "_oci_ref": "ghcr.io/quantized8/devfeats/install-ripgrep-all",
        "_devcontainer": {
            "features": {
                "../.src/install-ripgrep": {},
            },
        },
    }


def test_generate_feature_devcontainer_json_does_not_mutate_metadata() -> None:
    """Test and try generation must not share or mutate _devcontainer.features."""
    metadata = _minimal_metadata()
    original_features = dict(metadata["_devcontainer"]["features"])

    _generate_feature_devcontainer_json(metadata, local=True)
    assert metadata["_devcontainer"]["features"] == original_features

    try_json = json.loads(_generate_feature_devcontainer_json(metadata, local=False))
    assert try_json["features"] == {
        "../.src/install-ripgrep": {},
        "ghcr.io/quantized8/devfeats/install-ripgrep-all:0.1.0": {},
    }


def test_generate_feature_devcontainer_json_test_uses_local_src() -> None:
    """Test containers install the feature under test from local src/."""
    metadata = _minimal_metadata()

    test_json = json.loads(_generate_feature_devcontainer_json(metadata, local=True))
    assert test_json["features"] == {
        "../.src/install-ripgrep": {},
        "../.src/install-ripgrep-all": {},
    }


def test_gather_metadata_files_single_entry() -> None:
    """``_gather_metadata_files`` maps a single entry under ``files/``."""
    metadata = {
        "_files": [{"path": "foo.sh", "content": "#!/bin/sh\necho hi\n"}],
    }
    result = _gather_metadata_files(metadata, feature_id="test-feature")
    assert result == {Path("files/foo.sh"): "#!/bin/sh\necho hi\n"}


def test_gather_metadata_files_nested_path() -> None:
    """``_gather_metadata_files`` preserves nested relative paths."""
    metadata = {
        "_files": [{"path": "skel/.zshrc", "content": "export FOO=1\n"}],
    }
    result = _gather_metadata_files(metadata, feature_id="test-feature")
    assert result == {Path("files/skel/.zshrc"): "export FOO=1\n"}


@pytest.mark.parametrize(
    ("path", "match"),
    [
        ("", "empty path"),
        ("/abs.sh", "absolute"),
        ("../escape.sh", "must not contain"),
        ("foo/../bar.sh", "must not contain"),
    ],
)
def test_gather_metadata_files_rejects_invalid_paths(path: str, match: str) -> None:
    """``_gather_metadata_files`` rejects empty, absolute, and traversal paths."""
    metadata = {"_files": [{"path": path, "content": "x"}]}
    with pytest.raises(ValueError, match=match):
        _gather_metadata_files(metadata, feature_id="test-feature")


def test_gather_metadata_files_rejects_duplicate_paths() -> None:
    """``_gather_metadata_files`` rejects duplicate ``path`` values in ``_files``."""
    metadata = {
        "_files": [
            {"path": "foo.sh", "content": "a"},
            {"path": "foo.sh", "content": "b"},
        ],
    }
    with pytest.raises(ValueError, match="duplicate _files path"):
        _gather_metadata_files(metadata, feature_id="test-feature")


def test_merge_feature_files_no_collision() -> None:
    """``_merge_feature_files`` combines disjoint disk and metadata file maps."""
    disk = {Path("files/disk.sh"): "from disk\n"}
    meta = {Path("files/meta.sh"): "from metadata\n"}
    merged = _merge_feature_files(disk, meta, feature_id="test-feature")
    assert merged == {
        Path("files/disk.sh"): "from disk\n",
        Path("files/meta.sh"): "from metadata\n",
    }


def test_merge_feature_files_raises_on_collision() -> None:
    """``_merge_feature_files`` raises when disk and metadata share a path."""
    disk = {Path("files/shared.sh"): "from disk\n"}
    meta = {Path("files/shared.sh"): "from metadata\n"}
    with pytest.raises(ValueError, match="collide with"):
        _merge_feature_files(disk, meta, feature_id="test-feature")
