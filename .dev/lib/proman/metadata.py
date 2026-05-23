"""Feature metadata: read, augment, and enumerate metadata.yaml files.

This is the single authoritative source for loading feature metadata.
It is consumed by the sync pipeline, the docs pipeline, and CLI commands.

Augmented keys added by this module (prefixed with ``_`` for internal use):
    ``id``       — feature directory name (e.g. ``install-git``)
    ``_oci_ref`` — OCI image reference (e.g. ``ghcr.io/owner/repo/install-git``)
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Literal

import yaml
import pyserials

from proman.const import (
    LIFECYCLE_COMMAND_KEYS,
    export_profile_d,
    feat_share_dir,
    lifecycle_command_entry_prefix,
    project_slug,
)
from proman.git import git_owner_repo
from proman.helpers import log

if TYPE_CHECKING:
    from pathlib import Path


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
        try:
            metadata = load_one(feat_id, features_dirpath)
        except Exception as e:
            raise ValueError(
                f"Error loading metadata for feature '{feat_id}': {e}"
            ) from e
        if metadata is None:
            log(f"⚠️  load_all: skipping {feat_id} (metadata load/augment failed)")
            continue
        all_metadata[feat_id] = metadata
    return all_metadata


def load_one(feature_id: str, features_dirpath: Path) -> dict | None:
    """Read and fully augment metadata for a single feature; return None on failure.

    Augmentation steps performed (in order):
    1. Read ``metadata.yaml`` from disk.
    2. Substitute feature-scoped variables (e.g. ``@@_FEAT_SHARE_DIR@@``,
       ``@@PROJECT_NAMESPACE@@``) in all string dict keys and values.
       See :func:`_feature_vars` for the full variable table.
    3. Normalize lifecycle command map keys with
       :func:`normalize_lifecycle_command_keys`
       (``<owner>-<repo>--<feature_id>--…``).
    4. Merge shared options from ``features/shared-options.yaml``.
    5. Set ``metadata["id"]`` and ``metadata["_oci_ref"]``.
    """
    derived_options = load_derived_options(features_dirpath)
    metadata = read_metadata(feature_id, features_dirpath)
    if not isinstance(metadata, dict):
        return None
    owner, repo_name = git_owner_repo()
    metadata = _substitute_vars(metadata, _feature_vars(feature_id, owner, repo_name))
    normalize_lifecycle_command_keys(metadata, feature_id, owner, repo_name)
    if not augment_metadata(feature_id, metadata, derived_options):
        return None
    metadata["id"] = feature_id
    metadata["_oci_ref"] = f"ghcr.io/{owner}/{repo_name}/{feature_id}"
    return metadata


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
            sanitized_option_dict = {
                k: v for k, v in option_def.items() if not k.startswith("_")
            }
            try:
                filled_option_dict = pyserials.update.TemplateFiller().fill(
                    data=metadata,
                    template=sanitized_option_dict,
                )
            except Exception as e:
                raise ValueError(
                    f"Error processing shared option '{option_id}' for feature '{feature_id}': {e}"
                ) from e
            options[option_id] = filled_option_dict
    metadata["options"] = options
    return True


def _inject_group_options(  # noqa: PLR0911
    feature_id: str,
    group_id: str,
    group_cfg: dict,
    options: dict,
) -> bool:
    """Inject generated options for a single ``_prefix_groups`` entry."""
    _default_root = "/usr/local"
    _default_nonroot = "${HOME}/.local"
    _default_symlink_root = "/usr/local/bin"
    _default_symlink_nonroot = "${HOME}/.local/bin"

    prefix_cfg: dict = group_cfg.get("prefix", {})
    symlink_cfg: dict = group_cfg.get("symlink", {})
    exports_cfg: dict = group_cfg.get("exports", {})
    activation_cfg: dict | None = group_cfg.get("activation")

    default_root: str = prefix_cfg.get("root", _default_root)
    default_nonroot: str = prefix_cfg.get("nonroot", _default_nonroot)
    option_name: str | None = group_cfg.get("option_name")
    skip_symlink: bool = symlink_cfg.get("skip", False)
    skip_exports: bool = exports_cfg.get("skip", False)
    applies_when: list | None = group_cfg.get("applies_when")
    prefix_description: str | None = prefix_cfg.get("description")
    symlink_description: str | None = symlink_cfg.get("description")
    exports_description: str | None = exports_cfg.get("description")

    bins: list[str] = prefix_cfg.get("bins", [])
    bin_dir: str = prefix_cfg.get("bin_dir", "bin")
    symlink_root: str = symlink_cfg.get("root", _default_symlink_root)
    symlink_nonroot: str = symlink_cfg.get("nonroot", _default_symlink_nonroot)

    stem = option_name or (f"{group_id}_prefix" if group_id else "prefix")
    prefix_key = stem
    discovery_key = f"{stem}_discovery"
    symlinks_key = f"{stem}_symlinks"
    exports_key = f"{stem}_exports"
    activations_key = f"{stem}_activations"

    # Inject prefix option
    if prefix_key in options:
        log(
            f"⛔ {feature_id}: option '{prefix_key}' is a derived prefix option and"
            " cannot be manually defined in metadata.yaml",
        )
        return False
    if bins:
        bin_list = ", ".join(f"`{b}`" for b in bins)
        bin_note = (
            f" Binaries ({bin_list}) are placed at"
            f" `${{{prefix_key.upper()}}}/{bin_dir}/`."
        )
    else:
        bin_note = ""
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

    # Inject discovery option (when at least one of symlinks/exports is active)
    if not (skip_symlink and skip_exports):
        if discovery_key in options:
            log(
                f"⛔ {feature_id}: option '{discovery_key}' is a derived"
                " discovery option and cannot be manually defined in metadata.yaml",
            )
            return False
        if bins:
            bins_label = "/".join(f"`{b}`" for b in bins)
            disc_intro = f"Controls how {bins_label} is made discoverable on PATH."
        else:
            disc_intro = "Controls PATH discoverability for this installation."
        opt_disc: dict = {
            "type": "string",
            "default": "auto",
            "description": (
                f"{disc_intro}"
                " `auto` (default): if the install directory is already on PATH,"
                " does nothing; otherwise creates symlinks when viable, or writes"
                " a PATH export block."
                " `symlink`: create symlinks only (suppresses PATH export)."
                " `shell`: write PATH export only (suppresses symlinks)."
                " `all`: both symlinks and PATH export unconditionally."
                " `none`: skip everything."
            ),
            "enum": [
                {
                    "value": "auto",
                    "description": (
                        "Smart detection: skip if already on PATH; otherwise"
                        " use symlinks when viable, PATH export as fallback."
                    ),
                },
                {
                    "value": "symlink",
                    "description": "Create symlinks only; suppress PATH export.",
                },
                {
                    "value": "shell",
                    "description": "Write PATH export to shell startup files only;"
                    " suppress symlinks.",
                },
                {
                    "value": "all",
                    "description": "Create symlinks and write PATH export"
                    " unconditionally.",
                },
                {
                    "value": "none",
                    "description": "Skip both symlinks and PATH export.",
                },
            ],
        }
        if applies_when:
            opt_disc["_applies_when"] = applies_when
        options[discovery_key] = opt_disc

    # Inject symlinks option (unless skip_symlink)
    if not skip_symlink:
        if symlinks_key in options:
            log(
                f"⛔ {feature_id}: option '{symlinks_key}' is a derived"
                " symlinks option and cannot be manually defined in metadata.yaml",
            )
            return False
        _dflt = (
            f" Defaults to `{symlink_root}` (root) or `{symlink_nonroot}` (non-root)."
        )
        _hint = (
            " Provide explicit target directories one per line to override."
            f" Use `{discovery_key}=none` to skip symlink creation entirely."
        )
        if bins:
            if len(bins) == 1:
                symlink_desc = (
                    f"Target directory for the `{bins[0]}` symlink." + _dflt + _hint
                )
            else:
                bin_list = ", ".join(f"`{b}`" for b in bins)
                symlink_desc = (
                    f"Target directory for {bin_list} symlinks." + _dflt + _hint
                )
        else:
            symlink_desc = "Target directory for binary symlinks." + _dflt + _hint
        opt: dict = {
            "type": "array",
            "default": "",
            "description": symlink_description or symlink_desc,
        }
        if applies_when:
            opt["_applies_when"] = applies_when
        options[symlinks_key] = opt

    # Inject exports option (unless skip_exports)
    if not skip_exports:
        if exports_key in options:
            log(
                f"⛔ {feature_id}: option '{exports_key}' is a derived"
                " exports option and cannot be manually"
                " defined in metadata.yaml",
            )
            return False
        opt = {
            "type": "array",
            "default": "",
            "description": exports_description
            or (
                "Shell startup files to write a PATH export block"
                f' (`export PATH="${{{prefix_key.upper()}}}/{bin_dir}:$PATH"`) to.'
                " Leave empty (default) to write to standard profiles"
                " (system-wide as root, user-scoped otherwise),"
                " or provide explicit file path(s) one per line."
                f" Use `{discovery_key}=none` to skip PATH export entirely."
            ),
        }
        if applies_when:
            opt["_applies_when"] = applies_when
        options[exports_key] = opt

    # Inject activations option (when activation: is present)
    if activation_cfg:
        shells: list[str] = activation_cfg.get("shells", [])
        act_description: str | None = activation_cfg.get("description")
        if activations_key in options:
            log(
                f"⛔ {feature_id}: option '{activations_key}' is a derived"
                " activations option and cannot be manually defined"
                " in metadata.yaml",
            )
            return False
        opt = {
            "type": "array",
            "default": "\n".join(shells),
            "description": act_description
            or (
                "Shell names to write activation snippets for"
                " (e.g. `bash`, `zsh`)."
                " Leave empty to skip all activation writes."
            ),
            "enum": [
                {"value": s, "description": f"Write activation snippet for {s}."}
                for s in ["bash", "zsh"]
            ],
        }
        if applies_when:
            opt["_applies_when"] = applies_when
        options[activations_key] = opt

    # Inject write_group and write_users options (when write_group: is present)
    write_group_cfg: dict | None = group_cfg.get("write_group")
    if write_group_cfg is not None:
        wg_default: str = write_group_cfg.get("default", "")
        if group_id:
            wg_key = f"{group_id}_write_group"
            wu_key = f"{group_id}_write_users"
        else:
            wg_key = "write_group"
            wu_key = "write_users"
        if wg_key in options:
            log(
                f"⛔ {feature_id}: option '{wg_key}' is a derived write_group"
                " option and cannot be manually defined in metadata.yaml",
            )
            return False
        if wu_key in options:
            log(
                f"⛔ {feature_id}: option '{wu_key}' is a derived write_users"
                " option and cannot be manually defined in metadata.yaml",
            )
            return False
        opt_wg: dict = {
            "type": "string",
            "default": wg_default,
            "description": (
                "OS group for shared write access to the installation prefix."
                " Non-empty: create this group (if absent), add all resolved"
                " users to it, and apply group-write bits so group members can"
                " install packages. Empty: skip group setup."
            ),
        }
        if applies_when:
            opt_wg["_applies_when"] = applies_when
        options[wg_key] = opt_wg
        opt_wu: dict = {
            "type": "array",
            "default": "",
            "description": (
                "Users to add to the write-permission group."
                " Empty (default): auto-discover (current user, remoteUser,"
                " containerUser). Non-empty: use exactly these users;"
                " auto-discovery is skipped."
            ),
        }
        if applies_when:
            opt_wu["_applies_when"] = applies_when
        options[wu_key] = opt_wu

    return True


def _inject_prefix_options(feature_id: str, metadata: dict) -> bool:
    """Inject generated options for each ``_prefix_groups`` entry."""
    prefix_groups = metadata.get("_prefix_groups")
    if not prefix_groups:
        return True

    options: dict = metadata["options"]

    for group_id, group_cfg in prefix_groups.items():
        if not _inject_group_options(feature_id, group_id, group_cfg, options):
            return False

    # Inject a single feature-level runtime_path option when at least one group
    # has discovery enabled. It is shared across all groups.
    has_discovery = any(
        not (
            g.get("symlink", {}).get("skip", False)
            and g.get("exports", {}).get("skip", False)
        )
        for g in prefix_groups.values()
    )
    if has_discovery:
        runtime_path_key = "runtime_path"
        if runtime_path_key in options:
            log(
                f"⛔ {feature_id}: option '{runtime_path_key}' is a derived"
                " runtime_path option and cannot be manually defined in metadata.yaml",
            )
            return False
        options[runtime_path_key] = {
            "type": "string",
            "default": "",
            "description": (
                "Colon-separated directories guaranteed to be on PATH at runtime"
                " (e.g. `/usr/local/bin:/usr/bin:/bin`)."
                " When set, the discovery step uses this value to decide whether"
                " the installation directory is already reachable."
                " Leave empty (default) to check `$PATH` at install time instead."
            ),
        }

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
    - Dot notation for object properties: ``options.runtime_path`` → ``data["options"]["runtime_path"]``

    Returns
    -------
    exists
        Whether the path exists in the metadata dict.
    value
        The value at the path if it exists, or ``None`` if it does not.
    """
    path_parts = jsonpath.split(".")
    current = data
    for part in path_parts:
        if not isinstance(current, dict) or part not in current:
            return False, None
        current = current[part]
    return True, current


