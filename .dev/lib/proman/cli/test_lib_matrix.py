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
    parser.add_argument(
        "run_unit_args",
        nargs=argparse.REMAINDER,
        help="Extra arguments forwarded to run-unit.sh.",
    )
    args = parser.parse_args()
    extra = [a for a in args.run_unit_args if a != "--"]
    sys.exit(run(args.env, extra))
