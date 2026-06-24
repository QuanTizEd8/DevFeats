"""Tests for proman.sync.pipeline helpers."""

from __future__ import annotations

import json

from proman.sync.pipeline import _generate_feature_devcontainer_json


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
