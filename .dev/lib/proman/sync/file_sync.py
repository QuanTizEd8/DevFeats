"""Single-file sync primitive: existence check, content compare, write, log.

This is the canonical helper used by every "regenerate file from source" flow
in proman.  Every status produces exactly one stderr line in a single
canonical format; callers do not format messages themselves.
"""

from __future__ import annotations

import sys
from enum import StrEnum
from typing import TYPE_CHECKING

from proman.git import git_repo_root

if TYPE_CHECKING:
    from pathlib import Path


class SyncStatus(StrEnum):
    """Outcome of a single ``sync_file`` / ``remove_file`` call."""

    CREATED = "created"
    UPDATED = "updated"
    UNCHANGED = "unchanged"
    MISSING = "missing"
    STALE = "stale"
    REMOVED = "removed"
    PENDING_REMOVAL = "pending_removal"

    @property
    def is_in_sync(self) -> bool:
        """Whether this status represents an in-sync state on disk."""
        return self not in (
            SyncStatus.MISSING,
            SyncStatus.STALE,
            SyncStatus.PENDING_REMOVAL,
        )


def sync_file(path: Path, content: str, *, check_only: bool = False) -> SyncStatus:
    """Make ``path`` contain exactly ``content``; report what (would) happen.

    Parameters
    ----------
    path
        Absolute path of the file to sync.
    content
        Desired full content of the file.
    check_only
        If True, do not write to disk; report ``MISSING`` or ``STALE`` instead
        of ``CREATED`` / ``UPDATED``.

    Returns
    -------
    SyncStatus
        The outcome of the sync.  ``status.is_in_sync`` is False iff the
        on-disk state did not already match the desired content.
    """
    if not path.exists():
        if check_only:
            status = SyncStatus.MISSING
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
            status = SyncStatus.CREATED
    elif path.read_text(encoding="utf-8") == content:
        status = SyncStatus.UNCHANGED
    elif check_only:
        status = SyncStatus.STALE
    else:
        path.write_text(content, encoding="utf-8")
        status = SyncStatus.UPDATED

    _log(path, status)
    return status


def remove_file(path: Path, *, check_only: bool = False) -> SyncStatus:
    """Remove ``path`` if present; report what (would) happen.

    Parameters
    ----------
    path
        Absolute path of the file to remove.
    check_only
        If True, do not unlink; report ``PENDING_REMOVAL`` instead of
        ``REMOVED``.

    Returns
    -------
    SyncStatus
        ``REMOVED`` after a successful unlink, ``PENDING_REMOVAL`` in
        check-only mode, or ``UNCHANGED`` if the file was already absent.
    """
    if not path.exists():
        status = SyncStatus.UNCHANGED
    elif check_only:
        status = SyncStatus.PENDING_REMOVAL
    else:
        path.unlink()
        status = SyncStatus.REMOVED

    _log(path, status)
    return status


_STATUS_MESSAGES: dict[SyncStatus, tuple[str, str]] = {
    SyncStatus.CREATED: ("✅", "created"),
    SyncStatus.UPDATED: ("✅", "updated"),
    SyncStatus.UNCHANGED: ("✅", "unchanged"),
    SyncStatus.REMOVED: ("🗑️ ", "removed"),
    SyncStatus.MISSING: ("⛔", "is missing"),
    SyncStatus.STALE: ("⛔", "is stale"),
    SyncStatus.PENDING_REMOVAL: ("⛔", "must be removed"),
}


def _log(path: Path, status: SyncStatus) -> None:
    """Emit one stderr line in the canonical format for this status."""
    icon, suffix = _STATUS_MESSAGES[status]
    try:
        rel = path.relative_to(git_repo_root())
    except ValueError:
        rel = path
    print(f"{icon} {rel} {suffix}", file=sys.stderr)
