"""Shared git discovery helpers for scripts."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


_SCRIPT_DIR = Path(__file__).resolve().parent


def _resolve_cwd() -> Path:
    """Return the default cwd used for all git commands."""
    return _SCRIPT_DIR


def _run_git(args: list[str]) -> str:
    """Run a git command in the scripts directory and return stripped stdout."""
    try:
        return subprocess.check_output(
            ["git", *args],
            cwd=_resolve_cwd(),
            text=True,
        ).strip()
    except Exception as exc:  # pragma: no cover - environment dependent
        raise RuntimeError(f"git {' '.join(args)} failed: {exc}") from exc


def git_repo_root() -> Path:
    """Return repository root resolved via git."""
    return Path(_run_git(["rev-parse", "--show-toplevel"]))


def git_origin_url() -> str:
    """Return origin remote URL."""
    return _run_git(["config", "--get", "remote.origin.url"])


def git_origin_slug() -> str:
    """Return GitHub slug in owner/repo form from origin URL."""
    remote = git_origin_url()
    match = re.search(r"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?$", remote)
    if not match:
        raise RuntimeError(f"Could not parse GitHub slug from origin URL: {remote}")
    return f"{match.group(1)}/{match.group(2)}"


def git_owner_repo() -> tuple[str, str]:
    """Return (owner, repo_name) from origin URL."""
    slug = git_origin_slug()
    owner, repo_name = slug.split("/", 1)
    return owner, repo_name
