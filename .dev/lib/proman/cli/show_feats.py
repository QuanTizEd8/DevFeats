"""CLI entry point for proman-show-feats."""

from __future__ import annotations

import sys

import yaml

from proman.git import git_repo_root


def main() -> None:
    """Print all features with their descriptions."""
    repo = git_repo_root()
    features_dir = repo / "features"
    total = 0
    for meta_path in sorted(features_dir.glob("*/metadata.yaml")):
        feat_id = meta_path.parent.name
        meta = yaml.safe_load(meta_path.read_text(encoding="utf-8"))
        desc = meta.get("description", "")
        print(f"{feat_id}: {desc}")
        total += 1
    print(f"Total features: {total}")
    sys.exit(0)
