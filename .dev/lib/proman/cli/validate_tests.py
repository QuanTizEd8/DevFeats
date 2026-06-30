"""CLI entry point for validating feature test YAML definitions."""

from __future__ import annotations

import argparse
import sys

from proman.test.loader import FeatureTestError, FeatureTestLoader


def _validate_one(loader: FeatureTestLoader, feature_id: str) -> bool:
    """Validate one feature; print result; return True on success."""
    try:
        loader.load(feature_id)
    except (FeatureTestError, FileNotFoundError) as exc:
        print(f"⛔ {exc}", file=sys.stderr)
        return False
    print(f"✔  test/features/{feature_id}")
    return True


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
    feature_ids = [args.feature] if args.feature else loader.feature_ids()
    results = [_validate_one(loader, fid) for fid in feature_ids]
    if not all(results):
        sys.exit(1)


if __name__ == "__main__":
    main()
