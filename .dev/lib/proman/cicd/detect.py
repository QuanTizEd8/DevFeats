"""Detect CI/CD workflow decisions from repository and event state.

This module replaces the shell-based `cicd_detect.sh` logic with Python while
preserving outputs and decision behavior expected by the GitHub Actions
workflows in this repository.

Responsibilities include:

- determining force-run mode for specific event conditions
- collecting changed files and mapping them to decision groups from YAML
- selecting feature and macOS test matrices
- enforcing PR version-bump rules for changed features
- resolving release eligibility and releasable feature list
- deciding devcontainer image build/reuse strategy
- computing all CI job configuration and emitting a single ``config`` JSON

The script writes a single ``config`` key to ``GITHUB_OUTPUT``.
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
from dataclasses import dataclass
from fnmatch import fnmatch
from pathlib import Path
from typing import TYPE_CHECKING

import yaml

from proman.config import load_ci
from proman.git import git_repo_root
from proman.release.detect import detect_releasable

if TYPE_CHECKING:
    from collections.abc import Iterable


FEATURE_DIRPATH = "features"

SELF_FILEPATH = Path(__file__).resolve()
_DETECT_REPO_RELPATH = ".dev/lib/proman/cicd/detect.py"


LOG = logging.getLogger("cicd_detect")


@dataclass(frozen=True)
class Env:
    """Environment and context values used by detection logic."""

    event_name: str
    ref_type: str
    ref_name: str
    head_ref: str
    base_ref: str
    before: str
    input_rebuild_devcontainer: str
    # Dispatch override inputs (empty string = not provided)
    input_run_lint: str
    input_run_validate: str
    input_run_unit: str
    input_run_features: str
    input_features: str
    input_run_macos: str
    input_macos_features: str
    input_run_python: str
    input_run_docs: str
    repo_owner: str
    repository: str
    repository_owner_type: str
    github_output: str


def sh(cmd: list[str], cwd: Path | None = None, *, check: bool = True) -> str:
    """Run a subprocess command and return stripped stdout.

    Parameters
    ----------
    cmd : list of str
        Command and arguments to execute.
    cwd : pathlib.Path or None, optional
        Working directory for command execution.
    check : bool, optional
        If True, raise on non-zero exit status.

    Returns
    -------
    str
        Standard output with surrounding whitespace removed.
    """
    proc = subprocess.run(
        cmd,
        cwd=str(cwd or git_repo_root()),
        check=check,
        text=True,
        capture_output=True,
    )
    return proc.stdout.strip()


def any_match(paths: Iterable[str], patterns: Iterable[str]) -> bool:
    """Return whether any path matches any provided pattern.

    Parameters
    ----------
    paths : iterable of str
        Changed file paths to test.
    patterns : iterable of str
        Glob-like matching patterns.

    Returns
    -------
    bool
        True if any path satisfies at least one pattern.
    """
    pats = list(patterns)
    if not pats:
        return False
    for p in paths:
        for pat in pats:
            if fnmatch(p, pat):
                return True
    return False


def discover_feature_ids() -> list[str]:
    """Discover feature IDs from feature metadata files.

    Returns
    -------
    list of str
        Sorted unique feature IDs inferred from ``features/*/metadata.yaml``.
    """
    ids: list[str] = []
    features_root = git_repo_root() / FEATURE_DIRPATH
    for metadata in sorted(features_root.glob("*/metadata.yaml")):
        rel = metadata.relative_to(features_root).as_posix()
        ids.append(rel.replace("/metadata.yaml", ""))
    return sorted(set(ids))


