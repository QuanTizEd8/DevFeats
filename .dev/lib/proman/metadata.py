"""Feature metadata: read, augment, and enumerate metadata.yaml files.

This is the single authoritative source for loading feature metadata.
It is consumed by the sync pipeline, the docs pipeline, and CLI commands.
"""

import pyserials
from jsonschema.exceptions import ValidationError

from proman.config import load as load_config
from proman.schema_bundle import get_validator


class MetadataLoader:
    """Feature metadata loader."""

    def __init__(self) -> None:
        self._config = load_config()
        self._feat_dirpath = self._config.absolute_path("path.features")
        self._feat_metadata_filename = str(self._config["filename.feature_metadata"])
        self._shared_metadata = pyserials.read.yaml_from_file(
            self._config.absolute_path("path.shared_metadata")
        )
        self._schema_validator = get_validator()

    def load(self, *feat_ids: str) -> dict[str, dict]:
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
                msg = f"Error loading metadata for feature '{feat_id}': {e}"
                raise ValueError(msg) from e

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
            msg = (
                f"Metadata file not found for feature '{feature_id}':"
                f" {metadata_filepath}"
            )
            raise FileNotFoundError(msg)

        try:
            metadata: dict = pyserials.read.yaml_from_file(metadata_filepath)
        except Exception as e:
            msg = f"Error reading metadata.yaml for feature '{feature_id}': {e}"
            raise ValueError(msg) from e

        if not isinstance(metadata, dict):
            msg = f"Metadata for feature '{feature_id}' is not a YAML mapping (dict)."
            raise TypeError(msg)

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
            msg = (
                f"Error substituting variables in metadata for feature"
                f" '{feature_id}': {e}"
            )
            raise ValueError(msg) from e
        metadata.pop("_project")

        self._validate_schema(metadata)

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
                msg = (
                    f"Error substituting variables in _apply_when condition"
                    f" for option '{option_id}': {e}"
                )
                raise ValueError(msg) from e

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
            lines.extend(
                f"    ↳ {_schema_error_path(sub)}: {sub.message}"
                for sub in sorted(
                    err.context, key=lambda e: (list(e.absolute_path), e.message)
                )
            )
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


def _schema_error_path(err: ValidationError) -> str:
    """Return a human-readable instance path for a jsonschema validation error."""
    if err.json_path and err.json_path != "$":
        return err.json_path
    if err.absolute_path:
        return " → ".join(str(part) for part in err.absolute_path)
    return "(root)"
