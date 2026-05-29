"""Tests for lib/argparse-manifest.schema.json."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO_ROOT / "lib" / "argparse-manifest.schema.json"
FIXTURES_DIR = REPO_ROOT / "test" / "fixtures" / "argparse-manifests"


@pytest.fixture(scope="module")
def validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


@pytest.mark.parametrize(
    "fixture_name",
    [
        "minimal.json",
        "full-options.json",
    ],
)
def test_fixture_validates(validator: Draft202012Validator, fixture_name: str) -> None:
    data = json.loads((FIXTURES_DIR / fixture_name).read_text(encoding="utf-8"))
    validator.validate(data)


def test_allows_option_without_var_and_flag(
    validator: Draft202012Validator,
) -> None:
    data = {
        "schema_version": 1,
        "script": {"name": "x", "version": "1"},
        "input": {"mode": "cli_only"},
        "options": [
            {
                "name": "log_level",
                "type": "string",
                "default": "info",
                "description": "Log level.",
            }
        ],
    }
    validator.validate(data)


def test_allows_explicit_var_and_flag_overrides(
    validator: Draft202012Validator,
) -> None:
    data = {
        "schema_version": 1,
        "script": {"name": "x", "version": "1"},
        "input": {"mode": "cli_only"},
        "options": [
            {
                "name": "verbosity",
                "var": "LOG_LEVEL",
                "flag": "--log_level",
                "type": "string",
                "default": "info",
                "description": "Legacy env/flag names.",
            }
        ],
    }
    validator.validate(data)


def test_rejects_boolean_with_enum(validator: Draft202012Validator) -> None:
    invalid = {
        "schema_version": 1,
        "script": {"name": "x", "version": "1"},
        "input": {"mode": "cli_only"},
        "options": [
            {
                "name": "flag",
                "type": "boolean",
                "default": False,
                "enum": ["true"],
                "description": "bad",
            }
        ],
    }
    with pytest.raises(Exception):
        validator.validate(invalid)


def test_rejects_integer_with_uri(validator: Draft202012Validator) -> None:
    invalid = {
        "schema_version": 1,
        "script": {"name": "x", "version": "1"},
        "input": {"mode": "cli_only"},
        "options": [
            {
                "name": "count",
                "type": "integer",
                "default": 1,
                "uri": True,
                "description": "bad",
            }
        ],
    }
    with pytest.raises(Exception):
        validator.validate(invalid)


def test_rejects_listed_env_trigger_without_vars(
    validator: Draft202012Validator,
) -> None:
    invalid = {
        "schema_version": 1,
        "script": {"name": "x", "version": "1"},
        "input": {"mode": "env_exclusive_else_cli", "env_trigger": "listed"},
        "options": [],
    }
    with pytest.raises(Exception):
        validator.validate(invalid)


def test_allows_array_with_uri(validator: Draft202012Validator) -> None:
    data = {
        "schema_version": 1,
        "script": {"name": "x", "version": "1"},
        "input": {"mode": "cli_only"},
        "options": [
            {
                "name": "files",
                "type": "array",
                "default": "",
                "uri": True,
                "description": "ok",
            }
        ],
    }
    validator.validate(data)
