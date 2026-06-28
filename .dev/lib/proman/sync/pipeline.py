"""Feature sync pipeline: assemble src/ from features/ + lib/."""

from __future__ import annotations

import copy
import fnmatch
import json
import shutil
import subprocess
from pathlib import Path, PurePosixPath

from proman.config import load as load_config
from proman.const import LIFECYCLE_COMMAND_KEYS
from proman.helpers import log
from proman.manifest_util import escape_devcontainer_default
from proman.metadata import MetadataLoader
from proman.sync.file_sync import SyncStatus, remove_file, sync_file
from proman.sync.install_script import InstallScriptGenerator
from proman.utils import markdown


def run(*, check_only: bool = False) -> int:
    """Assemble src/ for all features from features/ + lib/.

    Parameters
    ----------
    check_only : bool
        If True, verify sync state without writing files; return non-zero if stale.

    Returns
    -------
    int
        0 on success, 1 if any feature failed validation or sync.
    """
    config = load_config()

    lib_dirpath = config.absolute_path("path.library")
    feature_lib_dir = Path(str(config["path.feature_library"]))
    features_dirpath = config.absolute_path("path.features")
    src_dirpath = config.absolute_path("path.src")
    devcontainer_dirpath = config.absolute_path("path.devcontainer")

    metadata_loader = MetadataLoader()
    script_generator = InstallScriptGenerator()
    lib_files = _gather_lib_files(lib_dirpath, feature_lib_dir)
    bootstrap_file = _gather_bootstrap(features_dirpath)
    gitignore_patterns = _gitignore_basename_patterns(config.root_path)

    n_features: int = 0
    n_failures = 0

    all_metadata = metadata_loader.load()

    for feature_dirpath in sorted(features_dirpath.iterdir()):
        if not feature_dirpath.is_dir() or feature_dirpath.name[0] in (".", "_"):
            continue

        feature_id = feature_dirpath.name
        metadata = all_metadata.get(feature_id)

        if not metadata:
            # No metadata.yaml found; skip without counting as a failure
            # (allows draft features to be added).
            continue

        n_features += 1
        output_files: dict[Path, str] = {}

        sanitize_markdown(metadata)

        output_files.update(_generate_metadata_json(metadata=metadata))
        output_files.update(script_generator.generate(metadata))
        output_files.update(lib_files)
        output_files.update(bootstrap_file)
        try:
            disk_files = _gather_feature_files(feature_id, features_dirpath)
            metadata_files = _gather_metadata_files(metadata, feature_id=feature_id)
            output_files.update(
                _merge_feature_files(
                    disk_files,
                    metadata_files,
                    feature_id=feature_id,
                ),
            )
        except ValueError as e:
            log(f"❌ {feature_id}: {e}")
            n_failures += 1
            continue

        feature_in_sync = _sync_source_files(
            feature_id,
            output_files,
            src_dirpath,
            gitignore_patterns,
            check_only=check_only,
        )

        devcontainers_in_sync = True
        for prefix, is_local in (("test", True), ("try", False)):
            devcontainer_status = sync_file(
                devcontainer_dirpath / f"{prefix}-{feature_id}" / "devcontainer.json",
                _generate_feature_devcontainer_json(metadata, local=is_local),
                check_only=check_only,
            )
            if not devcontainer_status.is_in_sync:
                devcontainers_in_sync = False

        if not (feature_in_sync and devcontainers_in_sync):
            n_failures += 1

    stale_in_sync = _remove_stale_feature_dirs(
        features_dirpath,
        src_dirpath,
        all_metadata,
        check_only=check_only,
    )
    if not stale_in_sync:
        n_failures += 1

    log("\nFinal results:")
    if n_failures:
        log(f"\n{n_failures}/{n_features} feature(s) failed validation.")
        return 1

    log(f"✅ All {n_features} features passed.")
    return 0


def sanitize_markdown(metadata: dict) -> None:
    """Recursively process a value, stripping markdown from description fields."""
    metadata["description"] = markdown.sanitize(metadata["description"])

    if "options" in metadata:
        for option in metadata["options"].values():
            option["description"] = markdown.sanitize(option["description"])


