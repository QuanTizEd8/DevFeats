"""Shared git discovery helpers — thin wrappers over gittidy."""

from __future__ import annotations

from functools import cache
from pathlib import Path

from gittidy import Git

_PROMAN_DIR = Path(__file__).resolve().parent


@cache
def _git() -> Git:
    return Git(_PROMAN_DIR)


def git_repo_root() -> Path:
    """Return the absolute path to the repository root."""
    return _git().repo_path


def git_owner_repo() -> tuple[str, str]:
    """Return ``(owner, name)`` parsed from the git remote origin URL.

    Raises
    ------
    RuntimeError
        If the remote origin URL cannot be parsed.
    """
    result = _git().get_remote_repo_name()
    if result is None:
        msg = "Could not determine owner/repo from git remote origin."
        raise RuntimeError(msg)
    return result
