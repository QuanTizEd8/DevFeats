"""Tests for proman.test.environments."""

from __future__ import annotations

from proman.test.environments import docker_buildkit_env


def test_docker_buildkit_env_enables_plain_progress() -> None:
    """Test Docker builds use BuildKit with plain progress."""
    env = docker_buildkit_env({"PATH": "/bin"})
    assert env["PATH"] == "/bin"
    assert env["DOCKER_BUILDKIT"] == "1"
    assert env["BUILDKIT_PROGRESS"] == "plain"
