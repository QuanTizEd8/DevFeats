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

from proman.const import export_profile_d, feat_share_dir
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
    2. Substitute feature-scoped variables (e.g. ``@@_FEAT_SHARE_DIR@@``) in all
       string values.  See :func:`_feature_vars` for the full variable table.
    3. Merge shared options from ``features/shared-options.yaml``.
    4. Set ``metadata["id"]`` and ``metadata["_oci_ref"]``.
    """
    derived_options = load_derived_options(features_dirpath)
    metadata = read_metadata(feature_id, features_dirpath)
    if not isinstance(metadata, dict):
        return None
    owner, repo_name = git_owner_repo()
    metadata = _substitute_vars(metadata, _feature_vars(feature_id, owner, repo_name))
    if not augment_metadata(feature_id, metadata, derived_options):
        return None
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


def _inject_prefix_options(feature_id: str, metadata: dict) -> bool:
    """Inject prefix/symlink/export_path options for each ``_prefix_groups`` entry."""
    prefix_groups = metadata.get("_prefix_groups")
    if not prefix_groups:
        return True

    _default_root = "/usr/local"
    _default_nonroot = "${HOME}/.local"

    options: dict = metadata["options"]

    for group_id, group_cfg in prefix_groups.items():
        default_root: str = group_cfg.get("default_root", _default_root)
        default_nonroot: str = group_cfg.get("default_nonroot", _default_nonroot)
        option_name: str | None = group_cfg.get("option_name")
        dir_symlink: bool = group_cfg.get("dir_symlink", False)
        skip_symlink: bool = group_cfg.get("skip_symlink", False)
        skip_export_path: bool = group_cfg.get("skip_export_path", False)
        export_path_default: str = group_cfg.get("export_path_default", "auto")
        applies_when: list | None = group_cfg.get("_applies_when")
        prefix_description: str | None = group_cfg.get("prefix_description")
        symlink_description: str | None = group_cfg.get("symlink_description")
        export_path_description: str | None = group_cfg.get("export_path_description")

        binname: str = group_cfg.get("bin", "")
        bin_dir: str = "bin"

        prefix_key = option_name or (f"{group_id}_prefix" if group_id else "prefix")
        symlink_key = f"{group_id}_symlink" if group_id else "symlink"
        export_key = f"{group_id}_export_path" if group_id else "export_path"

        # Inject prefix option
        if prefix_key in options:
            log(
                f"⛔ {feature_id}: option '{prefix_key}' is a derived prefix option and"
                " cannot be manually defined in metadata.yaml",
            )
            return False
        bin_note = (
            f" The `{binname}` binary is placed at"
            f" `${{{prefix_key.upper()}}}/bin/{binname}`."
            if binname
            else ""
        )
        opt_prefix: dict = {
            "type": "string",
            "default": "",
            "description": prefix_description
            or (
                "Installation prefix."
                " Resolved automatically when left empty:"
                f" `{default_root}` (root) or `{default_nonroot}` (non-root).{bin_note}"
            ),
        }
        if applies_when:
            opt_prefix["_applies_when"] = applies_when
        options[prefix_key] = opt_prefix

        # Inject symlink option (unless skip_symlink)
        if not skip_symlink:
            if symlink_key in options:
                log(
                    f"⛔ {feature_id}: option '{symlink_key}' is a derived"
                    " symlink option and cannot be manually defined in metadata.yaml",
                )
                return False
            if dir_symlink:
                symlink_desc = (
                    "Create a symlink to the installation directory"
                    f" (`${{{prefix_key.upper()}}}`)"
                    f" pointing to the standard path"
                    f" (`{default_root}` as root, `{default_nonroot}` as non-root)"
                    " when the prefix resolves to a non-default path."
                )
            elif binname:
                symlink_desc = (
                    f"Create a symlink to `{binname}` in the standard binary directory"
                    f" (`{default_root}/bin/{binname}` as root,"
                    f" `{default_nonroot}/bin/{binname}` as non-root)"
                    " when the prefix resolves to a non-default path."
                )
            else:
                symlink_desc = (
                    "Create a symlink to the installed binary"
                    " in the standard binary directory"
                    " when the prefix resolves to a non-default path."
                )
            opt: dict = {
                "type": "boolean",
                "default": True,
                "description": symlink_description or symlink_desc,
            }
            if applies_when:
                opt["_applies_when"] = applies_when
            options[symlink_key] = opt

        # Inject export_path option (unless skip_export_path)
        if not skip_export_path:
            if export_key in options:
                log(
                    f"⛔ {feature_id}: option '{export_key}' is a derived"
                    " export_path option and cannot be manually"
                    " defined in metadata.yaml",
                )
                return False
            opt = {
                "type": "array",
                "default": export_path_default,
                "description": export_path_description
                or (
                    "Write a PATH export block"
                    f' (`export PATH="${{{prefix_key.upper()}}}/{bin_dir}:$PATH"`)'
                    " to shell startup files."
                    " Set to 'auto' to write to standard profiles"
                    " (system-wide as root, user-scoped otherwise),"
                    " or provide explicit file path(s) one per line."
                    " Leave empty to skip."
                ),
            }
            if applies_when:
                opt["_applies_when"] = applies_when
            options[export_key] = opt

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


def _feature_vars(feature_id: str, owner: str, repo: str) -> dict[str, str]:
    """Return the substitution table for feature-scoped template variables.

    The following ``@@VAR@@`` tokens are recognised in ``metadata.yaml`` string
    values and expanded during :func:`load_and_augment`:

    ``@@_FEAT_SHARE_DIR@@``
        Canonical ``/usr/local/share/`` sub-directory for this feature's
        persistent artefacts (entrypoints, lifecycle hooks, config files).
        Formula: ``/usr/local/share/<owner>/<repo>/<feature_id>``.

    ``@@_EXPORT_PROFILE_D@@``
        Filename of the ``/etc/profile.d/`` drop-in for PATH export blocks.
        Formula: ``<owner>-<repo>-<feature_id>-export-path.sh``.
    """
    return {
        "_FEAT_SHARE_DIR": feat_share_dir(feature_id, owner, repo),
        "_EXPORT_PROFILE_D": export_profile_d(feature_id, owner, repo),
    }


def _substitute_vars(obj: object, vars_: dict[str, str]) -> object:
    """Recursively substitute ``@@VAR@@`` tokens in all string values of *obj*.

    Processes dicts (values only, not keys), lists, and plain strings.
    Non-string scalars (int, bool, None, …) are returned unchanged.
    """
    if isinstance(obj, str):
        for name, value in vars_.items():
            obj = obj.replace(f"@@{name}@@", value)
        return obj
    if isinstance(obj, dict):
        return {k: _substitute_vars(v, vars_) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_substitute_vars(item, vars_) for item in obj]
    return obj
