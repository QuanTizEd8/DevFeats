"""Feature metadata: read, augment, and enumerate metadata.yaml files.

This is the single authoritative source for loading feature metadata.
It is consumed by the sync pipeline, the docs pipeline, and CLI commands.

Augmented keys added by this module (prefixed with ``_`` for internal use):
    ``id``       — feature directory name (e.g. ``install-git``)
    ``_oci_ref`` — OCI image reference (e.g. ``ghcr.io/owner/repo/install-git``)
"""

from __future__ import annotations

import sys
from typing import TYPE_CHECKING, Literal

import yaml

from proman.git import git_owner_repo

if TYPE_CHECKING:
    from pathlib import Path


def log(msg: str) -> None:
    """Write a diagnostic message to stderr."""
    print(msg, file=sys.stderr)


# ── Public API ────────────────────────────────────────────────────────────────


def load_and_augment(feature_id: str, features_dirpath: Path) -> dict | None:
    """Read and fully augment metadata for a single feature; return None on failure.

    Augmentation steps performed (in order):
    1. Read ``metadata.yaml`` from disk.
    2. Merge shared options from ``features/shared-options.yaml``.
    3. Set ``metadata["id"]`` and ``metadata["_oci_ref"]``.
    """
    derived_options = load_derived_options(features_dirpath)
    metadata = read_metadata(feature_id, features_dirpath)
    if not isinstance(metadata, dict):
        return None
    if not augment_metadata(feature_id, metadata, derived_options):
        return None
    owner, repo_name = git_owner_repo()
    metadata["id"] = feature_id
    metadata["_oci_ref"] = f"ghcr.io/{owner}/{repo_name}/{feature_id}"
    return metadata


def load_all(features_dirpath: Path) -> dict[str, dict]:
    """Load and augment metadata for all features found in *features_dirpath*.

    Features whose ``metadata.yaml`` is missing or fails augmentation are
    skipped with a warning and omitted from the result.

    Returns
    -------
    dict[str, dict]
        Mapping of ``feature_id`` → fully augmented metadata dict.
    """
    all_metadata: dict[str, dict] = {}
    for meta_path in sorted(features_dirpath.glob("*/metadata.yaml")):
        feat_id = meta_path.parent.name
        metadata = load_and_augment(feat_id, features_dirpath)
        if metadata is None:
            log(f"⚠️  load_all: skipping {feat_id} (metadata load/augment failed)")
            continue
        all_metadata[feat_id] = metadata
    return all_metadata


# ── Metadata Reading ──────────────────────────────────────────────────────────


def read_metadata(feature_id: str, features_dirpath: Path) -> dict | Literal[0, 1]:
    """Read and parse the metadata.yaml for the given feature ID.

    Returns
    -------
    dict
        Parsed metadata mapping on success.
    0
        File not found — caller should skip this feature (not a hard error).
    1
        Parse or type error — caller should count as a failure.
    """
    metadata_filepath = features_dirpath / feature_id / "metadata.yaml"
    if not metadata_filepath.is_file():
        log(
            f"⚠️ {feature_id}: metadata.yaml not found for feature '{feature_id}';"
            " skipping",
        )
        return 0

    try:
        data = yaml.safe_load(metadata_filepath.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        log(f"❌ {feature_id}: YAML parse error: {exc}")
        return 1

    if not isinstance(data, dict):
        log(
            f"❌ {feature_id}: metadata.yaml does not contain a mapping"
            f" (got {type(data).__name__})",
        )
        return 1

    return data


# ── Metadata Augmentation ─────────────────────────────────────────────────────


def augment_metadata(feature_id: str, metadata: dict, derived_options: dict) -> bool:
    """Merge shared options from ``features/shared-options.yaml`` into *metadata*.

    Options tagged with ``_apply_when`` are only merged when the condition
    evaluates to ``True`` against the feature's full metadata dict.

    Returns
    -------
    bool
        ``True`` on success, ``False`` if a conflict with a derived option is
        detected (error is logged).
    """
    options: dict = metadata.get("options", {})
    for option_id, option_def in derived_options.items():
        if option_id in options:
            log(
                f"⛔ {feature_id}: option '{option_id}' is a derived option and"
                " cannot be manually defined in metadata.yaml",
            )
            return False
        should_apply = (
            _evaluate_condition(option_def["_apply_when"], metadata)
            if "_apply_when" in option_def
            else True
        )
        if should_apply:
            options[option_id] = {
                k: v for k, v in option_def.items() if not k.startswith("_")
            }
    metadata["options"] = options
    return True


def load_derived_options(features_dirpath: Path) -> dict:
    """Load ``features/shared-options.yaml`` and return its contents as a dict."""
    with (features_dirpath / "shared-options.yaml").open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


# ── Private helpers ───────────────────────────────────────────────────────────


def _evaluate_condition(apply_when: dict, data: dict) -> bool:
    """Evaluate an ``_apply_when`` condition against the feature's full metadata."""
    jsonpath = apply_when["jsonpath"]
    exists, value = _resolve_jsonpath(jsonpath, data)
    condition = apply_when["condition"]
    if condition == "exists":
        return exists
    if condition == "not_exists":
        return not exists
    if condition == "equals":
        expected = apply_when["value"]
        return exists and value == expected
    if condition == "not_equals":
        expected = apply_when["value"]
        return not exists or value != expected
    msg = f"Unsupported condition: {condition}"
    raise ValueError(msg)


def _resolve_jsonpath(jsonpath: str, data: dict) -> tuple[bool, object]:
    """Resolve a simple JSONPath expression against the feature metadata dict.

    Supported JSONPath syntax:
    - Root object: ``$``
    - Dot notation for object properties: ``$.property``

    Returns
    -------
    exists
        Whether the path exists in the metadata dict.
    value
        The value at the path if it exists, or ``None`` if it does not.
    """
    if not jsonpath.startswith("$."):
        msg = f"Unsupported JSONPath expression: {jsonpath}"
        raise ValueError(msg)
    path_parts = jsonpath[2:].split(".")
    current = data
    for part in path_parts:
        if not isinstance(current, dict) or part not in current:
            return False, None
        current = current[part]
    return True, current
