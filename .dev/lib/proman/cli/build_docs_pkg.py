"""CLI entry point for proman-build-docs-pkg."""

from __future__ import annotations

import argparse
import os
import sys
import tarfile
from pathlib import Path

from proman.git import git_repo_root


def _package(output: Path) -> int:
    build_dir = output.parent

    if not build_dir.is_dir():
        print(f"{build_dir}/ not found. Run 'just build-docs' first.", file=sys.stderr)
        return 1

    html_files = list(build_dir.glob("**/*.html"))
    if not html_files:
        print(
            f"{build_dir}/ contains no HTML files. Run 'just build-docs' first.",
            file=sys.stderr,
        )
        return 1

    symlinks = [p for p in build_dir.rglob("*") if p.is_symlink()]
    if symlinks:
        print(
            "Symlinks found in docs/.build/ — the GitHub Pages API will reject"
            " this artifact:",
            file=sys.stderr,
        )
        for s in symlinks:
            print(f"  {s}", file=sys.stderr)
        return 1

    print(f"Packaging {build_dir}/ → {output}", file=sys.stderr)
    output.unlink(missing_ok=True)

    with tarfile.open(output, "w") as tf:
        for item in sorted(build_dir.rglob("*")):
            if item.is_symlink():
                continue
            name = item.relative_to(build_dir)
            parts = name.parts
            # exclude hidden files/dirs and the output tar itself
            if any(p.startswith(".") for p in parts):
                continue
            if item == output:
                continue
            tf.add(item, arcname=str(name))

    size_kb = output.stat().st_size // 1024
    print(f"Packaged: {output} ({size_kb} KB)", file=sys.stderr)
    return 0


def main() -> None:
    """Package docs/.build/ into a GitHub Pages artifact tarball."""
    repo = git_repo_root()
    default_output = repo / os.environ.get(
        "WEBSITE_TAR_FILEPATH", "docs/.build/artifact.tar",
    )

    parser = argparse.ArgumentParser(
        description="Package docs/.build/ into a GitHub Pages artifact tarball.",
    )
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=default_output,
        help=f"Output tar path (default: {default_output}).",
    )
    args = parser.parse_args()
    sys.exit(_package(Path(args.output)))
