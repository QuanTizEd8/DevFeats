"""Unit tests for devcontainer / standalone feature log capture helpers."""

# ruff: noqa: S108 — paths mirror real feature-test log_file options under /tmp/

from __future__ import annotations

import json
from typing import TYPE_CHECKING

from proman.test.feature_logs import (
    DEVFEATS_LOG_BIND_DIR_ENV,
    append_bind_mount_copy_to_test_script,
    bind_mount_container_log_path,
    container_log_path,
    default_container_log_path,
    devcontainer_log_bind_mount_spec,
    patch_devcontainer_scenario_logging,
    uses_bind_mount_log,
)

if TYPE_CHECKING:
    from pathlib import Path


def test_default_container_log_path_matches_shared_defaults() -> None:
    """Shared default log_file matches defaults.shared.yaml."""
    assert default_container_log_path() == "/tmp/devfeats-feature.log"


def test_uses_bind_mount_log() -> None:
    """Detect default vs dedicated log_file scenario options."""
    assert uses_bind_mount_log({}) is True
    assert uses_bind_mount_log({"log_file": "/tmp/devfeats-feature.log"}) is True
    assert uses_bind_mount_log({"log_file": "/tmp/git.log"}) is False


def test_bind_mount_container_log_path_sanitizes_key() -> None:
    """Map scenario keys with slashes to safe log file names."""
    assert bind_mount_container_log_path("log_file/ubuntu-24.04") == (
        "/log-out/log_file_ubuntu-24.04.log"
    )


def test_devcontainer_log_bind_mount_spec_uses_env_var() -> None:
    """Bind mount spec references DEVFEATS_LOG_BIND_DIR localEnv."""
    assert DEVFEATS_LOG_BIND_DIR_ENV in devcontainer_log_bind_mount_spec()
    assert "target=/log-out" in devcontainer_log_bind_mount_spec()


def test_patch_devcontainer_scenario_logging_default_log_file(
    tmp_path: Path,
) -> None:
    """Default scenarios get mount and log_file under /log-out."""
    path = tmp_path / "scenarios.json"
    path.write_text(
        json.dumps(
            {
                "default_install": {
                    "build": {"dockerfile": "default_install.Dockerfile"},
                    "features": {"install-git": {"version": "stable"}},
                },
            },
        )
        + "\n",
        encoding="utf-8",
    )
    effective = patch_devcontainer_scenario_logging(
        path,
        feature="install-git",
        scenario_key="default_install",
        options={},
    )
    assert effective == "/log-out/default_install.log"
    data = json.loads(path.read_text(encoding="utf-8"))
    sc = data["default_install"]
    assert devcontainer_log_bind_mount_spec() in sc["mounts"]
    assert sc["features"]["install-git"]["log_file"] == "/log-out/default_install.log"


def test_patch_devcontainer_scenario_logging_custom_log_file(
    tmp_path: Path,
) -> None:
    """Dedicated log_file scenarios keep in-container path but still get mount."""
    path = tmp_path / "scenarios.json"
    path.write_text(
        json.dumps(
            {
                "log_file": {
                    "build": {"dockerfile": "log_file.Dockerfile"},
                    "features": {"install-git": {"log_file": "/tmp/git.log"}},
                },
            },
        )
        + "\n",
        encoding="utf-8",
    )
    effective = patch_devcontainer_scenario_logging(
        path,
        feature="install-git",
        scenario_key="log_file",
        options={"log_file": "/tmp/git.log"},
    )
    assert effective == "/tmp/git.log"
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["log_file"]["features"]["install-git"]["log_file"] == "/tmp/git.log"
    assert devcontainer_log_bind_mount_spec() in data["log_file"]["mounts"]


def test_append_bind_mount_copy_to_test_script(tmp_path: Path) -> None:
    """Inject explicit log path copy before standalone reportResults line."""
    script = tmp_path / "log_file.sh"
    script.write_text(
        "#!/bin/bash\n"
        "set -e\n"
        "source dev-container-features-test-lib\n"
        "check foo true\n"
        "reportResults\n",
        encoding="utf-8",
    )
    append_bind_mount_copy_to_test_script(
        script,
        "log_file",
        log_path="/tmp/conda-env.log",
    )
    text = script.read_text(encoding="utf-8")
    assert '/tmp/conda-env.log' in text
    assert "/log-out/log_file.log" in text
    assert text.index("/log-out/") < text.rindex("reportResults")


def test_append_bind_mount_copy_skips_heredoc_report_results_comment(
    tmp_path: Path,
) -> None:
    """Do not replace reportResults inside embedded assert.sh heredoc text."""
    lib_line = "#   reportResults                                   — summary\n"
    script = tmp_path / "log_file.sh"
    script.write_text(
        "#!/bin/bash\n"
        f"cat > /tmp/lib <<'END'\n{lib_line}END\n"
        "reportResults\n",
        encoding="utf-8",
    )
    append_bind_mount_copy_to_test_script(
        script,
        "log_file",
        log_path="/tmp/conda-env.log",
    )
    text = script.read_text(encoding="utf-8")
    assert text.count("reportResults") == 2
    assert lib_line in text


def test_container_log_path_respects_options() -> None:
    """Resolve log_file from options or shared defaults."""
    assert container_log_path({"log_file": "/tmp/git.log"}) == "/tmp/git.log"
    assert container_log_path({}) == default_container_log_path()