def compute_macos_matrix(feature_ids: list[str]) -> list[dict[str, str]]:
    """Compute ``{feature, runner}`` pairs for macOS testing.

    Reads ``test/environments.yaml`` and each feature's
    ``test/features/{id}/scenarios.yaml`` to find scenarios that target a macOS
    environment (image name starts with ``"macos"``).

    Parameters
    ----------
    feature_ids : list of str
        Feature IDs to inspect. Only features with macOS scenarios are included.

    Returns
    -------
    list of dict
        Unique ``{"feature": str, "runner": str}`` pairs sorted by feature then runner.
    """
    envs_data: dict = (
        yaml.safe_load(
            (git_repo_root() / "test/environments.yaml").read_text(encoding="utf-8"),
        )
        or {}
    )
    seen: set[tuple[str, str]] = set()
    result: list[dict[str, str]] = []
    for fid in sorted(feature_ids):
        scenarios_file = git_repo_root() / "test" / "features" / fid / "scenarios.yaml"
        if not scenarios_file.exists():
            continue
        scenarios: dict = (
            yaml.safe_load(scenarios_file.read_text(encoding="utf-8")) or {}
        )
        for key, scenario in scenarios.items():
            if key == "defaults":
                continue
            for env_name in scenario.get("envs") or []:
                env_def = envs_data.get(env_name)
                if not isinstance(env_def, dict):
                    continue
                image = env_def.get("image", "")
                if image.startswith("macos"):
                    pair = (fid, image)
                    if pair not in seen:
                        seen.add(pair)
                        result.append({"feature": fid, "runner": image})
    return result


def compute_unit_macos_matrix() -> list[dict[str, str]]:
    """Compute macOS runner entries for unit tests.

    Returns
    -------
    list of dict
        Unique ``{"runner": image}`` entries from ``test/environments.yaml``
        where the image name starts with ``"macos"``, sorted by runner name.
    """
    envs_data: dict = (
        yaml.safe_load(
            (git_repo_root() / "test/environments.yaml").read_text(encoding="utf-8"),
        )
        or {}
    )
    runners: set[str] = set()
    for val in envs_data.values():
        if isinstance(val, dict) and val.get("image", "").startswith("macos"):
            runners.add(val["image"])
    return [{"runner": r} for r in sorted(runners)]


def compute_unit_env_matrix() -> list[dict[str, str]]:
    """Compute Linux environment entries for unit tests.

    Returns
    -------
    list of dict
        ``{"name": scenario_key, "env": env_name}`` for every non-``defaults``
        entry in ``test/lib/scenarios.yaml``, preserving file order.
    """
    data: dict = (
        yaml.safe_load(
            (git_repo_root() / "test/lib/scenarios.yaml").read_text(encoding="utf-8"),
        )
        or {}
    )
    return [{"name": k, "env": v["env"]} for k, v in data.items() if k != "defaults"]


def _parse_feature_list(s: str) -> list[str]:
    """Parse a feature list from a dispatch input string.

    Parameters
    ----------
    s : str
        Either a JSON array string (``"[\"a\",\"b\"]"``) or a comma-separated
        list (``"a, b"``).

    Returns
    -------
    list of str
        Parsed feature IDs with empty strings filtered out.
    """
    s = s.strip()
    if s.startswith("["):
        return json.loads(s)
    return [f.strip() for f in s.split(",") if f.strip()]


def _bool_inp(val: str, *, default: bool = True) -> bool:
    """Convert a dispatch boolean input string to bool.

    Parameters
    ----------
    val : str
        ``"true"``, ``"false"``, or ``""`` (not provided).
    default : bool
        Value to return when ``val`` is empty.
    """
    if val == "":
        return default
    return val == "true"


def changed_files(env: Env) -> list[str]:
    """Collect changed files for the current event context.

    Parameters
    ----------
    env : Env
        Parsed environment/context values.

    Returns
    -------
    list of str
        Changed file paths according to event-specific diff baseline.
    """
    if env.event_name == "pull_request":
        out = sh(["git", "diff", "--name-only", f"origin/{env.base_ref}...HEAD"])
    else:
        out = sh(["git", "diff", "--name-only", f"{env.before}...HEAD"])
    return [line.strip() for line in out.splitlines() if line.strip()]


