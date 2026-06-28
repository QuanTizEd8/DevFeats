"""Unit tests for feature test run naming (keys, logs, artifacts)."""

from __future__ import annotations

from proman.test.names import (
    FeatureTestRun,
    artifact_name,
    bind_mount_container_log_path,
    host_log_basename,
    host_log_path,
    mode_artifact_suffix,
    sanitize_segment,
)
from proman.test.scenarios import expand_envs


def test_expand_envs_always_includes_env() -> None:
    """Single-env scenarios get env suffix in run key."""
    entries = expand_envs(
        "default",
        {"envs": ["ubuntu-24.04"], "tests": ["default.sh"]},
    )
    assert entries == [
        (
            "default.ubuntu-24.04",
            "ubuntu-24.04",
            {"envs": ["ubuntu-24.04"], "tests": ["default.sh"]},
        ),
    ]


def test_expand_envs_multi_env_unchanged() -> None:
    """Multi-env keys keep scenario.env format."""
    entries = expand_envs(
        "package_default",
        {
            "envs": ["debian-12+bash", "ubuntu-24.04"],
            "tests": ["package_default.sh"],
        },
    )
    assert [e[0] for e in entries] == [
        "package_default.debian-12+bash",
        "package_default.ubuntu-24.04",
    ]


def test_mode_artifact_suffix_maps_standalone_to_linux() -> None:
    """CLI standalone mode uses linux in artifact/log suffix."""
    assert mode_artifact_suffix("standalone") == "linux"
    assert mode_artifact_suffix("devcontainer") == "devcontainer"
    assert mode_artifact_suffix("macos") == "macos"


def test_host_log_basename_includes_feature_and_mode() -> None:
    """Host log basename encodes feature, env-qualified key, and mode."""
    run = FeatureTestRun("install-direnv", "default.ubuntu-24.04", "devcontainer")
    assert host_log_basename(run) == (
        "install-direnv--default.ubuntu-24.04--devcontainer.log"
    )


def test_host_log_paths_unique_across_features_and_modes() -> None:
    """Different features and modes must not share the same host log path."""
    key = "default.ubuntu-24.04"
    a = host_log_path(FeatureTestRun("install-direnv", key, "devcontainer"))
    b = host_log_path(FeatureTestRun("install-git", key, "devcontainer"))
    c = host_log_path(FeatureTestRun("install-direnv", key, "standalone"))
    assert a != b
    assert a != c
    assert b != c


def test_artifact_name_pattern() -> None:
    """Artifact names use single-dash segments (not host log double-dash)."""
    run = FeatureTestRun("install-direnv", "default.ubuntu-24.04", "standalone")
    assert artifact_name(run) == (
        "feat-log-install-direnv-default.ubuntu-24.04-linux"
    )


def test_bind_mount_container_log_path_matches_host_basename() -> None:
    """Bind-mount destination reuses host log basename; slashes sanitized in key."""
    run = FeatureTestRun("install-git", "log_file/ubuntu-24.04", "devcontainer")
    assert bind_mount_container_log_path(run) == (
        "/log-out/install-git--log_file_ubuntu-24.04--devcontainer.log"
    )
    assert sanitize_segment("log_file/ubuntu-24.04") == "log_file_ubuntu-24.04"
