"""Unit tests for devcontainer / standalone feature log capture helpers."""

# ruff: noqa: S108 — paths mirror real feature-test log_file options under /tmp/

from __future__ import annotations

import json
from typing import TYPE_CHECKING

from proman.test.feature_logs import (
    DEVFEATS_LOG_BIND_DIR_ENV,
    append_bind_mount_copy_to_test_script,
    container_log_path,
    copy_log_to_bind_mount_fragment,
    default_container_log_path,
    devcontainer_log_bind_mount_spec,
    patch_devcontainer_scenario_logging,
    uses_bind_mount_log,
)
from proman.test.names import FeatureTestRun

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


def test_copy_log_to_bind_mount_fragment_uses_run_basename() -> None:
    """Copy fragment targets /log-out/<feature>--<key>--<mode>.log."""
    run = FeatureTestRun("install-direnv", "default.ubuntu-stable", "standalone")
    fragment = copy_log_to_bind_mount_fragment(run, log_path="/tmp/x.log")
    assert "/log-out/install-direnv--default.ubuntu-stable--linux.log" in fragment


def test_devcontainer_log_bind_mount_spec_uses_env_var() -> None:
    """Bind mount spec references DEVFEATS_LOG_BIND_DIR localEnv."""
    assert DEVFEATS_LOG_BIND_DIR_ENV in devcontainer_log_bind_mount_spec()
    assert "target=/log-out" in devcontainer_log_bind_mount_spec()


def test_patch_devcontainer_scenario_logging_default_log_file(
    tmp_path: Path,
) -> None:
    """Default scenarios get mount only; install log_file stays on /tmp."""
    path = tmp_path / "scenarios.json"
    path.write_text(
        json.dumps(
            {
                "default_install.ubuntu-stable": {
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
        scenario_key="default_install.ubuntu-stable",
        options={},
    )
    assert effective == "/tmp/devfeats-feature.log"
    data = json.loads(path.read_text(encoding="utf-8"))
    sc = data["default_install.ubuntu-stable"]
    assert devcontainer_log_bind_mount_spec() in sc["mounts"]
    assert "log_file" not in sc["features"]["install-git"]


def test_patch_devcontainer_scenario_logging_custom_log_file(
    tmp_path: Path,
) -> None:
    """Dedicated log_file scenarios keep in-container path but still get mount."""
    path = tmp_path / "scenarios.json"
    path.write_text(
        json.dumps(
            {
                "log_file.ubuntu-stable": {
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
        scenario_key="log_file.ubuntu-stable",
        options={"log_file": "/tmp/git.log"},
    )
    assert effective == "/tmp/git.log"
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["log_file.ubuntu-stable"]["features"]["install-git"]["log_file"] == (
        "/tmp/git.log"
    )
    assert devcontainer_log_bind_mount_spec() in data["log_file.ubuntu-stable"]["mounts"]


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
    run = FeatureTestRun("install-conda-env", "log_file.ubuntu-stable", "devcontainer")
    append_bind_mount_copy_to_test_script(
        script,
        run,
        log_path="/tmp/conda-env.log",
    )
    text = script.read_text(encoding="utf-8")
    assert "/tmp/conda-env.log" in text
    assert "/log-out/install-conda-env--log_file.ubuntu-stable--devcontainer.log" in text
    assert text.index("/log-out/") < text.rindex("reportResults")


def test_append_bind_mount_copy_skips_heredoc_report_results_comment(
    tmp_path: Path,
) -> None:
    """Do not replace reportResults inside embedded assert.sh heredoc text."""
    lib_line = "#   reportResults                                   — summary\n"
    script = tmp_path / "log_file.sh"
    script.write_text(
        f"#!/bin/bash\ncat > /tmp/lib <<'END'\n{lib_line}END\nreportResults\n",
        encoding="utf-8",
    )
    run = FeatureTestRun("install-git", "log_file.ubuntu-stable", "devcontainer")
    append_bind_mount_copy_to_test_script(
        script,
        run,
        log_path="/tmp/conda-env.log",
    )
    text = script.read_text(encoding="utf-8")
    assert text.count("reportResults") == 2
    assert lib_line in text


def test_container_log_path_respects_options() -> None:
    """Resolve log_file from options or shared defaults."""
    assert container_log_path({"log_file": "/tmp/git.log"}) == "/tmp/git.log"
    assert container_log_path({}) == default_container_log_path()