def detect_release(env: Env) -> tuple[bool, list[dict[str, str]]]:
    """Resolve release mode and feature release entries.

    Parameters
    ----------
    env : Env
        Parsed environment/context values.

    Returns
    -------
    tuple
        Pair of:
        - ``is_release`` boolean
        - release entries as list of dicts
    """
    is_release = False
    features_to_release: list[dict[str, str]] = []
    LOG.info(
        "release-gate: EVENT_NAME='%s' REF_TYPE='%s' REF_NAME='%s' BEFORE='%s'",
        env.event_name,
        env.ref_type,
        env.ref_name,
        env.before,
    )
    if env.event_name == "push" and env.ref_type == "branch" and env.ref_name == "main":
        LOG.info("release-gate: push-to-main detected; running detect_releasable().")
        features_dir = git_repo_root() / "features"
        try:
            features_to_release = detect_releasable(env.repository, features_dir)
        except RuntimeError as exc:
            LOG.exception("release-gate: detect_releasable() failed")
            raise SystemExit(1) from exc
        LOG.info(
            "release-gate: detect_releasable() result: %s",
            features_to_release,
        )
        if features_to_release:
            is_release = True
    LOG.info(
        "release-gate: is_release='%s' features_to_release_count='%s'.",
        str(is_release).lower(),
        len(features_to_release),
    )
    return is_release, features_to_release


def head_feature_version(feature_id: str) -> str:
    """Read feature version from HEAD metadata.

    Parameters
    ----------
    feature_id : str
        Feature identifier path under ``features/``.

    Returns
    -------
    str
        Version string if present; otherwise an empty string.
    """
    p = git_repo_root() / FEATURE_DIRPATH / feature_id / "metadata.yaml"
    if not p.exists():
        return ""
    payload = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    version = payload.get("version", "")
    return str(version) if version is not None else ""


def base_feature_version(base_ref: str, feature_id: str) -> str:
    """Read feature version from the base branch metadata.

    Parameters
    ----------
    base_ref : str
        Pull request base ref (without ``origin/`` prefix).
    feature_id : str
        Feature identifier path under ``features/``.

    Returns
    -------
    str
        Version string if present in base; otherwise an empty string.
    """
    from gittidy import Git

    content = Git(git_repo_root()).file_at_ref(
        f"origin/{base_ref}",
        f"features/{feature_id}/metadata.yaml",
        raise_missing=False,
    )
    if not content:
        return ""
    payload = yaml.safe_load(content) or {}
    version = payload.get("version", "")
    return str(version) if version is not None else ""


def enforce_version_bump(
    event_name: str,
    base_ref: str,
    changed: list[str],
    feature_ids: list[str],
) -> None:
    """Enforce version-bump policy for pull requests.

    Parameters
    ----------
    event_name : str
        Current GitHub event name.
    base_ref : str
        Pull request base ref.
    changed : list of str
        Changed file paths.
    feature_ids : list of str
        Feature IDs to evaluate.
    """
    if event_name != "pull_request":
        return
    libs_changed = any(p.startswith("lib/") for p in changed)
    bootstrap_changed = "features/install.sh" in changed
    needs_bump: list[str] = []

    for fid in feature_ids:
        fid_changed = any(p.startswith(f"features/{fid}/") for p in changed)
        if not (libs_changed or bootstrap_changed or fid_changed):
            continue
        base_v = base_feature_version(base_ref, fid)
        head_v = head_feature_version(fid)
        if not base_v:
            continue  # new feature exempt
        if base_v == head_v:
            needs_bump.append(f"{fid} (version still {head_v})")

    if needs_bump:
        LOG.error(
            "version-bump lint: modified features without metadata bump vs. origin/%s:",
            base_ref,
        )
        for item in needs_bump:
            LOG.error("  - %s", item)
        LOG.error(
            "   Bump the version field in each listed feature's"
            " metadata.yaml before merging.",
        )
        raise SystemExit(1)


