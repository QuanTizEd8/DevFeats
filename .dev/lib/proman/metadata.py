"""Feature metadata: read, augment, and enumerate metadata.yaml files.

This is the single authoritative source for loading feature metadata.
It is consumed by the sync pipeline, the docs pipeline, and CLI commands.
"""

import pyserials

from proman.config import load as load_config
from proman.helpers import log
from proman.schema_bundle import get_validator


class MetadataLoader:
    """Feature metadata loader."""

    def __init__(self):
        self._config = load_config()
        self._feat_dirpath = self._config.absolute_path("path.features")
        self._feat_metadata_filename = str(self._config["filename.feature_metadata"])
        self._shared_metadata = pyserials.read.yaml_from_file(
            self._config.absolute_path("path.shared_metadata")
        )
        self._schema_validator = get_validator()
        return

    def load(self, *feat_ids) -> dict[str, dict]:
        """Load and augment metadata for all features found in *features_dirpath*.

        Features whose ``metadata.yaml`` is missing or fails augmentation are
        skipped with a warning and omitted from the result.

        Returns
        -------
        dict[str, dict]
            Mapping of ``feature_id`` → fully augmented metadata dict.
        """
        feat_ids = feat_ids or [
            metadata_path.parent.name
            for metadata_path in self._feat_dirpath.glob(
                f"*/{self._feat_metadata_filename}"
            )
        ]

        all_metadata: dict[str, dict] = {}

        for feat_id in feat_ids:
            try:
                metadata = self._load_one(feat_id)
            except Exception as e:
                raise ValueError(
                    f"Error loading metadata for feature '{feat_id}': {e}"
                ) from e

            all_metadata[feat_id] = metadata

        return all_metadata

    def _load_one(self, feature_id: str) -> dict:
        """Read and fully augment metadata for a single feature; return None on failure.

        Augmentation steps performed (in order):
        1. Read ``metadata.yaml`` from disk.
        2. Substitute feature-scoped variables (e.g. ``@@_FEAT_SHARE_DIR@@``,
        ``@@PROJECT_NAMESPACE@@``) in all string dict keys and values.
        See :func:`_feature_vars` for the full variable table.
        3. Normalize lifecycle command map keys with
        :func:`normalize_lifecycle_command_keys`
        (``<owner>-<repo>--<feature_id>--…``).
        4. Merge shared metadata.
        5. Set ``metadata["id"]`` and ``metadata["_oci_ref"]``.
        """
        metadata_filepath = (
            self._feat_dirpath / feature_id / self._feat_metadata_filename
        )
        if not metadata_filepath.is_file():
            raise FileNotFoundError(
                f"Metadata file not found for feature '{feature_id}': {metadata_filepath}"
            )

        try:
            metadata: dict = pyserials.read.yaml_from_file(metadata_filepath)
        except Exception as e:
            raise ValueError(
                f"Error reading metadata.yaml for feature '{feature_id}': {e}"
            ) from e

        if not isinstance(metadata, dict):
            raise ValueError(
                f"Metadata for feature '{feature_id}' is not a YAML mapping (dict)."
            )

        metadata["id"] = feature_id
        metadata["_project"] = self._config

        pyserials.update.recursive_update(
            source=metadata,
            addon=self._shared_metadata,
        )

        self._normalize_lifecycle_keys(metadata)
        metadata["options"] = self._filter_options(metadata)

        try:
            metadata = pyserials.update.TemplateFiller().fill(metadata)
        except Exception as e:
            raise ValueError(
                f"Error substituting variables in metadata for feature '{feature_id}': {e}"
            ) from e

        self._validate_schema(metadata)

        prefix_groups = metadata.get("_prefix_groups", {})
        for group_id, group_cfg in prefix_groups.items():
            _inject_prefix_group_options(group_id, group_cfg, metadata["options"])

        metadata.pop("_project")

        return metadata

    def _filter_options(self, metadata: dict) -> dict:
        """Merge shared metadata into *metadata*.

        Options tagged with ``_apply_when`` are only merged when the condition
        evaluates to ``True`` against the feature's full metadata dict.

        Returns
        -------
        bool
            ``True`` on success, ``False`` if a conflict with a derived option is
            detected (error is logged).
        """
        final_options: dict = {}
        for option_id, option_def in metadata.get("options", {}).items():
            condition = option_def.get("_apply_when")

            if not condition:
                final_options[option_id] = option_def
                continue

            try:
                should_apply = pyserials.update.TemplateFiller().fill(
                    metadata,
                    condition,
                )
            except Exception as e:
                raise ValueError(
                    f"Error substituting variables in _apply_when condition for option '{option_id}': {e}"
                ) from e

            if should_apply:
                final_options[option_id] = option_def

        return final_options

    def _validate_schema(self, metadata: dict) -> None:
        """Validate metadata against the JSON schema.

        Logs all validation errors and returns False on failure.
        """
        errs = sorted(
            self._schema_validator.iter_errors(metadata),
            key=lambda e: list(e.absolute_path),
        )
        if errs:
            error_paths = []
            for err in errs:
                path = (
                    " → ".join(str(p) for p in err.absolute_path)
                    if err.absolute_path
                    else "(root)"
                )
                error_paths.append(path)
            raise ValueError(
                f"Metadata validation failed with {len(errs)} error(s) at paths: "
                + ", ".join(error_paths)
            )
        return

    def _normalize_lifecycle_keys(self, metadata: dict) -> None:
        """Rewrite lifecycle hook map keys to ``<owner>-<repo>--<feature_id>--<task>``.

        *metadata* is updated in place. For each key in :data:`LIFECYCLE_COMMAND_KEYS`,
        if the value is a mapping, every string key ``k`` becomes:

        * ``prefix + suffix`` when ``k`` already contains the legacy segment
        ``--<feature_id>--`` (any project slug before it is dropped), or
        * ``prefix + k`` when there is no such segment (short task id in YAML).

        where ``prefix`` is :func:`proman.const.lifecycle_command_entry_prefix`.

        Keys that already start with *prefix* are left unchanged (idempotent).
        """
        lifecycle_keys: list[str] = self._config["features.lifecycle_hook_keys"]
        key_prefix = metadata["_lifecycle_key_prefix"]
        for lifecycle_key in lifecycle_keys:
            if lifecycle_key not in metadata:
                continue
            block = metadata[lifecycle_key]
            new_block: dict[str, dict] = {}
            for entry_id, entry in block.items():
                full_key = f"{key_prefix}{entry_id}"
                new_block[full_key] = entry
            metadata[lifecycle_key] = new_block
        return


def _inject_prefix_group_options(  # noqa: PLR0911
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
        raise ValueError(
            f"⛔ Option '{prefix_key}' is a derived prefix option and"
            " cannot be manually defined in metadata.yaml",
        )

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
