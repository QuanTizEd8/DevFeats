"""CLI entry point for validating feature test YAML definitions."""

from __future__ import annotations

import argparse
import sys

from proman.test.loader import FeatureTestError, FeatureTestLoader


def main() -> None:
    """Validate checks.yaml and scenarios.yaml for one or all feature tests."""
    parser = argparse.ArgumentParser(
        description="Validate feature test checks.yaml and scenarios.yaml files.",
    )
    parser.add_argument(
        "feature",
        nargs="?",
        help="Feature id (e.g. install-jq). Omit to validate all features.",
    )
    args = parser.parse_args()

    loader = FeatureTestLoader()
    try:
        if args.feature:
            loader.load(args.feature)
            print(f"✔  test/features/{args.feature}")
        else:
            loader.load_all()
            print("✔  all feature test definitions valid")
    except (FeatureTestError, FileNotFoundError) as exc:
        print(f"⛔ {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
