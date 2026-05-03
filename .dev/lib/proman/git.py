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
    return _git().repo_path


def git_owner_repo() -> tuple[str, str]:
    result = _git().get_remote_repo_name()
    if result is None:
        raise RuntimeError("Could not determine owner/repo from git remote origin.")
    return result