# ── Output generation ─────────────────────────────────────────────────────────


_LIFECYCLE_EVENT_ENV_VAR: dict[str, str] = {
    "onCreateCommand": "_FEAT_LIFECYCLE_ON_CREATE",
    "updateContentCommand": "_FEAT_LIFECYCLE_UPDATE_CONTENT",
    "postCreateCommand": "_FEAT_LIFECYCLE_POST_CREATE",
    "postStartCommand": "_FEAT_LIFECYCLE_POST_START",
    "postAttachCommand": "_FEAT_LIFECYCLE_POST_ATTACH",
}


def resolve_lifecycle_command(
    entry_id: str, entry: dict, lc_key: str, metadata: dict
) -> str:
    """Return the devcontainer command string for one lifecycle entry.

    When the entry has an explicit ``command`` key that value is returned as-is.
    Otherwise the command is auto-generated as ``<path-prefix><task>.sh [args]``,
    where the path prefix comes from the feature's ``_env_vars`` and the task name
    is the entry key with the ``_lifecycle_key_prefix`` stripped.
    """
    if "command" in entry:
        return entry["command"]
    env_var = _LIFECYCLE_EVENT_ENV_VAR[lc_key]
    prefix: str = metadata["_env_vars"][env_var]
    lc_key_prefix: str = metadata["_lifecycle_key_prefix"]
    task = entry_id.removeprefix(lc_key_prefix)
    command = f"{prefix}{task}.sh"
    args: str = entry.get("args", "").strip()
    if args:
        command = f"{command} {args}"
    return command


def _generate_metadata_json(metadata: dict) -> dict[Path, str]:
    """Generate devcontainer-feature.json content from parsed YAML data."""
    metadata_json_dict: dict = {}

    for key, value in metadata.items():
        # Options
        if key == "options":
            options = {}
            for option_id, option_raw in value.items():
                option = {}
                for k, v in option_raw.items():
                    if k.startswith("_"):
                        continue
                    if k == "type" and v in ("array", "integer"):
                        option[k] = "string"
                    elif k in ("enum", "proposals"):
                        option[k] = [item["value"] for item in v]
                    elif k == "default" and isinstance(v, str):
                        option[k] = escape_devcontainer_default(v)
                    else:
                        option[k] = v
                options[option_id] = option
            metadata_json_dict[key] = options

        # Lifecycle commands
        elif key in LIFECYCLE_COMMAND_KEYS:
            metadata_json_dict[key] = {
                entry_id: resolve_lifecycle_command(entry_id, entry, key, metadata)
                for entry_id, entry in value.items()
            }

        # Entrypoint: stored as an object in metadata, emitted as a string.
        elif key == "entrypoint":
            if "command" in value:
                metadata_json_dict[key] = value["command"]
            else:
                ep_path: str = metadata["_env_vars"]["_FEAT_ENTRYPOINT_PATH"]
                args: str = value.get("args", "").strip()
                metadata_json_dict[key] = f"{ep_path} {args}" if args else ep_path

        # All other public keys
        elif not key.startswith("_"):
            metadata_json_dict[key] = value

    # Auto-emit postCreateCommand for _options.verify when args are declared.
    verify_opts: dict = metadata.get("_options", {}).get("verify", {})
    if verify_opts.get("args"):
        lc_prefix: str = metadata["_lifecycle_key_prefix"]
        verify_key = f"{lc_prefix}verify"
        post_create = metadata["_env_vars"]["_FEAT_LIFECYCLE_POST_CREATE"]
        verify_path = post_create + "verification.sh"
        metadata_json_dict.setdefault("postCreateCommand", {})[verify_key] = verify_path

    metadata_json = json.dumps(
        metadata_json_dict, sort_keys=True, indent=3, ensure_ascii=False
    )

    return {Path("devcontainer-feature.json"): f"{metadata_json.strip()}\n"}


