#!/usr/bin/env python3
"""Detect which features in features/*/metadata.yaml need a new GitHub Release.

For every feature in ``features/<id>/metadata.yaml``:

1. Read the ``.version`` field.
2. Query the GitHub Releases API for an existing release with
   ``tag_name == "<id>/<version>"``.
3. If absent → emit a record ``{"feature": "<id>", "version": "<X.Y.Z>",
   "tag": "<id>/<X.Y.Z>"}``.

Outputs a JSON array on stdout. Used by
``.github/workflows/scripts/cicd_detect.sh`` to populate the
``features_to_release`` step output and derive the ``is_release`` boolean
(non-empty list → release run), and by a ``just detect-releasable`` recipe for
local preview before pushing.

Usage:
    python scripts/detect-releasable.py \\
        --repo <owner>/<name> \\
        [--features-dir features] \\
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
import time
import urllib.error
import urllib.parse
import urllib.request

import yaml


# Transient HTTP status codes worth retrying. 429 = rate-limited;
# 5xx = upstream/edge errors.
_TRANSIENT_CODES = frozenset({429, 500, 502, 503, 504})
_MAX_ATTEMPTS = 3
_BACKOFF_INITIAL_SEC = 1.0
_HTTP_TIMEOUT_SEC = 30


def _iter_feature_metadata(features_dir: pathlib.Path):
    """Yield ``(feature_id, metadata_dict)`` tuples for each feature."""
    for metadata_path in sorted(features_dir.glob("*/metadata.yaml")):
        with metadata_path.open(encoding="utf-8") as fp:
            data = yaml.safe_load(fp) or {}
        # Prefer the directory name (canonical) but fall back to the id field.
        fid = metadata_path.parent.name
        yield fid, data


def _github_request(url: str, token: str | None) -> tuple[int, bytes]:
    """GET ``url`` with retries on transient failures.

    Returns ``(status, body)`` where ``status`` is the HTTP status code. The
    body is the raw response bytes (may be empty). Retries up to
    ``_MAX_ATTEMPTS`` times with exponential back-off on:

    * ``urllib.error.URLError`` (DNS, timeout, connection refused/reset, TLS
      handshake failures — anything where no HTTP response was obtained).
    * HTTP status codes in ``_TRANSIENT_CODES`` (429, 500, 502, 503, 504).

    Non-transient HTTP errors (e.g. 404, 401, 403) are returned as-is so the
    caller can branch on them. If every attempt fails with a ``URLError``,
    raises ``RuntimeError`` with a summary of the last failure; callers are
    expected to surface this to the user.
    """
    backoff = _BACKOFF_INITIAL_SEC
    last_reason = "unknown error"
    for attempt in range(1, _MAX_ATTEMPTS + 1):
        req = urllib.request.Request(url, method="GET")
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        req.add_header("User-Agent", "sysset-detect-releasable")
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(req, timeout=_HTTP_TIMEOUT_SEC) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as exc:
            # HTTPError is a subclass of URLError but represents a *received*
            # HTTP response — the server answered, just with an error status.
            # Read the body defensively: exc.fp may already be closed/None.
            status = exc.code
            try:
                body = exc.read() if exc.fp else b""
            except Exception:  # pragma: no cover — defensive
                body = b""
            if status in _TRANSIENT_CODES and attempt < _MAX_ATTEMPTS:
                last_reason = f"HTTP {status}"
                print(
                    f"⚠️  detect-releasable: transient HTTP {status} from "
                    f"{url} (attempt {attempt}/{_MAX_ATTEMPTS}); retrying…",
                    file=sys.stderr,
                )
            else:
                return status, body
        except urllib.error.URLError as exc:
            # Covers timeouts, DNS failures, connection refused/reset, TLS
            # handshake errors, etc. — cases where no HTTP response is
            # available. HTTPError is excluded (handled above).
            last_reason = f"network error: {exc.reason!r}"
            if attempt >= _MAX_ATTEMPTS:
                raise RuntimeError(
                    f"GET {url} failed after {_MAX_ATTEMPTS} attempts — "
                    f"{last_reason}"
                ) from exc
            print(
                f"⚠️  detect-releasable: {last_reason} fetching {url} "
                f"(attempt {attempt}/{_MAX_ATTEMPTS}); retrying…",
                file=sys.stderr,
            )
        time.sleep(backoff)
        backoff *= 2
    # Only reachable if we exhaust retries on transient HTTP codes.
    raise RuntimeError(
        f"GET {url} exhausted {_MAX_ATTEMPTS} retries — last: {last_reason}"
    )


def _release_exists(repo: str, tag: str, token: str | None) -> bool:
    """Return True iff a GitHub Release with ``tag_name == tag`` exists.

    A 200 response means the release exists; 404 means it does not. Any other
    (non-transient) HTTP status is raised as ``RuntimeError`` so the caller
    can surface the problem rather than silently emitting a spurious release
    entry. Transient failures (5xx, 429, network errors) are retried inside
    ``_github_request``.
    """
    encoded_tag = urllib.parse.quote(tag, safe="")
    url = f"https://api.github.com/repos/{repo}/releases/tags/{encoded_tag}"
    status, body = _github_request(url, token)
    if status == 200:
        return True
    if status == 404:
        return False
    raise RuntimeError(
        f"unexpected GitHub API response fetching {url}: "
        f"HTTP {status}: {body[:200]!r}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo",
        required=True,
        help="GitHub repository in 'owner/name' format (e.g. quantized8/sysset).",
    )
    parser.add_argument(
        "--features-dir",
        default="features",
        help="Path to the features directory (default: features).",
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

    releasable: list[dict[str, str]] = []
    try:
        for fid, meta in _iter_feature_metadata(features_dir):
            version = str(meta.get("version", "")).strip()
            if not version:
                print(
                    f"⚠️  detect-releasable: {fid} has no version field — skipping.",
                    file=sys.stderr,
                )
                continue
            tag = f"{fid}/{version}"
            if _release_exists(args.repo, tag, args.token):
                continue
            releasable.append({"feature": fid, "version": version, "tag": tag})
    except RuntimeError as exc:
        print(f"⛔ detect-releasable: {exc}", file=sys.stderr)
        return 1

    json.dump(releasable, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
