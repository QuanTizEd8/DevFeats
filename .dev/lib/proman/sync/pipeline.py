"""Feature sync pipeline: assemble src/ from features/ + lib/."""

from __future__ import annotations

import fnmatch
import json
import subprocess
import sys
from pathlib import Path

import yaml

from proman.git import git_owner_repo, git_repo_root
from proman.sync.install_script import InstallScriptGenerator
from proman.sync.metadata import (
    augment_metadata,
    build_metadata_validator,
    load_derived_options,
    read_metadata,
    sanitize_markdown,
    validate_metadata_schema,
)


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
    repo_dirpath = git_repo_root()
    owner, name = git_owner_repo()

    lib_dirpath = repo_dirpath / "lib"
    features_dirpath = repo_dirpath / "features"
    src_dirpath = repo_dirpath / "src"

    ospkg_schema_id = (
        f"https://raw.githubusercontent.com/{owner}/{name}/main/"
        f"lib/ospkg.manifest.schema.json"
    )
    license_url = f"https://github.com/{owner}/{name}/blob/main/LICENSE"
    doc_url_template = f"https://{owner}.github.io/{name}/features/{{feature_id}}"

    derived_options = load_derived_options(features_dirpath)
    validator = build_metadata_validator(features_dirpath, lib_dirpath, ospkg_schema_id)
    generator = InstallScriptGenerator(
        features_dirpath=features_dirpath,
        templates_dirpath=features_dirpath / "_install.sh-templates",
        repo_dirpath=repo_dirpath,
    )
    lib_files = _gather_lib_files(lib_dirpath)
    bootstrap_file = _gather_bootstrap(features_dirpath)
    gitignore_patterns = _gitignore_basename_patterns(repo_dirpath)

    n_features: int = 0
    n_failures: dict[str, int] = {
        "read": 0,
        "augmentation": 0,
        "schema validation": 0,
        "sync": 0,
    }

    for feature_dirpath in sorted(features_dirpath.iterdir()):

        if not feature_dirpath.is_dir() or feature_dirpath.name[0] in (".", "_"):
            continue

        feature_id = feature_dirpath.name
        metadata = read_metadata(feature_id, features_dirpath)

        if metadata == 0:
            # No metadata.yaml found; skip without counting as a failure
            # (allows draft features to be added).
            continue

        if metadata == 1:
            n_failures["read"] += 1
            continue

        n_features += 1
        output_files: dict[Path, str] = {}

        if not augment_metadata(feature_id, metadata, derived_options):
            n_failures["augmentation"] += 1
            continue

        if not validate_metadata_schema(feature_id, metadata, validator):
            n_failures["schema validation"] += 1
            continue

        metadata["id"] = feature_id
        output_files.update(_generate_dependency_manifests(metadata))

        sanitize_markdown(metadata)

        output_files.update(
            _generate_metadata_json(
                feature_id, metadata, license_url, doc_url_template,
            ),
        )
        output_files.update(generator.generate(feature_id, metadata))
        output_files.update(lib_files)
        output_files.update(bootstrap_file)
        output_files.update(_gather_feature_files(feature_id, features_dirpath))

        if not _sync_source_files(
            feature_id, output_files, src_dirpath, gitignore_patterns,
            check_only=check_only,
        ):
            n_failures["sync"] += 1

    _log("\nFinal results:")
    if any(n_failures.values()):
        n_failures_total = sum(n_failures.values())
        _log(f"\n{n_failures_total}/{n_features} feature(s) failed validation.")
        for stage, count in n_failures.items():
            if count:
                _log(f"- {count} failed at {stage} stage")
        return 1

    _log(f"✅ All {n_features} features passed.")
    return 0


# ── Output generation ─────────────────────────────────────────────────────────


def _generate_dependency_manifests(metadata: dict) -> dict[Path, str]:
    """Sync the dependencies/ directory for the given feature based on its metadata."""
    deps = metadata.get("_dependencies")
    if not deps:
        return {}

    dirpath = Path("dependencies")
    manifests = {}

    for lifecycle, groups in deps.items():
        for dep_name, dep_content in groups.items():
            dep_path = dirpath / lifecycle / f"{dep_name}.yaml"
            manifest = yaml.dump(
                dep_content,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True,
            )
            manifests[dep_path] = manifest
    return manifests