def _generate_feature_devcontainer_json(metadata: dict, *, local: bool) -> str:
    """Generate .devcontainer/<feature>/devcontainer.json for live testing."""
    defaults = {
        "image": "ubuntu:latest",
        "remoteUser": "ubuntu",
    }

    overrides = {
        "name": f"{'Test' if local else 'Try'} {metadata['id']}",
    }

    sample = copy.deepcopy(metadata.get("_devcontainer", {}))

    devcontainer_json = defaults | sample | overrides

    features = devcontainer_json.setdefault("features", {})
    feature_id = metadata["id"]
    feat_options = {}
    for feat_id, feat_opts in features.items():
        if feature_id in feat_id:
            feat_options = feat_opts
            break
    feat_ref = (
        f"../.src/{feature_id}"
        if local
        else f"{metadata['_oci_ref']}:{metadata['version']}"
    )
    features[feat_ref] = feat_options

    return (
        json.dumps(
            devcontainer_json,
            sort_keys=True,
            indent=3,
            ensure_ascii=False,
        )
        + "\n"
    )


# ── File gathering ────────────────────────────────────────────────────────────


def _gather_lib_files(
    lib_dirpath: Path,
    feature_lib_dir: Path,
) -> dict[Path, str]:
    """Read repo library files keyed by their paths under the feature library dir."""
    files: dict[Path, str] = {}
    for src_path in sorted(lib_dirpath.rglob("*")):
        if not src_path.is_file():
            continue
        src_path_rel_lib = src_path.relative_to(lib_dirpath)
        src_path_rel_feat = feature_lib_dir / src_path_rel_lib
        files[src_path_rel_feat] = src_path.read_text(encoding="utf-8")
    return files


def _gather_bootstrap(features_dirpath: Path) -> dict[Path, str]:
    """Read features/install.sh and return it keyed as install.sh."""
    bootstrap = (features_dirpath / "install.sh").read_text(encoding="utf-8")
    return {Path("install.sh"): bootstrap}


def _gather_feature_files(feature_id: str, features_dirpath: Path) -> dict[Path, str]:
    """Read features/<id>/files/** keyed by their files/-relative output paths.

    Only git-tracked files are included.  This ensures that OS-generated
    artefacts (e.g. ``.DS_Store``) that happen to exist on disk but were never
    committed are silently ignored without any hardcoded filename list.
    """
    files_dir = features_dirpath / feature_id / "files"
    if not files_dir.is_dir():
        return {}
    ls = subprocess.run(
        ["git", "ls-files", "-z", "--", "."],
        capture_output=True,
        text=True,
        check=True,
        cwd=files_dir,
    )
    tracked = frozenset(files_dir / rel for rel in ls.stdout.split("\0") if rel)
    return {
        Path("files") / src_path.relative_to(files_dir): src_path.read_text(
            encoding="utf-8",
        )
        for src_path in sorted(files_dir.rglob("*"))
        if src_path.is_file() and src_path in tracked
    }


def _validate_metadata_file_path(path: str, *, feature_id: str) -> PurePosixPath:
    """Return a validated files/-relative path from a ``_files`` entry."""
    if not path or not path.strip():
        msg = f"Feature '{feature_id}': _files entry has an empty path."
        raise ValueError(msg)
    if path.startswith("/"):
        msg = (
            f"Feature '{feature_id}': _files path must be relative, not absolute:"
            f" {path!r}"
        )
        raise ValueError(msg)
    rel = PurePosixPath(path)
    if ".." in rel.parts:
        msg = f"Feature '{feature_id}': _files path must not contain '..': {path!r}"
        raise ValueError(msg)
    return rel


def _gather_metadata_files(metadata: dict, *, feature_id: str) -> dict[Path, str]:
    """Return ``_files`` entries keyed like ``_gather_feature_files`` output."""
    files: dict[Path, str] = {}
    seen_paths: set[str] = set()
    for entry in metadata.get("_files") or []:
        rel = _validate_metadata_file_path(entry["path"], feature_id=feature_id)
        rel_str = rel.as_posix()
        if rel_str in seen_paths:
            msg = f"Feature '{feature_id}': duplicate _files path: {rel_str!r}"
            raise ValueError(msg)
        seen_paths.add(rel_str)
        files[Path("files") / rel] = entry["content"]
    return files