def _feature_vars(feature_id: str, owner: str, repo: str) -> dict[str, str]:
    """Return the substitution table for feature-scoped template variables.

    The following ``@@VAR@@`` tokens are recognised in ``metadata.yaml`` string
    dict keys and values and expanded during :func:`load_one`:

    ``@@_FEAT_SHARE_DIR@@``
        Canonical ``/usr/local/share/`` sub-directory for this feature's
        persistent artefacts (entrypoints, lifecycle hooks, config files).
        Formula: ``/usr/local/share/<owner>/<repo>/<feature_id>``.

    ``@@_EXPORT_PROFILE_D@@``
        Filename of the ``/etc/profile.d/`` drop-in for PATH export blocks.
        Formula: ``<owner>-<repo>-<feature_id>-export-path.sh``.

    ``@@PROJECT_OWNER@@``
        GitHub-style owner slug (same as the first component of ``_oci_ref``).

    ``@@PROJECT_NAME@@``
        Repository name slug (same as the second component of ``_oci_ref``).

    ``@@PROJECT_NAMESPACE@@``
        ``<owner>/<repo>`` string (not a filesystem path).

    ``@@PROJECT_SLUG@@``
        ``<owner>-<repo>`` string (hyphen separator).
    """
    return {
        "_FEAT_SHARE_DIR": feat_share_dir(feature_id, owner, repo),
        "_EXPORT_PROFILE_D": export_profile_d(feature_id, owner, repo),
        "PROJECT_OWNER": owner,
        "PROJECT_NAME": repo,
        "PROJECT_NAMESPACE": f"{owner}/{repo}",
        "PROJECT_SLUG": project_slug(owner, repo),
    }


