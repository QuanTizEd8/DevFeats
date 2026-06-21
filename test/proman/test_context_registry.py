"""Tests for context key registry schema."""

from __future__ import annotations

import json
from pathlib import Path

import yaml

FIXTURES = Path(__file__).resolve().parent / "fixtures"
SCHEMA_PATH = Path(__file__).resolve().parents[2] / "features" / "metadata.schema.json"


def _load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text())


def _registry_fixture() -> list[dict]:
    return yaml.safe_load((FIXTURES / "context_registry_keys.yaml").read_text())


def test_context_registry_def_exists() -> None:
    schema = _load_schema()
    assert "ContextKeyRegistry" in schema["$defs"]


def test_when_spec_uses_qualified_keys() -> None:
    schema = _load_schema()
    when_obj = schema["$defs"]["WhenConditionObject"]
    pattern = when_obj["propertyNames"]["pattern"]
    assert "os|plat|feat" in pattern


def test_when_spec_rejects_legacy_flat_keys() -> None:
    schema = _load_schema()
    when_obj = schema["$defs"]["WhenConditionObject"]
    pattern = when_obj["propertyNames"]["pattern"]
    for legacy in ("arch", "pm", "id", "semver_lte", "kernel"):
        assert not __import__("re").match(pattern, legacy)


def test_registry_fixture_entries_match_schema_shape() -> None:
    schema = _load_schema()
    item_schema = schema["$defs"]["ContextKeyRegistry"]["items"]
    required = set(item_schema["required"])
    for entry in _registry_fixture():
        assert required <= set(entry)
        assert entry["namespace"] in item_schema["properties"]["namespace"]["enum"]
        assert entry["key"]
        if "matchMode" in entry:
            assert entry["matchMode"] in item_schema["properties"]["matchMode"]["enum"]


def test_os_id_like_uses_token_list_match_mode() -> None:
    entries = _registry_fixture()
    id_like = next(
        e for e in entries if e["namespace"] == "os" and e["key"] == "id_like"
    )
    assert id_like["matchMode"] == "token_list"


def test_registry_includes_core_plat_and_feat_keys() -> None:
    keys = {(e["namespace"], e["key"]) for e in _registry_fixture()}
    for ns, key in (
        ("plat", "pm"),
        ("plat", "machine_release"),
        ("plat", "deb_arch"),
        ("feat", "version"),
        ("feat", "method"),
        ("feat", "prefix"),
    ):
        assert (ns, key) in keys
