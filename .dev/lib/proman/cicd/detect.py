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

The script writes all computed values to `GITHUB_OUTPUT`.
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
from gittidy import Git

from proman.release.detect import detect_releasable

if TYPE_CHECKING:
    from collections.abc import Iterable

CI_TRIGGER_PATHS_FILEPATH = ".github/ci_trigger_paths.yaml"
FEATURE_DIRPATH = "features"


SELF_FILEPATH = Path(__file__).resolve()
_DETECT_REPO_RELPATH = ".dev/lib/proman/cicd/detect.py"


def _resolve_repo_root() -> Path:
    for start in (Path.cwd(), SELF_FILEPATH.parent):
        try:
            out = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                cwd=str(start),
                text=True,
                stderr=subprocess.DEVNULL,
            )
            return Path(out.strip())
        except subprocess.CalledProcessError:
            continue
    msg = "Cannot determine git repository root from CWD or script location."
    raise RuntimeError(msg)


REPO_ROOT = _resolve_repo_root()
_GIT = Git(REPO_ROOT)
PATHS_FILE = REPO_ROOT / CI_TRIGGER_PATHS_FILEPATH
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
    input_feature: str
    input_version: str
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
        cwd=str(cwd or REPO_ROOT),
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
        Sorted unique feature IDs inferred from `features/*/metadata.yaml`.
    """
    ids: list[str] = []
    features_root = REPO_ROOT / FEATURE_DIRPATH
    for metadata in sorted(features_root.glob("*/metadata.yaml")):
        rel = metadata.relative_to(features_root).as_posix()
        ids.append(rel.replace("/metadata.yaml", ""))
    return sorted(set(ids))


def discover_macos_capable() -> list[str]:
    """Discover features with macOS shell scenarios.

    Returns
    -------
    list of str
        Sorted unique feature/test identifiers that have macOS scenarios.
    """
    test_features_root = REPO_ROOT / "test" / "features"
    ids = {
        path.parent.parent.name
        for path in test_features_root.glob("*/macos/*.sh")
    }
    return sorted(ids)


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
        - `is_release` boolean
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
    dispatch = env.event_name == "workflow_dispatch"
    if dispatch and env.input_feature and env.input_version:
        is_release = True
        features_to_release = [
            {
                "feature": env.input_feature,
                "version": env.input_version,
                "tag": f"{env.input_feature}/{env.input_version}",
            },
        ]
        LOG.info(
            "release-gate: manual release request detected for"
            " feature='%s' version='%s'.",
            env.input_feature,
            env.input_version,
        )
    elif (
        env.event_name == "push"
        and env.ref_type == "branch"
        and env.ref_name == "main"
    ):
        LOG.info("release-gate: push-to-main detected; running detect_releasable().")
        features_dir = REPO_ROOT / "features"
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
        Feature identifier path under `features/`.

    Returns
    -------
    str
        Version string if present; otherwise an empty string.
    """
    p = REPO_ROOT / FEATURE_DIRPATH / feature_id / "metadata.yaml"
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
        Pull request base ref (without `origin/` prefix).
    feature_id : str
        Feature identifier path under `features/`.

    Returns
    -------
    str
        Version string if present in base; otherwise an empty string.
    """
    content = _GIT.file_at_ref(
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
            "version-bump lint: modified features without metadata bump vs."
            " origin/%s:",
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
    try:
        out = sh(
            [
                "gh",
                "api",
                (
                    f"{package_scope}/packages/container"
                    f"/{package_name}-devcontainer/versions"
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
        Path to `GITHUB_OUTPUT`.
    outputs : dict of str to str
        Output values to append.
    """
    with Path(path).open("a", encoding="utf-8") as f:
        f.writelines(f"{k}={v}\n" for k, v in outputs.items())