def _canonical_lifecycle_entry_id(entry_id: str, prefix: str, marker: str) -> str:
    """Return the fully-qualified lifecycle command key for *entry_id*."""
    if entry_id.startswith(prefix):
        return entry_id
    if marker in entry_id:
        _before, _sep, suffix = entry_id.partition(marker)
        if _sep:
            return f"{prefix}{suffix}"
    return f"{prefix}{entry_id}"


def normalize_lifecycle_command_keys(
    metadata: dict,
    feature_id: str,
    owner: str,
    repo: str,
) -> None:
    """Rewrite lifecycle hook map keys to ``<owner>-<repo>--<feature_id>--<task>``.

    *metadata* is updated in place. For each key in :data:`LIFECYCLE_COMMAND_KEYS`,
    if the value is a mapping, every string key ``k`` becomes:

    * ``prefix + suffix`` when ``k`` already contains the legacy segment
      ``--<feature_id>--`` (any project slug before it is dropped), or
    * ``prefix + k`` when there is no such segment (short task id in YAML).

    where ``prefix`` is :func:`proman.const.lifecycle_command_entry_prefix`.

    Keys that already start with *prefix* are left unchanged (idempotent).
    """
    prefix = lifecycle_command_entry_prefix(feature_id, owner, repo)
    marker = f"--{feature_id}--"
    for lc_key in LIFECYCLE_COMMAND_KEYS:
        block = metadata.get(lc_key)
        if not isinstance(block, dict) or not block:
            continue
        new_block: dict[object, object] = {}
        for entry_id, entry in block.items():
            if not isinstance(entry_id, str):
                new_block[entry_id] = entry
                continue
            canon = _canonical_lifecycle_entry_id(entry_id, prefix, marker)
            new_block[canon] = entry
        metadata[lc_key] = new_block


def _substitute_var_tokens(s: str, vars_: dict[str, str]) -> str:
    """Replace every ``@@NAME@@`` in *s* using *vars_* (non-recursive)."""
    for name, value in vars_.items():
        s = s.replace(f"@@{name}@@", value)
    return s


def _substitute_vars(obj: object, vars_: dict[str, str]) -> object:
    """Recursively substitute ``@@VAR@@`` tokens in all string keys and values of *obj*.

    Processes dicts (string keys and values), lists, and plain strings.
    Non-string dict keys are preserved. Non-string scalars (int, bool, None, …)
    are returned unchanged.
    """
    if isinstance(obj, str):
        return _substitute_var_tokens(obj, vars_)
    if isinstance(obj, dict):
        out: dict[object, object] = {}
        for k, v in obj.items():
            nk = _substitute_var_tokens(k, vars_) if isinstance(k, str) else k
            out[nk] = _substitute_vars(v, vars_)
        return out
    if isinstance(obj, list):
        return [_substitute_vars(item, vars_) for item in obj]
    return obj
