"""Canonical naming for feature test runs (keys, logs, artifacts)."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from typing import TYPE_CHECKING, Literal

if TYPE_CHECKING:
    from pathlib import Path

from proman.config import load as load_config

FeatureTestMode = Literal["devcontainer", "standalone", "macos"]

_MODE_ARTIFACT_SUFFIX: dict[FeatureTestMode, str] = {
    "devcontainer": "devcontainer",
    "standalone": "linux",
    "macos": "macos",
}


@dataclass(frozen=True)
class FeatureTestRun:
    """One feature test invocation: feature id, env-qualified scenario key, mode."""

    feature: str
    scenario_key: str
    mode: FeatureTestMode


def sanitize_segment(segment: str) -> str:
    """Make a path segment safe for host log filenames."""
    return segment.replace("/", "_")


def mode_artifact_suffix(mode: FeatureTestMode | str) -> str:
    """Map mode to CI artifact and host log suffix (``linux`` for standalone)."""
    return _MODE_ARTIFACT_SUFFIX[mode]  # type: ignore[index]


def host_log_basename(run: FeatureTestRun) -> str:
    """Basename for a host install log: ``<feature>--<key>--<mode>.log``."""
    key = sanitize_segment(run.scenario_key)
    suffix = mode_artifact_suffix(run.mode)
    return f"{run.feature}--{key}--{suffix}.log"


def host_log_path(run: FeatureTestRun) -> Path:
    """``.local/logs/tests/features/<feature>--<key>--<mode>.log`` on the host."""
    base = load_config().absolute_path("path.local_logs_features")
    return base / host_log_basename(run)


def artifact_name(run: FeatureTestRun) -> str:
    """CI artifact name: ``feat-log-<feature>-<key>-<mode>``."""
    suffix = mode_artifact_suffix(run.mode)
    return f"feat-log-{run.feature}-{run.scenario_key}-{suffix}"


def bind_mount_container_log_path(run: FeatureTestRun) -> str:
    """In-container bind-mount destination for the host install log."""
    return f"/log-out/{host_log_basename(run)}"


def host_log_path_cli() -> None:
    """Print repo-relative host log path for ``(feature, scenario_key, mode)``."""
    parser = argparse.ArgumentParser(
        description="Print repo-relative path to a feature test install log.",
    )
    parser.add_argument("feature", help="Feature id (e.g. install-direnv)")
    parser.add_argument("scenario_key", help="Env-qualified scenario run key")
    parser.add_argument(
        "mode",
        choices=["devcontainer", "standalone", "macos"],
        help="Test mode",
    )
    args = parser.parse_args()
    run = FeatureTestRun(args.feature, args.scenario_key, args.mode)
    cfg = load_config()
    rel = host_log_path(run).relative_to(cfg.root_path)
    print(rel)
    sys.exit(0)


if __name__ == "__main__":
    host_log_path_cli()
