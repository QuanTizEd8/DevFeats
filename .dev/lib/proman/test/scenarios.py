"""Load and expand devcontainer test scenarios from YAML files."""

from __future__ import annotations

import fnmatch
from pathlib import Path

import yaml

from proman.config import load as load_config


def load(path: Path | str) -> tuple[dict, dict]:
    """Load scenarios YAML and split off the defaults key."""
    with Path(path).open() as f:
        data = yaml.safe_load(f) or {}
    defaults = data.pop("defaults", {})
    return defaults, data


def shared_defaults() -> dict:
    """Load test/features/defaults.shared.yaml when present."""
    path = load_config().absolute_path("path.test_features_shared_defaults")
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    return data if isinstance(data, dict) else {}


def merge_defaults(scenario: dict, defaults: dict) -> dict:
    """Merge top-level defaults into a scenario dict."""
    merged = dict(scenario)
    for key in ("options", "args", "env_vars"):
        if key in defaults:
            base = dict(defaults[key])
            base.update(scenario.get(key, {}))
            merged[key] = base
    return merged


def merge_all_defaults(
    scenario: dict,
    feature_defaults: dict,
    shared: dict | None = None,
) -> dict:
    """Merge shared, feature-level, then scenario-level defaults/options."""
    merged: dict = {}
    for layer in [shared or {}, feature_defaults or {}, scenario]:
        for key, value in layer.items():
            if (
                key in merged
                and isinstance(merged[key], dict)
                and isinstance(value, dict)
            ):
                merged[key] = {**merged[key], **value}
            else:
                merged[key] = value
    return merged


def expand_envs(
    name: str,
    scenario: dict,
) -> list[tuple[str, str, dict]]:
    """Expand a scenario into one entry per (environment, test file)."""
    envs: list[str] = scenario.get("envs", [])
    tests: list[str] = scenario.get("tests", [])
    multi_test = len(tests) > 1

    entries = []
    test_iter: list = tests or [None]
    for env_name in envs:
        for test_file in test_iter:
            parts = [name, env_name]
            if multi_test:
                parts.append(Path(test_file).stem)
            sc = dict(scenario)
            if test_file is not None:
                sc["tests"] = [test_file]
            entries.append((".".join(parts), env_name, sc))

    return entries


def expand_test_files(
    tests_spec: dict | list | None,
    base_dir: Path | str,
) -> list[str]:
    """Expand a tests spec into a list of absolute file paths."""
    base = Path(base_dir)

    if tests_spec is None:
        includes = ["*.bats", "integration/*.bats"]
        excludes = []
    elif isinstance(tests_spec, dict):
        includes = tests_spec.get("includes", ["*.bats"])
        excludes = tests_spec.get("excludes", [])
    else:
        return []

    matched: set[Path] = set()
    for pattern in includes:
        matched.update(base.glob(pattern))

    result: list[str] = []
    for p in sorted(matched):
        rel = str(p.relative_to(base))
        excluded = any(fnmatch.fnmatch(rel, exc) for exc in excludes)
        if not excluded:
            result.append(str(p))

    return result
