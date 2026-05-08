"""CLI entry point for proman-show-feat-opts."""

from __future__ import annotations

import sys
from collections import Counter

import yaml

from proman.git import git_repo_root


def main() -> None:
    """Print all feature option keys sorted by number of occurrences across features."""
    repo = git_repo_root()
    features_dir = repo / "features"
    counts: Counter[str] = Counter()
    for meta_path in sorted(features_dir.glob("*/metadata.yaml")):
        meta = yaml.safe_load(meta_path.read_text(encoding="utf-8"))
        for key in meta.get("options") or {}:
            counts[key] += 1
    for key, count in counts.most_common():
        print(f"{key} ({count})")
    sys.exit(0)