def parse_env_from_context() -> Env:
    """Parse runtime environment from `GITHUB_CONTEXT` and process env vars.

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
    event_inputs = event.get("inputs", {})
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
        input_feature=str(event_inputs.get("feature", "")),
        input_version=str(event_inputs.get("version", "")),
        repo_owner=str(github_ctx["repository_owner"]),
        repository=str(github_ctx["repository"]),
        repository_owner_type=str(repository_owner_payload["type"]),
        github_output=os.getenv("GITHUB_OUTPUT", ""),
    )


def main() -> None:
    """Entrypoint for CI/CD detection script execution."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    env = parse_env_from_context()
    if not env.github_output:
        msg = "GITHUB_OUTPUT is required"
        raise SystemExit(msg)
    LOG.info(
        "context: event='%s' ref_type='%s' ref_name='%s'"
        " head_ref='%s' base_ref='%s'",
        env.event_name,
        env.ref_type,
        env.ref_name,
        env.head_ref,
        env.base_ref,
    )

    groups = yaml.safe_load(PATHS_FILE.read_text(encoding="utf-8"))
    LOG.info("groups: loaded decision groups: %s", ", ".join(sorted(groups.keys())))

    changed = changed_files(env)
    LOG.info(
        "Changed files: %s",
        json.dumps(changed, indent=4) if changed else "none",
    )

    zero_sha = "0" * 40
    is_force = (
        env.event_name == "workflow_dispatch"
        or (env.event_name == "push" and env.before == zero_sha)
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
    macos_capable = discover_macos_capable()
    LOG.info(
        "features: discovered total='%s' macos_capable='%s'",
        len(all_feature_ids),
        len(macos_capable),
    )

    is_release, features_to_release = detect_release(env)

    if is_force or is_release:
        run_lint = run_validate = run_unit = run_features = run_docs = run_python = True
        features = all_feature_ids
        macos_features = macos_capable
        run_macos = bool(macos_features)
    else:
        run_lint = any_match(changed, groups["lint"])
        run_validate = any_match(changed, groups["validate"])
        run_unit = any_match(changed, groups["unit_test"])
        run_docs = any_match(changed, groups["docs"])
        run_python = any_match(changed, groups["python_test"])

        if any_match(changed, groups["scenario_test"]):
            features = all_feature_ids
            macos_features = macos_capable
        else:
            features = [
                f
                for f in all_feature_ids
                if any(
                    p.startswith((f"features/{f}/", f"test/features/{f}/"))
                    for p in changed
                )
            ]
            macos_features = [
                f
                for f in macos_capable
                if any(
                    p.startswith((f"features/{f}/", f"test/features/{f}/"))
                    for p in changed
                )
            ]
        run_features = bool(features)
        run_macos = bool(macos_features)

    LOG.info(
        "decision: run_lint='%s' run_validate='%s' run_unit='%s'"
        " run_features='%s' run_macos='%s' run_docs='%s' run_python='%s'",
        str(run_lint).lower(),
        str(run_validate).lower(),
        str(run_unit).lower(),
        str(run_features).lower(),
        str(run_macos).lower(),
        str(run_docs).lower(),
        str(run_python).lower(),
    )
    LOG.info(
        "decision: features_count='%s' macos_features_count='%s'",
        len(features),
        len(macos_features),
    )
    if features:
        LOG.info(
            "decision: features=%s",
            json.dumps(features, separators=(",", ":")),
        )
    if macos_features:
        LOG.info(
            "decision: macos_features=%s",
            json.dumps(macos_features, separators=(",", ":")),
        )

    enforce_version_bump(env.event_name, env.base_ref, changed, all_feature_ids)

    outputs = {
        "run_lint": str(run_lint).lower(),
        "run_validate": str(run_validate).lower(),
        "run_unit": str(run_unit).lower(),
        "run_features": str(run_features).lower(),
        "features": json.dumps(features, separators=(",", ":")),
        "run_macos": str(run_macos).lower(),
        "run_docs": str(run_docs).lower(),
        "run_python": str(run_python).lower(),
        "macos_features": json.dumps(macos_features, separators=(",", ":")),
        "is_release": str(is_release).lower(),
        "features_to_release": json.dumps(
            features_to_release,
            separators=(",", ":"),
        ),
    }
    final_outputs = dict(outputs)
    write_outputs(env.github_output, outputs)
    LOG.info("output: wrote primary decision outputs to GITHUB_OUTPUT.")

    branch_name = env.head_ref or env.ref_name
    branch_tag = "branch-" + re.sub(r"[^a-zA-Z0-9._-]", "-", branch_name)
    LOG.info(
        "image-gate: branch_name='%s' branch_tag='%s'",
        branch_name,
        branch_tag,
    )

    devcontainer_changed = detect_devcontainer_changed(
        env,
        is_force=is_force,
        changed=changed,
        groups=groups,
    )
    existing_tags = ghcr_tags(env)
    has_latest = "latest" in existing_tags
    has_branch = branch_tag in existing_tags
    LOG.info(
        "image-gate: devcontainer_changed='%s' existing_tags_count='%s'"
        " has_latest='%s' has_branch='%s'",
        str(devcontainer_changed).lower(),
        len(existing_tags),
        str(has_latest).lower(),
        str(has_branch).lower(),
    )
    if existing_tags:
        LOG.info(
            "image-gate: existing_tags=%s",
            json.dumps(existing_tags, separators=(",", ":")),
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

    image_outputs = {
        "build_image": str(build_image).lower(),
        "image_tag": image_tag,
    }
    final_outputs.update(image_outputs)
    write_outputs(env.github_output, image_outputs)
    LOG.info(
        "image-gate: final build_image='%s' image_tag='%s'",
        str(build_image).lower(),
        image_tag,
    )
    LOG.info(
        "output: final outputs=%s",
        json.dumps(final_outputs, separators=(",", ":")),
    )


if __name__ == "__main__":
    main()
