"""CLI: publish JSON Schemas into the Sphinx output tree for GitHub Pages."""

from __future__ import annotations

import argparse
from pathlib import Path

from proman.git import git_repo_root
from proman.schema_bundle import publish_website_schemas


def main() -> None:
    """Write rewritten JSON schemas into the Sphinx output tree for GitHub Pages."""
    parser = argparse.ArgumentParser(
        description=(
            "Materialize JSON Schemas listed in .config/docs.yaml "
            "(json_schemas_publish) into <outdir>/schema/ with $id / $ref URLs "
            "for the published site."
        ),
    )
    parser.add_argument(
        "--outdir",
        type=Path,
        default=None,
        help="Sphinx HTML output directory (default: <repo>/.local/build/docs)",
    )
    parser.add_argument(
        "--base-url",
        type=str,
        default=None,
        help="Override website base URL (must match GitHub Pages); "
        "default: website_base_url in .config/docs.yaml or git-derived Pages URL",
    )
    args = parser.parse_args()
    repo = git_repo_root()
    outdir = args.outdir or (repo / ".local" / "build" / "docs")
    publish_website_schemas(repo, outdir, base_url=args.base_url)


if __name__ == "__main__":
    main()
