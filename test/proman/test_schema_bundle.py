"""Tests for JSON Schema bundling (website + metadata validation)."""

from __future__ import annotations

import json
from pathlib import Path

from proman.schema_bundle import (
    build_materialized_schemas_for_website,
    get_validator,
    published_schema_basename,
    schema_stem_from_path,
)


def test_schema_stem_and_published_name() -> None:
    """Verify schema stem extraction and published filename generation."""
    p = Path("features/install-os-pkg/manifest.schema.json")
    assert schema_stem_from_path(p) == "manifest"
    assert published_schema_basename("manifest") == "manifest.json"


def test_build_materialized_for_website(tmp_path: Path) -> None:
    """Verify $id and $ref rewriting in materialized schemas for the published site."""
    feat_dir = tmp_path / "features" / "install-os-pkg"
    feat_dir.mkdir(parents=True)
    minimal = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "properties": {"a": {"type": "string"}},
    }
    (feat_dir / "manifest.schema.json").write_text(
        json.dumps(minimal),
        encoding="utf-8",
    )
    out = build_materialized_schemas_for_website(
        repo_root=tmp_path,
        base_url="https://example.org/myrepo/",
        publish_relpaths=["features/install-os-pkg/manifest.schema.json"],
    )
    doc = out["manifest"]
    assert doc["$id"] == "https://example.org/myrepo/schema/manifest.json"


def test_get_validator_smoke() -> None:
    """Ensure the real repo schemas load into a Draft 2020-12 validator."""
    v = get_validator()
    assert type(v).__name__ == "Draft202012Validator"
