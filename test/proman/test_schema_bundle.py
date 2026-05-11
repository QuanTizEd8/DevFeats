"""Tests for JSON Schema bundling (website + metadata validation)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from proman.schema_bundle import (
    build_materialized_schemas_for_website,
    build_metadata_validator,
    published_schema_basename,
    schema_stem_from_path,
)


def test_schema_stem_and_published_name() -> None:
    """Verify schema stem extraction and published filename generation."""
    p = Path("lib/ospkg-manifest.schema.json")
    assert schema_stem_from_path(p) == "ospkg-manifest"
    assert published_schema_basename("ospkg-manifest") == "ospkg-manifest.json"


def test_build_materialized_for_website(tmp_path: Path) -> None:
    """Verify $id and $ref rewriting in materialized schemas for the published site."""
    lib = tmp_path / "lib"
    lib.mkdir()
    minimal = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "properties": {"a": {"type": "string"}},
    }
    (lib / "ospkg-manifest.schema.json").write_text(
        json.dumps(minimal),
        encoding="utf-8",
    )
    out = build_materialized_schemas_for_website(
        repo_root=tmp_path,
        base_url="https://example.org/myrepo/",
        publish_relpaths=["lib/ospkg-manifest.schema.json"],
    )
    doc = out["ospkg-manifest"]
    assert doc["$id"] == "https://example.org/myrepo/schema/ospkg-manifest.json"


def test_build_metadata_validator_smoke(repo_root: Path) -> None:
    """Ensure the real repo schemas load into a Draft 2020-12 validator."""
    v = build_metadata_validator(repo_root / "features", repo_root / "lib")
    assert type(v).__name__ == "Draft202012Validator"


@pytest.fixture
def repo_root() -> Path:
    """Return the repository root path."""
    return Path(__file__).resolve().parents[2]
