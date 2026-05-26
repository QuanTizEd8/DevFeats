"""Per-feature paths and filenames resolved from metadata (single source of truth).

Values under ``_env_vars`` come from the same :class:`~proman.metadata.MetadataLoader`
pipeline that generates ``install.bash`` (``metadata.shared.yaml`` templates filled
with project config).  Test runners and codegen should use these accessors instead of
duplicating path formulas.

Activation profile.d basenames are not in ``_env_vars`` (they vary by prefix-group
``stem``); :func:`activation_profile_d_filename` is the shared definition used by
:mod:`~proman.sync.install_script` and tests.
"""

from __future__ import annotations

from functools import lru_cache

from proman.config import load as load_config
from proman.metadata import MetadataLoader


@lru_cache(maxsize=1)
def _metadata_loader() -> MetadataLoader:
    return MetadataLoader()


@lru_cache(maxsize=256)
def resolved_env_vars(feature_id: str) -> dict[str, str]:
    """Return filled ``_env_vars`` for *feature_id* (same values as install.bash)."""
    metadata = _metadata_loader().load(feature_id)[feature_id]
    raw = metadata.get("_env_vars")
    if not isinstance(raw, dict):
        msg = f"Feature {feature_id!r}: _env_vars missing or not a mapping"
        raise KeyError(msg)
    out: dict[str, str] = {}
    for key, value in raw.items():
        if not isinstance(value, str):
            msg = (
                f"Feature {feature_id!r}: _env_vars[{key!r}] must be str after fill, "
                f"got {type(value).__name__}"
            )
            raise TypeError(msg)
        out[key] = value
    return out


def share_dir_root(feature_id: str) -> str:
    """Root share directory (``share_dir_root`` in ``metadata.shared.yaml``)."""
    return resolved_env_vars(feature_id)["share_dir_root"]


def shell_profile_d_filename(feature_id: str) -> str:
    """``/etc/profile.d`` drop-in basename (``shell_profile_d_filename`` in metadata)."""
    return resolved_env_vars(feature_id)["shell_profile_d_filename"]


def activation_profile_d_filename(feature_id: str, stem: str = "prefix") -> str:
    """Profile.d basename for prefix-group activation snippets."""
    cfg = load_config()
    return f"{cfg['owner_slug']}-{cfg['name_slug']}-{feature_id}-{stem}-activation.sh"


def clear_caches() -> None:
    """Clear memoized metadata (for tests that patch project config)."""
    resolved_env_vars.cache_clear()
    _metadata_loader.cache_clear()