def detect_devcontainer_changed(
    env: Env,
    *,
    is_force: bool,
    changed: list[str],
    groups: dict[str, list[str]],
) -> bool:
    """Decide whether devcontainer sources should be treated as changed.

    Parameters
    ----------
    env : Env
        Parsed environment/context values.
    is_force : bool
        Force-run mode flag.
    changed : list of str
        Changed file paths.
    groups : dict of str to list of str
        Decision-group patterns.

    Returns
    -------
    bool
        True if devcontainer should be rebuilt due to changes or override.
    """
    if env.event_name == "workflow_dispatch":
        return env.input_rebuild_devcontainer == "true"
    if is_force:
        return True
    return any_match(changed, groups["devcontainer"])


def ghcr_tags(env: Env) -> list[str]:
    """Query existing devcontainer tags from GHCR.

    Parameters
    ----------
    env : Env
        Parsed environment/context values.

    Returns
    -------
    list of str
        Existing tag names if available; otherwise an empty list.
    """
    owner_name = env.repo_owner.lower()
    package_name = env.repository.split("/", 1)[1].lower()
    package_scope = ""
    owner_type = env.repository_owner_type
    if owner_type == "Organization":
        package_scope = f"orgs/{owner_name}"
    elif owner_type == "User":
        package_scope = f"users/{owner_name}"
    else:
        msg = f"Unsupported repository owner type for GHCR query: {owner_type}"
        raise RuntimeError(msg)
    if not package_scope:
        return []
    image_suffix = load_ci()["image"]["suffix"]
    try:
        out = sh(
            [
                "gh",
                "api",
                (
                    f"{package_scope}/packages/container"
                    f"/{package_name}{image_suffix}/versions"
                ),
                "--jq",
                ".[].metadata.container.tags[]",
            ],
        )
    except subprocess.CalledProcessError:
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]


def write_outputs(path: str, outputs: dict[str, str]) -> None:
    """Append key-value outputs to GitHub Actions output file.

    Parameters
    ----------
    path : str
        Path to ``GITHUB_OUTPUT``.
    outputs : dict of str to str
        Output values to append.
    """
    with Path(path).open("a", encoding="utf-8") as f:
        f.writelines(f"{k}={v}\n" for k, v in outputs.items())


def parse_env_from_context() -> Env:
    """Parse runtime environment from ``GITHUB_CONTEXT`` and process env vars.

    Returns
    -------
    Env
        Parsed environment object used for workflow detection.
    """
    github_ctx_raw = os.getenv("GITHUB_CONTEXT")
    if not github_ctx_raw:
        msg = "GITHUB_CONTEXT is required"
        raise SystemExit(msg)
    github_ctx = json.loads(github_ctx_raw)
    event = github_ctx["event"]
    repository_payload = event["repository"]
    repository_owner_payload = repository_payload["owner"]
    event_inputs = event.get("inputs") or {}
    return Env(
        event_name=str(github_ctx["event_name"]),
        ref_type=str(github_ctx["ref_type"]),
        ref_name=str(github_ctx["ref_name"]),
        head_ref=str(github_ctx.get("head_ref", "")),
        base_ref=str(github_ctx.get("base_ref", "")),
        before=str(event.get("before", "")),
        input_rebuild_devcontainer=str(
            event_inputs.get("rebuild_devcontainer", "false"),
        ),
        input_run_lint=str(event_inputs.get("run_lint", "")),
        input_run_validate=str(event_inputs.get("run_validate", "")),
        input_run_unit=str(event_inputs.get("run_unit", "")),
        input_run_features=str(event_inputs.get("run_features", "")),
        input_features=str(event_inputs.get("features", "")),
        input_run_macos=str(event_inputs.get("run_macos", "")),
        input_macos_features=str(event_inputs.get("macos_features", "")),
        input_run_python=str(event_inputs.get("run_python", "")),
        input_run_docs=str(event_inputs.get("run_docs", "")),
        repo_owner=str(github_ctx["repository_owner"]),
        repository=str(github_ctx["repository"]),
        repository_owner_type=str(repository_owner_payload["type"]),
        github_output=os.getenv("GITHUB_OUTPUT", ""),
    )


