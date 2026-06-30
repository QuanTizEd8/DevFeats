"""CLI entry point for proman-test-lib-matrix."""

from __future__ import annotations

import argparse
import sys

from proman.test.lib_matrix import run


def main() -> None:
    """Run lib/ unit tests across container environments."""
    parser = argparse.ArgumentParser(
        description="Run lib/ unit tests across container environments.",
    )
    parser.add_argument(
        "--env",
        metavar="NAME",
        default=None,
        help="Run only this environment (default: run all).",
    )
    args, extra = parser.parse_known_args()
    extra = [a for a in extra if a != "--"]
    sys.exit(run(args.env, extra))
