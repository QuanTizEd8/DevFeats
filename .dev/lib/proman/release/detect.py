r"""Detect which features and the bash library need a new GitHub Release.

For every feature in ``features/<id>/metadata.yaml``:

1. Read the ``.version`` field.
2. Query the GitHub Releases API for an existing release with
   ``tag_name == "<id>/<version>"``.
3. If absent → emit a record ``{"kind": "feature", "feature": "<id>",
   "version": "<X.Y.Z>", "tag": "<id>/<X.Y.Z>"}``.

For the bash library at ``lib/metadata.yaml``:

1. Read the ``.version`` field.
2. Query the GitHub Releases API for an existing release with
   ``tag_name == "lib/<version>"``.
3. If absent → emit a record ``{"kind": "lib", "feature": "bashlib",
   "version": "<X.Y.Z>", "tag": "lib/<X.Y.Z>"}``.

Outputs a JSON array on stdout. Used by
``.github/workflows/scripts/cicd_detect.sh`` to populate the
``features_to_release`` step output and derive the ``is_release`` boolean
(non-empty list → release run), and by a ``just detect-releasable`` recipe for
local preview before pushing.

Usage:
    python scripts/detect-releasable.py \\
        --repo <owner>/<name> \\
        [--features-dir features] \\
        [--lib-metadata lib/metadata.yaml] \\
        [--token $GITHUB_TOKEN]

``--token`` defaults to the ``GITHUB_TOKEN`` environment variable. The script
falls back to unauthenticated requests (subject to a lower rate limit) when no
token is available.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import urllib.parse
from typing import TYPE_CHECKING

import yaml
from pylinks.api.github import GitHub, Repo

if TYPE_CHECKING:
    from collections.abc import Generator
from pylinks.exception.api import WebAPIPersistentStatusCodeError


def _iter_feature_metadata(
    features_dir: pathlib.Path,
) -> Generator[tuple[str, dict], None, None]:
    """Yield ``(feature_id, metadata_dict)`` tuples for each feature."""
    for metadata_path in sorted(features_dir.glob("*/metadata.yaml")):
        with metadata_path.open(encoding="utf-8") as fp:
            data = yaml.safe_load(fp) or {}
        fid = metadata_path.parent.name
        yield fid, data


def _release_exists(repo: Repo, tag: str) -> bool:
    """Return True iff a GitHub Release with ``tag_name == tag`` exists."""
    encoded_tag = urllib.parse.quote(tag, safe="")
    try:
        repo._rest_query(f"releases/tags/{encoded_tag}")
        return True
    except WebAPIPersistentStatusCodeError as exc:
        if exc.response.status_code == 404:
            return False
        msg = (
            f"unexpected GitHub API response for tag {tag!r}: "
            f"HTTP {exc.response.status_code}"
        )
        raise RuntimeError(
            msg,
        ) from exc


def detect_releasable(
    repository: str,
    features_dir: pathlib.Path,
    token: str | None = None,
    lib_metadata_path: pathlib.Path | None = None,
) -> list[dict[str, str]]:
    """Return features and/or library that need a new GitHub Release.

    Each record includes a ``kind`` field: ``"feature"`` for features and
    ``"lib"`` for the bash library.

    Raises RuntimeError on unexpected GitHub API errors.
    """
    owner, _, name = repository.partition("/")
    repo = GitHub(token).user(owner).repo(name)
    releasable: list[dict[str, str]] = []

    for fid, meta in _iter_feature_metadata(features_dir):
        version = str(meta.get("version", "")).strip()
        if not version:
            print(
                f"⚠️  detect-releasable: {fid} has no version field — skipping.",
                file=sys.stderr,
            )
            continue
        tag = f"{fid}/{version}"
        if not _release_exists(repo, tag):
            releasable.append(
                {"kind": "feature", "feature": fid, "version": version, "tag": tag}
            )

    if lib_metadata_path is not None and lib_metadata_path.is_file():
        with lib_metadata_path.open(encoding="utf-8") as fp:
            lib_meta = yaml.safe_load(fp) or {}
        lib_version = str(lib_meta.get("version", "")).strip()
        if not lib_version:
            print(
                "⚠️  detect-releasable: lib/metadata.yaml missing 'version' — skipping.",
                file=sys.stderr,
            )
        else:
            lib_tag = f"lib/{lib_version}"
            if not _release_exists(repo, lib_tag):
                releasable.append(
                    {
                        "kind": "lib",
                        "feature": "bashlib",
                        "version": lib_version,
                        "tag": lib_tag,
                    }
                )

    return releasable


def main() -> int:
    """Parse CLI arguments and run the releasable detection pipeline."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo",
        required=True,
        help="GitHub repository in 'owner/name' format.",
    )
    parser.add_argument(
        "--features-dir",
        default="features",
        help="Path to the features directory (default: features).",
    )
    parser.add_argument(
        "--lib-metadata",
        default="lib/metadata.yaml",
        help=(
            "Path to lib/metadata.yaml (default: lib/metadata.yaml)."
            " Pass an empty string to skip library detection."
        ),
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GITHUB_TOKEN"),
        help="GitHub token (defaults to $GITHUB_TOKEN).",
    )
    args = parser.parse_args()

    features_dir = pathlib.Path(args.features_dir).resolve()
    if not features_dir.is_dir():
        print(
            f"⛔ detect-releasable: features directory not found: {features_dir}",
            file=sys.stderr,
        )
        return 1

    owner, _, name = args.repo.partition("/")
    if not owner or not name:
        print(
            f"⛔ detect-releasable: --repo must be 'owner/name', got: {args.repo!r}",
            file=sys.stderr,
        )
        return 1

    lib_metadata_path: pathlib.Path | None = None
    if args.lib_metadata:
        lib_metadata_path = pathlib.Path(args.lib_metadata).resolve()

    try:
        releasable = detect_releasable(
            args.repo, features_dir, args.token, lib_metadata_path
        )
    except RuntimeError as exc:
        print(f"⛔ detect-releasable: {exc}", file=sys.stderr)
        return 1

    json.dump(releasable, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
