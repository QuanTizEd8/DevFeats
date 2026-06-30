"""Tests for proman.test.environments and test/environments.yaml policy."""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

from proman.test.environments import docker_buildkit_env

REPO_ROOT = Path(__file__).resolve().parents[2]
ENVS_PATH = REPO_ROOT / "test" / "environments.yaml"

# Base keys must not embed version numbers; pins live in image: fields only.
VERSION_IN_BASE_KEY = re.compile(
    r"^(?:ubuntu|debian|alpine|fedora|rockylinux|opensuse-leap|macos)-\d"
)


def _load_environments() -> dict:
    return yaml.safe_load(ENVS_PATH.read_text(encoding="utf-8"))


def _base_key(env_key: str) -> str:
    return env_key.split("+", 1)[0]


def test_docker_buildkit_env_enables_plain_progress() -> None:
    """Test Docker builds use BuildKit with plain progress."""
    env = docker_buildkit_env({"PATH": "/bin"})
    assert env["PATH"] == "/bin"
    assert env["DOCKER_BUILDKIT"] == "1"
    assert env["BUILDKIT_PROGRESS"] == "plain"


def test_environment_base_keys_have_no_version_numbers() -> None:
    """Semantic env keys must not embed distro version numbers."""
    envs = _load_environments()
    offenders = [key for key in envs if VERSION_IN_BASE_KEY.match(_base_key(key))]
    assert not offenders, f"version-baked base keys: {offenders}"


def _collect_env_refs_from_scenarios() -> set[str]:
    refs: set[str] = set()
    for path in (REPO_ROOT / "test").rglob("scenarios.yaml"):
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        for spec in data.values():
            if not isinstance(spec, dict):
                continue
            envs = spec.get("envs")
            if not envs:
                continue
            if isinstance(envs, str):
                refs.add(envs)
            else:
                refs.update(envs)
    lib = yaml.safe_load((REPO_ROOT / "test/lib/scenarios.yaml").read_text()) or {}
    for spec in lib.values():
        if isinstance(spec, dict) and "env" in spec:
            refs.add(spec["env"])
    return refs


def test_scenario_env_refs_exist_in_environments_yaml() -> None:
    """Every env key referenced in scenarios must exist in environments.yaml."""
    envs = _load_environments()
    refs = _collect_env_refs_from_scenarios()
    missing = sorted(ref for ref in refs if ref not in envs)
    assert not missing, f"unknown env keys: {missing}"
