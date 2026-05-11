"""Feature sync pipeline: assembly of src/ from features/ + lib/."""

from proman.sync.file_sync import SyncStatus, remove_file, sync_file
from proman.sync.install_script import HEADER_END_MARKER, InstallScriptGenerator
from proman.sync.metadata import (
    augment_metadata,
    build_metadata_validator,
    load_all,
    load_and_augment,
    load_derived_options,
    read_metadata,
    sanitize_markdown,
    validate_metadata_schema,
)
from proman.sync.pipeline import run

__all__ = [
    "HEADER_END_MARKER",
    "InstallScriptGenerator",
    "SyncStatus",
    "augment_metadata",
    "build_metadata_validator",
    "load_all",
    "load_and_augment",
    "load_derived_options",
    "read_metadata",
    "remove_file",
    "run",
    "sanitize_markdown",
    "sync_file",
    "validate_metadata_schema",
]
