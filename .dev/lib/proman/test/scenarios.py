from __future__ import annotations

import fnmatch
from pathlib import Path
from typing import Any

import yaml


def load(path: Path | str) -> tuple[dict, dict]:
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    defaults = data.pop("defaults", {})
    return defaults, data


def merge_defaults(scenario: dict, defaults: dict) -> dict:
    merged = dict(scenario)
    for key in ("options", "args", "env_vars"):
        if key in defaults:
            base = dict(defaults[key])
            base.update(scenario.get(key, {}))
            merged[key] = base
    return merged


def expand_envs(
    name: str, scenario: dict
) -> list[tuple[str, str, dict]]:
    envs: list[str] = scenario.get("envs", [])
    if len(envs) == 1:
        return [(name, envs[0], scenario)]
    return [(f"{name}.{env_name}", env_name, scenario) for env_name in envs]


def expand_test_files(
    tests_spec: Any, base_dir: Path | str
) -> list[str]:
    base = Path(base_dir)

    if tests_spec is None:
        includes = ["*.bats"]
        excludes = ["integration/**"]
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
