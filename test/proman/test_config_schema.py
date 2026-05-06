"""Tests for proman.cicd.config_schema.json — JSON Schema validation."""

import json
from pathlib import Path

import jsonschema
import pytest

import proman.cicd.detect as CD

SCHEMA = json.loads((Path(CD.__file__).parent / "config_schema.json").read_text())


def _make_valid_config() -> dict:
    return CD.build_config(
        build_image=True,
        image_name="ghcr.io/org/repo-devcontainer",
        image_tag="latest",
        ci_image="ghcr.io/org/repo-devcontainer:latest",
        run_lint=True,
        run_validate=True,
        run_unit=True,
        run_features=True,
        features=["install-git"],
        run_macos=True,
        macos_matrix=[{"feature": "install-git", "runner": "macos-latest"}],
        run_python=True,
        run_docs=True,
        is_release=False,
        features_to_release=[],
        unit_env_matrix=[{"name": "ubuntu-24.04", "env": "ubuntu-latest"}],
        unit_macos_matrix=[{"runner": "macos-latest"}],
    )


def test_valid_config_passes():
    jsonschema.validate(_make_valid_config(), SCHEMA)


def test_missing_top_level_key_fails():
    cfg = _make_valid_config()
    del cfg["ci_build"]
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(cfg, SCHEMA)


def test_string_where_bool_required_fails():
    cfg = _make_valid_config()
    cfg["ci_lint"]["shell"]["enabled"] = "true"
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(cfg, SCHEMA)


def test_extra_key_fails_due_to_additional_properties():
    cfg = _make_valid_config()
    cfg["ci_build"]["unknown_key"] = "x"
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(cfg, SCHEMA)


def test_cm_devcontainer_build_matrix_items_typed():
    cfg = _make_valid_config()
    cfg["cm_devcontainer"]["build_matrix"] = [{"runner": 42, "platform": "x", "platform_tag": "y"}]
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(cfg, SCHEMA)


def test_cd_features_list_typed():
    cfg = _make_valid_config()
    cfg["cd"]["features"] = [{"feature": "x", "version": 1, "tag": "x/1"}]
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(cfg, SCHEMA)


def test_ci_test_lib_linux_matrix_typed():
    cfg = _make_valid_config()
    cfg["ci_test_lib"]["linux_matrix"] = [{"name": "x"}]  # missing "env"
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(cfg, SCHEMA)
