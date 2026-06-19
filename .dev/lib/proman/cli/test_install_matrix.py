"""CLI entry point for proman-test-install-matrix."""

from __future__ import annotations

import argparse
import sys

from proman.test.install_matrix import run


def main() -> None:
    """Run install framework tests across container environments."""
    parser = argparse.ArgumentParser(
        description="Run install framework tests across container environments.",
    )
    parser.add_argument(
        "--env",
        metavar="NAME",
        default=None,
        help="Run only this environment (default: run all).",
    )
    parser.add_argument(
        "run_install_args",
        nargs=argparse.REMAINDER,
        help="Extra arguments forwarded to run-install.sh.",
    )
    args = parser.parse_args()
    extra = [a for a in args.run_install_args if a != "--"]
    sys.exit(run(args.env, extra))
