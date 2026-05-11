"""Config accessors for .config/ YAML files."""

from __future__ import annotations

from functools import cache

import yaml

from proman.git import git_repo_root


@cache
def load_project() -> dict:
    """Return the parsed contents of .config/project.yaml."""
    return yaml.safe_load(
        (git_repo_root() / ".config" / "project.yaml").read_text(encoding="utf-8"),
    )


@cache
def load_ci() -> dict:
    """Return the parsed contents of .config/ci.yaml."""
    return yaml.safe_load(
        (git_repo_root() / ".config" / "ci.yaml").read_text(encoding="utf-8"),
    )
