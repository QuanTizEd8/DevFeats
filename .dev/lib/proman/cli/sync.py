"""CLI entry point for proman-sync."""

from __future__ import annotations

import argparse
import sys

from proman.sync import run


def main() -> None:
    """Parse CLI arguments and run the feature sync pipeline."""
    parser = argparse.ArgumentParser(
        description="Assemble each feature's src/ directory from features/ + lib/.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify src/ is up to date; exit non-zero if stale (no files written).",
    )
    args = parser.parse_args()
    sys.exit(run(check_only=args.check))
