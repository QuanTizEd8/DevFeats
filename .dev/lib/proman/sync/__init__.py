"""Feature sync pipeline: assembly of src/ from features/ + lib/."""

from proman.sync.file_sync import SyncStatus, remove_file, sync_file
from proman.sync.install_script import InstallScriptGenerator
from proman.sync.metadata import (
    build_metadata_validator,
    sanitize_markdown,
    validate_metadata_schema,
)
from proman.sync.pipeline import run

__all__ = [
    "InstallScriptGenerator",
    "SyncStatus",
    "build_metadata_validator",
    "remove_file",
    "run",
    "sanitize_markdown",
    "sync_file",
    "validate_metadata_schema",
]