def build_config(  # noqa: PLR0913
    *,
    build_image: bool,
    image_name: str,
    image_tag: str,
    ci_image: str,
    run_lint: bool,
    run_validate: bool,
    run_unit: bool,
    run_features: bool,
    features: list[str],
    run_macos: bool,
    macos_matrix: list[dict[str, str]],
    run_python: bool,
    run_docs: bool,
    is_release: bool,
    features_to_release: list[dict[str, str]],
    unit_env_matrix: list[dict[str, str]],
    unit_macos_matrix: list[dict[str, str]],
) -> dict:
    """Assemble the single ``config`` dict written to GITHUB_OUTPUT."""
    ci = load_ci()
    img = ci["image"]
    art = ci["artifacts"]
    pub = ci["publish"]
    scr = ci["scripts"]
    fds = ci["runner"]["free_disk_space"]
    source_enabled = any([run_lint, run_validate, run_unit, run_features, run_macos])
    return {
        "cm_devcontainer": {
            "enabled": build_image,
            "image_name": image_name,
            "image_tag": image_tag,
            "tag_is_latest": image_tag == "latest",
            "config_dir": img["config_dir"],
            "userdata_dir": img["userdata_dir"],
            "cache_ref_prefix": img["cache_ref_prefix"],
            "registry": pub["registry"],
            "build_matrix": img["build_matrix"],
        },
        "ci_build": {
            "ci_image": ci_image,
            "source": {
                "enabled": source_enabled,
                "artifact_src": {
                    "name": art["src"]["name"],
                    "path": art["src"]["path"],
                    "retention_days": art["retention_days"],
                },
                "artifact_dist": {
                    "name": art["dist"]["name"],
                    "path": art["dist"]["path"],
                    "retention_days": art["retention_days"],
                },
            },
            "docs": {
                "enabled": run_docs,
                "artifact": {
                    "name": art["pages"]["name"],
                    "path": art["pages"]["path"],
                    "retention_days": art["retention_days"],
                },
            },
        },
        "ci_lint": {
            "ci_image": ci_image,
            "artifact_src_name": art["src"]["name"],
            "artifact_src_path": art["src"]["path"],
            "shell": {"enabled": run_lint},
            "validate": {"enabled": run_validate, "features_path": scr["features_src"]},
            "python": {"enabled": run_python},
        },
        "ci_test_dev": {
            "enabled": run_python,
            "ci_image": ci_image,
        },
        "ci_test_feat": {
            "artifact_src_name": art["src"]["name"],
            "artifact_src_path": art["src"]["path"],
            "linux": {
                "enabled": run_features,
                "features": features,
                "ci_image": ci_image,
                "registry": pub["registry"],
                "free_disk_space": {
                    "tool_cache": fds["tool_cache"],
                    "swap_storage": fds["swap_storage"],
                    "docker_images": fds["docker_images"],
                    "android": fds["android"],
                    "dotnet": fds["dotnet"],
                    "haskell": fds["haskell"],
                    "large_packages": fds["large_packages"],
                },
            },
            "macos": {
                "enabled": run_macos,
                "matrix": macos_matrix,
            },
        },
        "ci_test_lib": {
            "enabled": run_unit,
            "ci_image": ci_image,
            "artifact_src_name": art["src"]["name"],
            "artifact_src_path": art["src"]["path"],
            "linux_matrix": unit_env_matrix,
            "macos_matrix": unit_macos_matrix,
        },
        "cd": {
            "enabled": is_release,
            "features": features_to_release,
            "artifact_src_name": art["src"]["name"],
            "artifact_src_path": art["src"]["path"],
            "artifact_dist_name": art["dist"]["name"],
            "artifact_dist_path": art["dist"]["path"],
            "features_src_path": scr["features_src"],
            "registry": pub["registry"],
            "git_bot_name": pub["git_bot"]["name"],
            "git_bot_email": pub["git_bot"]["email"],
            "pages_environment": pub["pages_environment"],
        },
    }


