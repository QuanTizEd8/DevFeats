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
            for metadata_path in sorted(
                self._feat_dirpath.glob(f"*/{self._feat_metadata_filename}")
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
        2. Substitute ``${{ … }}$`` template variables (project paths, env vars, …)
        in all string dict keys and values via :class:`pyserials.update.TemplateFiller`.
        3. Normalize lifecycle command map keys to
        ``<owner_slug>-<name_slug>--<feature_id>--<task>``.
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
        metadata["_project"] = self._config.asdict

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
        metadata.pop("_project")
        prefix_option_templates = metadata.pop("_prefix_option_templates", {})

        self._validate_schema(metadata)

        prefix_groups = metadata.get("_prefix_groups", {})
        for group_id, group_cfg in prefix_groups.items():
            _inject_prefix_group_options(
                feature_id,
                group_id,
                group_cfg,
                metadata["options"],
                prefix_option_templates,
            )

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
                final_options[option_id] = {
                    k: v for k, v in option_def.items() if k != "_apply_when"
                }

        return final_options

    def _validate_schema(self, metadata: dict) -> None:
        """Validate metadata against the JSON schema.

        Raises :class:`ValueError` with all validation errors on failure.
        """
        errs = sorted(
            self._schema_validator.iter_errors(metadata),
            key=lambda e: (list(e.absolute_path), e.message),
        )
        if not errs:
            return

        lines = [f"Metadata validation failed with {len(errs)} error(s):"]
        for err in errs:
            lines.append(f"  • {_schema_error_path(err)}: {err.message}")
            for sub in sorted(
                err.context, key=lambda e: (list(e.absolute_path), e.message)
            ):
                lines.append(f"    ↳ {_schema_error_path(sub)}: {sub.message}")
        raise ValueError("\n".join(lines))

    def _normalize_lifecycle_keys(self, metadata: dict) -> None:
        """Rewrite lifecycle hook map keys to ``<prefix><task>``.

        *metadata* is updated in place. ``prefix`` comes from shared metadata
        (``_lifecycle_key_prefix``, e.g. ``quantized8-devfeats--``). Short YAML
        keys such as ``run`` become ``quantized8-devfeats--run``.
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


def _schema_error_path(err) -> str:
    """Return a human-readable instance path for a jsonschema validation error."""
    if err.json_path and err.json_path != "$":
        return err.json_path
    if err.absolute_path:
        return " → ".join(str(part) for part in err.absolute_path)
    return "(root)"


def _inject_one_option(
    feature_id: str,
    kind: str,
    key: str,
    opt: dict,
    options: dict,
    applies_when: list | None,
) -> bool:
    """Check for a key collision, apply applies_when, and inject into options."""
    if key in options:
        log(
            f"⛔ {feature_id}: option '{key}' is a derived {kind} option"
            " and cannot be manually defined in metadata.yaml",
        )
        return False
    if applies_when:
        opt = {**opt, "_applies_when": applies_when}
    options[key] = opt
    return True


def _inject_prefix_group_options(
    feature_id: str,
    group_id: str,
    group_cfg: dict,
    options: dict,
    prefix_option_templates: dict,
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

    # Substitution values for description templates.
    if bins:
        bin_list = ", ".join(f"`{b}`" for b in bins)
        bin_note = (
            f" Binaries ({bin_list}) are placed at"
            f" `${{{prefix_key.upper()}}}/{bin_dir}/`."
        )
        bins_label = "/".join(f"`{b}`" for b in bins)
        disc_intro = f"Controls how {bins_label} is made discoverable on PATH."
        symlink_subject = (
            f"Target directory for the `{bins[0]}` symlink."
            if len(bins) == 1
            else f"Target directory for {bin_list} symlinks."
        )
    else:
        bin_note = ""
        disc_intro = "Controls PATH discoverability for this installation."
        symlink_subject = "Target directory for binary symlinks."
    subs = {
        "default_root": default_root,
        "default_nonroot": default_nonroot,
        "bin_note": bin_note,
        "disc_intro": disc_intro,
        "symlink_subject": symlink_subject,
        "symlink_root": symlink_root,
        "symlink_nonroot": symlink_nonroot,
        "discovery_key": discovery_key,
        "prefix_var_ref": f"${{{prefix_key.upper()}}}",
        "bin_dir": bin_dir,
    }

    # Inject prefix option (raises ValueError on collision — schema violation).
    if prefix_key in options:
        raise ValueError(
            f"⛔ Option '{prefix_key}' is a derived prefix option and"
            " cannot be manually defined in metadata.yaml",
        )
    opt_prefix = dict(prefix_option_templates["prefix"])
    opt_prefix["description"] = prefix_description or opt_prefix[
        "description"
    ].format_map(subs)
    if applies_when:
        opt_prefix["_applies_when"] = applies_when
    options[prefix_key] = opt_prefix

    # Inject discovery option (when at least one of symlinks/exports is active).
    if not (skip_symlink and skip_exports):
        opt_disc = dict(prefix_option_templates["discovery"])
        opt_disc["description"] = opt_disc["description"].format_map(subs)
        if not _inject_one_option(
            feature_id, "discovery", discovery_key, opt_disc, options, applies_when
        ):
            return False

    # Inject symlinks option (unless skip_symlink).
    if not skip_symlink:
        opt_symlinks = dict(prefix_option_templates["symlinks"])
        opt_symlinks["description"] = symlink_description or opt_symlinks[
            "description"
        ].format_map(subs)
        if not _inject_one_option(
            feature_id, "symlinks", symlinks_key, opt_symlinks, options, applies_when
        ):
            return False

    # Inject exports option (unless skip_exports).
    if not skip_exports:
        opt_exports = dict(prefix_option_templates["exports"])
        opt_exports["description"] = exports_description or opt_exports[
            "description"
        ].format_map(subs)
        if not _inject_one_option(
            feature_id, "exports", exports_key, opt_exports, options, applies_when
        ):
            return False

    # Inject activations option (when activation: is present).
    if activation_cfg:
        shells: list[str] = activation_cfg.get("shells", [])
        act_description: str | None = activation_cfg.get("description")
        opt_activations = dict(prefix_option_templates["activations"])
        opt_activations["default"] = "\n".join(shells)
        if act_description:
            opt_activations["description"] = act_description
        if not _inject_one_option(
            feature_id,
            "activations",
            activations_key,
            opt_activations,
            options,
            applies_when,
        ):
            return False

    # Inject write_group and write_users options (when write_group: is present).
    write_group_cfg: dict | None = group_cfg.get("write_group")
    if write_group_cfg is not None:
        wg_default: str = write_group_cfg.get("default", "")
        if group_id:
            wg_key = f"{group_id}_write_group"
            wu_key = f"{group_id}_write_users"
        else:
            wg_key = "write_group"
            wu_key = "write_users"
        opt_wg = dict(prefix_option_templates["write_group"])
        opt_wg["default"] = wg_default
        if not _inject_one_option(
            feature_id, "write_group", wg_key, opt_wg, options, applies_when
        ):
            return False
        opt_wu = dict(prefix_option_templates["write_users"])
        if not _inject_one_option(
            feature_id, "write_users", wu_key, opt_wu, options, applies_when
        ):
            return False

    return True
