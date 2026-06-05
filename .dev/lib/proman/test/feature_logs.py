"""Feature-test install log capture (paths via ``proman.config``)."""

from __future__ import annotations

import json
import re
from typing import TYPE_CHECKING

from proman.config import load as load_config

from .scenarios import shared_defaults

if TYPE_CHECKING:
    from pathlib import Path

DEVFEATS_LOG_BIND_DIR_ENV = "DEVFEATS_LOG_BIND_DIR"
LOG_BIND_MOUNT_TARGET = "/log-out"

_FALLBACK_CONTAINER_LOG = "/tmp/devfeats-feature.log"  # noqa: S108


def container_log_path(options: dict) -> str:
    """Return LOG_FILE path used inside the install container."""
    raw = options.get("log_file")
    if raw is None or str(raw).strip() == "":
        shared_opts = shared_defaults().get("options", {})
        fallback = shared_opts.get("log_file")
        if fallback:
            return str(fallback)
        return _FALLBACK_CONTAINER_LOG
    return str(raw)


def default_container_log_path() -> str:
    """Shared default ``log_file`` from ``test/features/defaults.shared.yaml``."""
    return container_log_path({})


def uses_bind_mount_log(options: dict) -> bool:
    """Return whether the scenario uses the shared default ``log_file``."""
    raw = options.get("log_file")
    if raw is None or str(raw).strip() == "":
        return True
    return str(raw) == default_container_log_path()


def bind_mount_container_log_path(scenario_key: str) -> str:
    """In-container path for install logs written through the host bind mount."""
    name = scenario_key.replace("/", "_")
    return f"{LOG_BIND_MOUNT_TARGET}/{name}.log"


def devcontainer_log_bind_mount_spec() -> str:
    """Return the devcontainer.json mount for the host log directory at ``/log-out``."""
    return (
        f"source=${{localEnv:{DEVFEATS_LOG_BIND_DIR_ENV}}},"
        f"target={LOG_BIND_MOUNT_TARGET},type=bind,consistency=cached"
    )


def host_log_path(scenario_key: str) -> Path:
    """`.local/logs/tests/features/<scenario-key>.log` on the host."""
    name = scenario_key.replace("/", "_")
    return load_config().absolute_path("path.local_logs_features") / f"{name}.log"


def ensure_host_log_dir() -> Path:
    """Create `.local/logs/tests/features` and return it."""
    d = load_config().absolute_path("path.local_logs_features")
    d.mkdir(parents=True, exist_ok=True)
    return d


def copy_log_to_bind_mount_fragment(
    scenario_key: str,
    *,
    log_path: str | None = None,
) -> str:
    """Shell fragment: copy install log into /log-out/<key>.log when present."""
    qkey = scenario_key.replace("'", "'\\''")
    if log_path:
        qpath = log_path.replace("'", "'\\''")
        return (
            f'if [ -f "{qpath}" ]; then '
            "mkdir -p /log-out && "
            f'cp "{qpath}" "/log-out/{qkey}.log" 2>/dev/null || true; '
            "fi"
        )
    return (
        'if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE}" ]; then '
        "mkdir -p /log-out && "
        f'cp "${{LOG_FILE}}" "/log-out/{qkey}.log" 2>/dev/null || true; '
        "fi"
    )


def patch_devcontainer_scenario_logging(
    scenarios_json_path: Path,
    *,
    feature: str,
    scenario_key: str,
    options: dict,
) -> str:
    """Patch scenario JSON for host log bind mount; return in-container log path."""
    with scenarios_json_path.open(encoding="utf-8") as f:
        data = json.load(f)
    scenario = data[scenario_key]
    mounts = list(scenario.get("mounts") or [])
    spec = devcontainer_log_bind_mount_spec()
    if spec not in mounts:
        mounts.append(spec)
    scenario["mounts"] = mounts

    features = scenario.setdefault("features", {})
    feat_opts = features.get(feature)
    if not isinstance(feat_opts, dict):
        feat_opts = {}
    features[feature] = feat_opts

    if uses_bind_mount_log(options):
        effective = bind_mount_container_log_path(scenario_key)
        feat_opts["log_file"] = effective
    else:
        effective = container_log_path(options)

    with scenarios_json_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)
        f.write("\n")
    return effective


def append_bind_mount_copy_to_test_script(
    test_script: Path,
    scenario_key: str,
    *,
    log_path: str | None = None,
) -> None:
    """Insert install-log copy before ``reportResults`` for dedicated log_file tests."""
    fragment = copy_log_to_bind_mount_fragment(scenario_key, log_path=log_path)
    content = test_script.read_text(encoding="utf-8")
    if fragment in content:
        return
    if re.search(r"^reportResults\s*$", content, re.MULTILINE):
        content = re.sub(
            r"^reportResults\s*$",
            f"{fragment}\nreportResults",
            content,
            count=1,
            flags=re.MULTILINE,
        )
    else:
        content = content.rstrip() + "\n" + fragment + "\n"
    test_script.write_text(content, encoding="utf-8")