def _merge_feature_files(
    disk_files: dict[Path, str],
    metadata_files: dict[Path, str],
    *,
    feature_id: str,
) -> dict[Path, str]:
    """Merge disk and metadata file maps, raising on path collisions."""
    collisions = sorted(disk_files.keys() & metadata_files.keys())
    if collisions:
        paths = ", ".join(path.as_posix() for path in collisions)
        msg = (
            f"Feature '{feature_id}': _files path(s) collide with"
            f" features/{feature_id}/files/: {paths}"
        )
        raise ValueError(msg)
    return disk_files | metadata_files


def _gitignore_basename_patterns(repo_dirpath: Path) -> list[str]:
    """Return the basename-only patterns from the repo .gitignore.

    Basename-only patterns are those without a '/' in their body — they match
    any file regardless of directory depth, exactly as git does.  Path-anchored
    patterns (e.g. ``/src/``, ``docs/features/``) are intentionally excluded so
    that this function returns only file-name patterns (e.g. ``.DS_Store``,
    ``._*``, ``Thumbs.db``).
    """
    gitignore = repo_dirpath / ".gitignore"
    if not gitignore.is_file():
        return []
    patterns: list[str] = []
    for raw in gitignore.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", "!")):
            continue
        # Directory-only patterns (trailing '/') are not file patterns.
        if line.endswith("/"):
            continue
        # Strip leading '/' anchors before the slash check.
        body = line.lstrip("/")
        # Skip patterns that contain a '/' — they are path-specific, not basename
        # patterns.
        if "/" in body:
            continue
        patterns.append(body)
    return patterns


# ── File sync ─────────────────────────────────────────────────────────────────


def _remove_stale_feature_dirs(
    features_dirpath: Path,
    src_dirpath: Path,
    all_metadata: dict[str, dict],
    *,
    check_only: bool = False,
) -> bool:
    """Drop ``src/<feature_id>/`` trees with no matching ``features/<feature_id>/``."""
    valid_ids = {
        child.name
        for child in features_dirpath.iterdir()
        if child.is_dir()
        and child.name[0] not in (".", "_")
        and child.name in all_metadata
    }
    if not src_dirpath.is_dir():
        return True

    in_sync = True
    for child in sorted(src_dirpath.iterdir()):
        if not child.is_dir() or child.name in valid_ids:
            continue
        in_sync = False
        rel = child.relative_to(src_dirpath.parent)
        if check_only:
            log(f"❌ {rel}/: stale feature directory (no features/{child.name}/)")
        else:
            shutil.rmtree(child)
            log(f"🗑 removed stale {rel}/")
    return in_sync


def _sync_source_files(
    feature_id: str,
    new_files: dict[Path, str],
    src_dirpath: Path,
    gitignore_patterns: list[str],
    *,
    check_only: bool = False,
) -> bool:
    """Sync ``src/<feature_id>/`` to match ``new_files``; deleting strays."""
    feature_src_dir = src_dirpath / feature_id
    old_filepaths: set[Path] = (
        {
            path.relative_to(feature_src_dir)
            for path in feature_src_dir.rglob("*")
            if path.is_file()
            and not any(fnmatch.fnmatch(path.name, p) for p in gitignore_patterns)
        }
        if feature_src_dir.exists()
        else set()
    )

    statuses: list[SyncStatus] = [
        sync_file(
            feature_src_dir / new_filepath,
            new_content,
            check_only=check_only,
        )
        for new_filepath, new_content in new_files.items()
    ]
    statuses.extend(
        remove_file(feature_src_dir / old_filepath, check_only=check_only)
        for old_filepath in sorted(old_filepaths - new_files.keys())
    )
    return all(status.is_in_sync for status in statuses)
