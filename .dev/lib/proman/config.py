"""Config accessors for .config/ YAML files."""

from __future__ import annotations

from functools import cache
from typing import TYPE_CHECKING

import pyserials

from proman.git import git_repo_root

if TYPE_CHECKING:
    from pathlib import Path


class Config:
    """Access and resolve project-level ProMan configuration values."""

    def __init__(self) -> None:
        self._root_path = git_repo_root()
        config_dict = {}
        for file in self._root_path.glob(".config/proman/*.yaml"):
            data = pyserials.read.yaml_from_file(file)
            if file.stem.startswith("_"):
                config_dict.update(data)
            else:
                config_dict[file.stem] = data
        config = pyserials.NestedDict(config_dict)
        config.fill()
        self._config = config

    @property
    def root_path(self) -> Path:
        """Root path of the project (git repo root)."""
        return self._root_path

    @property
    def asdict(self) -> dict:
        """Config as a regular dict."""
        return self._config()

    def absolute_path(self, config_path: str) -> Path:
        """Convert a path relative to the project root into an absolute Path."""
        rel_path = self._config[config_path]
        if not isinstance(rel_path, str):
            msg = f"Config path {config_path} does not point to a string path."
            raise TypeError(msg)
        return self._root_path / rel_path

    def __getitem__(self, dotted_path: str) -> object:
        """Return a config value by dotted path."""
        return self._config[dotted_path]


def load() -> Config:
    """Load all config from .config/proman/*.yaml."""
    return _load_cached()


def clear_cache() -> None:
    """Clear the cached Config instance used by ``load()``."""
    _load_cached.cache_clear()


@cache
def _load_cached() -> Config:
    return Config()