def _generate_metadata_json(
    feature_id: str,
    metadata: dict,
    license_url: str,
    doc_url_template: str,
) -> dict[Path, str]:
    """Generate devcontainer-feature.json content from parsed YAML data."""
    metadata_json_dict: dict = {
        "documentationURL": doc_url_template.format(feature_id=feature_id),
        "licenseURL": license_url,
    }

    for key, value in metadata.items():
        if key.startswith("_"):
            continue
        if key != "options":
            metadata_json_dict[key] = value
            continue

        options = {}
        for option_id, option_raw in value.items():
            option = {}
            for k, v in option_raw.items():
                if k.startswith("_"):
                    continue
                if k == "type" and v == "array":
                    option[k] = "string"
                elif k in ("enum", "proposals"):
                    option[k] = [item["value"] for item in v]
                else:
                    option[k] = v
            options[option_id] = option
        metadata_json_dict[key] = options

    metadata_json = (
        json.dumps(metadata_json_dict, sort_keys=True, indent=3, ensure_ascii=False)
        + "\n"
    )
    return {Path("devcontainer-feature.json"): metadata_json}


# ── File gathering ────────────────────────────────────────────────────────────


def _gather_lib_files(lib_dirpath: Path) -> dict[Path, str]:
    """Read all files from lib/ and return them keyed by their _lib/-relative paths."""
    files: dict[Path, str] = {}
    for src_path in sorted(lib_dirpath.rglob("*")):
        if not src_path.is_file():
            continue
        rel = src_path.relative_to(lib_dirpath)
        files[Path("_lib") / rel] = src_path.read_text(encoding="utf-8")
    return files


def _gather_bootstrap(features_dirpath: Path) -> dict[Path, str]:
    """Read features/bootstrap.sh and return it keyed as install.sh."""
    bootstrap = (features_dirpath / "bootstrap.sh").read_text(encoding="utf-8")
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
        capture_output=True, text=True, check=True,
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


def _sync_source_files(
    feature_id: str,
    new_files: dict[Path, str],
    src_dirpath: Path,
    gitignore_patterns: list[str],
    *,
    check_only: bool = False,
) -> bool:
    feature_src_dir = src_dirpath / feature_id
    old_files = {
        path.relative_to(feature_src_dir): path.read_text(encoding="utf-8")
        for path in sorted(feature_src_dir.rglob("*"))
        if path.is_file()
        and not any(fnmatch.fnmatch(path.name, p) for p in gitignore_patterns)
    } if feature_src_dir.exists() else {}

    is_in_sync = True

    for new_filepath, new_content in new_files.items():
        if new_filepath not in old_files:
            if check_only:
                is_in_sync = False
                _log(f"⛔ {feature_id}: {new_filepath} is missing")
            else:
                dest = feature_src_dir / new_filepath
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(new_content, encoding="utf-8")
                _log(f"✅ {feature_id}: {new_filepath} created")
            continue

        if old_files[new_filepath] == new_content:
            _log(f"✅ {feature_id}: {new_filepath} unchanged")
            continue

        if check_only:
            is_in_sync = False
            _log(f"⛔ {feature_id}: {new_filepath} is stale")
        else:
            (feature_src_dir / new_filepath).write_text(new_content, encoding="utf-8")
            _log(f"✅ {feature_id}: {new_filepath} updated")

    for old_filepath in old_files:
        if old_filepath not in new_files:
            if check_only:
                is_in_sync = False
                _log(f"⛔ {feature_id}: {old_filepath} must be removed")
            else:
                (feature_src_dir / old_filepath).unlink()
                _log(f"🗑️  {feature_id}: {old_filepath} removed")
    return is_in_sync


def _log(msg: str) -> None:
    print(msg, file=sys.stderr)