def main() -> None:
    """Entrypoint for CI/CD detection script execution."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    env = parse_env_from_context()
    if not env.github_output:
        msg = "GITHUB_OUTPUT is required"
        raise SystemExit(msg)
    LOG.info(
        "context: event='%s' ref_type='%s' ref_name='%s' head_ref='%s' base_ref='%s'",
        env.event_name,
        env.ref_type,
        env.ref_name,
        env.head_ref,
        env.base_ref,
    )

    groups = load_ci()["triggers"]
    LOG.info("groups: loaded decision groups: %s", ", ".join(sorted(groups.keys())))

    changed = changed_files(env)
    LOG.info(
        "Changed files: %s",
        json.dumps(changed, indent=4) if changed else "none",
    )

    zero_sha = "0" * 40
    is_force = env.event_name != "workflow_dispatch" and (
        (env.event_name == "push" and env.before == zero_sha)
        or any_match(
            changed,
            [
                ".github/workflows/*.yaml",
                _DETECT_REPO_RELPATH,
            ],
        )
    )
    LOG.info("force-gate: is_force='%s'", str(is_force).lower())

    all_feature_ids = discover_feature_ids()
    LOG.info("features: discovered total='%s'", len(all_feature_ids))

    is_release, features_to_release = detect_release(env)

    # ── Resolve run flags ────────────────────────────────────────────────────
    if env.event_name == "workflow_dispatch":
        run_lint = _bool_inp(env.input_run_lint)
        run_validate = _bool_inp(env.input_run_validate)
        run_unit = _bool_inp(env.input_run_unit)
        run_features_flag = _bool_inp(env.input_run_features)
        run_macos_flag = _bool_inp(env.input_run_macos)
        run_python = _bool_inp(env.input_run_python)
        run_docs = _bool_inp(env.input_run_docs)
        features: list[str] = (
            _parse_feature_list(env.input_features)
            if env.input_features
            else (all_feature_ids if run_features_flag else [])
        )
        macos_capable_ids: list[str] = (
            _parse_feature_list(env.input_macos_features)
            if env.input_macos_features
            else (
                [d["feature"] for d in compute_macos_matrix(all_feature_ids)]
                if run_macos_flag
                else []
            )
        )
        LOG.info(
            "dispatch: run_lint=%s run_validate=%s run_unit=%s"
            " run_features=%s run_macos=%s run_python=%s run_docs=%s",
            run_lint,
            run_validate,
            run_unit,
            run_features_flag,
            run_macos_flag,
            run_python,
            run_docs,
        )
    elif is_force or is_release:
        run_lint = run_validate = run_unit = run_python = run_docs = True
        features = all_feature_ids
        macos_capable_ids = [
            d["feature"] for d in compute_macos_matrix(all_feature_ids)
        ]
        LOG.info("force-gate: all jobs enabled; all features selected")
    else:
        run_lint = any_match(changed, groups["lint"])
        run_validate = any_match(changed, groups["validate"])
        run_unit = any_match(changed, groups["unit_test"])
        run_docs = any_match(changed, groups["docs"])
        run_python = any_match(changed, groups["python_test"])

        if any_match(changed, groups["scenario_test"]):
            features = all_feature_ids
            macos_capable_ids = [
                d["feature"] for d in compute_macos_matrix(all_feature_ids)
            ]
        else:
            features = [
                f
                for f in all_feature_ids
                if any(
                    p.startswith((f"features/{f}/", f"test/features/{f}/"))
                    for p in changed
                )
            ]
            macos_capable_ids = [
                f
                for f in [d["feature"] for d in compute_macos_matrix(all_feature_ids)]
                if any(
                    p.startswith((f"features/{f}/", f"test/features/{f}/"))
                    for p in changed
                )
            ]

    LOG.info(
        "decision: run_lint='%s' run_validate='%s' run_unit='%s'"
        " run_python='%s' run_docs='%s'",
        str(run_lint).lower(),
        str(run_validate).lower(),
        str(run_unit).lower(),
        str(run_python).lower(),
        str(run_docs).lower(),
    )

    # ── Compute matrices ─────────────────────────────────────────────────────
    macos_matrix = compute_macos_matrix(macos_capable_ids)
    run_macos = bool(macos_matrix)
    run_features = bool(features)

    unit_env_matrix = compute_unit_env_matrix()
    unit_macos_matrix = compute_unit_macos_matrix()

    LOG.info(
        "matrices: features=%d macos_matrix=%d unit_env=%d unit_macos=%d",
        len(features),
        len(macos_matrix),
        len(unit_env_matrix),
        len(unit_macos_matrix),
    )

    enforce_version_bump(env.event_name, env.base_ref, changed, all_feature_ids)

    # ── Devcontainer image gate ───────────────────────────────────────────────
    devcontainer_changed = detect_devcontainer_changed(
        env,
        is_force=is_force,
        changed=changed,
        groups=groups,
    )
    existing_tags = ghcr_tags(env)
    has_latest = "latest" in existing_tags

    branch_name = env.head_ref or env.ref_name
    branch_tag = "branch-" + re.sub(r"[^a-zA-Z0-9._-]", "-", branch_name)
    has_branch = branch_tag in existing_tags

    LOG.info(
        "image-gate: devcontainer_changed='%s' existing_tags_count='%s'"
        " has_latest='%s' has_branch='%s'",
        str(devcontainer_changed).lower(),
        len(existing_tags),
        str(has_latest).lower(),
        str(has_branch).lower(),
    )

    build_image = False
    image_tag = "latest"
    if branch_name == "main":
        image_tag = "latest"
        if devcontainer_changed or not has_latest:
            build_image = True
    elif devcontainer_changed:
        build_image = True
        image_tag = branch_tag
    elif has_branch:
        build_image = False
        image_tag = branch_tag
    elif has_latest:
        build_image = False
        image_tag = "latest"
    else:
        build_image = True
        image_tag = branch_tag

    LOG.info(
        "image-gate: final build_image='%s' image_tag='%s'",
        str(build_image).lower(),
        image_tag,
    )

    # ── Assemble and emit single config output ────────────────────────────────
    ci_cfg = load_ci()
    image_name = f"{ci_cfg['publish']['registry']}/{env.repository.lower()}{ci_cfg['image']['suffix']}"
    ci_image = f"{image_name}:{image_tag}"

    config = build_config(
        build_image=build_image,
        image_name=image_name,
        image_tag=image_tag,
        ci_image=ci_image,
        run_lint=run_lint,
        run_validate=run_validate,
        run_unit=run_unit,
        run_features=run_features,
        features=features,
        run_macos=run_macos,
        macos_matrix=macos_matrix,
        run_python=run_python,
        run_docs=run_docs,
        is_release=is_release,
        features_to_release=features_to_release,
        unit_env_matrix=unit_env_matrix,
        unit_macos_matrix=unit_macos_matrix,
    )

    write_outputs(
        env.github_output, {"config": json.dumps(config, separators=(",", ":"))}
    )
    LOG.info(
        "output: wrote config to GITHUB_OUTPUT (keys: %s)", ", ".join(config.keys())
    )


if __name__ == "__main__":
    main()
