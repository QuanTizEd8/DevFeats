"""Per-feature paths and filenames resolved from metadata (single source of truth).

Values under ``_env_vars`` come from the same :class:`~proman.metadata.MetadataLoader`
pipeline that generates ``install.bash`` (``metadata.shared.yaml`` templates filled
with project config).  Keys in ``_env_vars`` ARE the final bash variable names
(e.g. ``_FEAT_SHARE_DIR_ROOT``); no renaming occurs.  Test runners and codegen
use :func:`resolved_env_vars` to inject them verbatim so install scripts and tests
always share an identical variable set.

:func:`activation_profile_d_filename` is kept separately because it varies by
prefix-group ``stem`` and is used by :mod:`~proman.sync.install_script` for
multi-stem generation; the ``prefix`` stem value is already in ``_env_vars`` as
``_FEAT_ACTIVATION_PROFILE_D_FILE``.
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
    """Return filled ``_env_vars`` for *feature_id* (same values as install.bash).

    Keys are the final bash variable names (e.g. ``_FEAT_SHARE_DIR_ROOT``).
    """
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


def activation_profile_d_filename(feature_id: str, stem: str = "prefix") -> str:
    """Profile.d basename for prefix-group activation snippets (varies by stem).

    Used by :mod:`~proman.sync.install_script` for multi-stem generation.
    The default ``prefix`` stem value is also in ``_env_vars`` as
    ``_FEAT_ACTIVATION_PROFILE_D_FILE``.
    """
    cfg = load_config()
    return f"{cfg['owner_slug']}-{cfg['name_slug']}-{feature_id}-{stem}-activation.sh"


def clear_caches() -> None:
    """Clear memoized metadata (for tests that patch project config)."""
    resolved_env_vars.cache_clear()
    _metadata_loader.cache_clear()
