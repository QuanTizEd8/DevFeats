#!/usr/bin/env python3
"""Compute the next bundle tag for the SysSet accumulator-tagged release.

Terminology:
    - **Bundle tag** — a global semver tag of the form ``v<X.Y.Z>`` that
      identifies a snapshot of every ``features/<id>/metadata.yaml`` version.
      The bundle tag accumulates: each CD run computes the highest-severity
      bump across all per-feature changes since the previous bundle and
      applies it to the bundle's semver.
    - **Per-feature tag** — ``<feature-id>/<X.Y.Z>`` (e.g.
      ``install-pixi/1.2.3``). Owned by the per-feature release pipeline.

This script drives the ``publish-bundle`` CI job and the
``just compute-bundle-tag`` recipe. It has three output modes (default plus
two mutually exclusive flags) that all share a single underlying computation:

    default       JSON decision record (next tag, aggregate bump, per-feature
                  bump classifications). Consumed by CI to set the Git tag.
    --notes-body  Human-readable release notes (Markdown). Written to
                  ``notes.md`` and passed to ``gh release create --notes-file``.
    --manifest    Machine-readable manifest (YAML) published alongside
                  ``sysset-all.tar.gz`` as a bundle release asset.
                  ``get.bash`` consumes this file when ``SYSSET_VERSION`` is
                  set to resolve per-feature versions deterministically.

Rules (see the design plan for full rationale):

    - The prior bundle tag is the highest ``v<X.Y.Z>`` repo tag, semver-sorted
      (paginated via /tags). First run → baseline ``v0.0.0`` (overridable via
      ``--baseline``).
    - Per-feature classification:
          new feature (no prior ``<id>/<X.Y.Z>`` tag)  → minor
          major differs                                 → major
          minor differs                                 → minor
          patch differs                                 → patch
          equal                                         → none
          curr < prev (downgrade)                       → abort
    - Feature removal (prior tags exist, directory gone) → major.
    - Aggregate = max(major > minor > patch > none).
    - Aggregate ``none`` → skip bundle (log line only; ``next_tag`` = prior).
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import yaml


_BUNDLE_TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
_FEATURE_TAG_RE = re.compile(r"^([a-z0-9][a-z0-9._-]*)/(\d+)\.(\d+)\.(\d+)$")
_BUMP_ORDER = {"none": 0, "patch": 1, "minor": 2, "major": 3}
_BUMP_REVERSE = {v: k for k, v in _BUMP_ORDER.items()}

# Transient HTTP status codes worth retrying. 429 = rate-limited;
# 5xx = upstream/edge errors.
_TRANSIENT_CODES = frozenset({429, 500, 502, 503, 504})
_MAX_ATTEMPTS = 3
_BACKOFF_INITIAL_SEC = 1.0
_HTTP_TIMEOUT_SEC = 30


# ─── Semver helpers ──────────────────────────────────────────────────────────


def _parse_semver(text: str) -> tuple[int, int, int]:
    """Parse ``X.Y.Z`` → ``(X, Y, Z)``; raise ValueError on bad input."""
    parts = text.strip().split(".")
    if len(parts) != 3:
        raise ValueError(f"not a 3-part semver: {text!r}")
    return (int(parts[0]), int(parts[1]), int(parts[2]))


def _classify_bump(prev: tuple[int, int, int], curr: tuple[int, int, int]) -> str:
    if curr == prev:
        return "none"
    if curr < prev:
        raise ValueError(f"downgrade: {prev} → {curr}")
    if curr[0] != prev[0]:
        return "major"
    if curr[1] != prev[1]:
        return "minor"
    return "patch"


def _apply_bump(base: tuple[int, int, int], bump: str) -> tuple[int, int, int]:
    if bump == "major":
        return (base[0] + 1, 0, 0)
    if bump == "minor":
        return (base[0], base[1] + 1, 0)
    if bump == "patch":
        return (base[0], base[1], base[2] + 1)
    return base


def _fmt_bundle(triple: tuple[int, int, int]) -> str:
    return f"v{triple[0]}.{triple[1]}.{triple[2]}"


def _max_bump(bumps: list[str]) -> str:
    if not bumps:
        return "none"
    return _BUMP_REVERSE[max(_BUMP_ORDER[b] for b in bumps)]


# ─── GitHub API helpers (stdlib only — no external deps beyond PyYAML) ───────


def _github_get(url: str, token: str | None) -> tuple[int, bytes]:
    """GET ``url`` with retries on transient failures.

    Returns ``(status, body)`` where ``status`` is the HTTP status code. Retries
    up to ``_MAX_ATTEMPTS`` times with exponential back-off on:

    * ``urllib.error.URLError`` (DNS, timeout, connection refused/reset, TLS
      handshake failures — anything where no HTTP response was obtained).
    * HTTP status codes in ``_TRANSIENT_CODES`` (429, 500, 502, 503, 504).

    Non-transient HTTP errors (e.g. 404, 401, 403) are returned as-is so the
    caller can branch on them. If every attempt fails with a network error,
    raises ``RuntimeError``.
    """
    backoff = _BACKOFF_INITIAL_SEC
    last_reason = "unknown error"
    for attempt in range(1, _MAX_ATTEMPTS + 1):
        req = urllib.request.Request(url, method="GET")
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        req.add_header("User-Agent", "sysset-compute-bundle-tag")
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(req, timeout=_HTTP_TIMEOUT_SEC) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as exc:
            # HTTPError is a subclass of URLError but represents a *received*
            # HTTP response. Read body defensively — exc.fp may be closed.
            status = exc.code
            try:
                body = exc.read() if exc.fp else b""
            except Exception:  # pragma: no cover — defensive
                body = b""
            if status in _TRANSIENT_CODES and attempt < _MAX_ATTEMPTS:
                last_reason = f"HTTP {status}"
                print(
                    f"⚠️  compute-bundle-tag: transient HTTP {status} from "
                    f"{url} (attempt {attempt}/{_MAX_ATTEMPTS}); retrying…",
                    file=sys.stderr,
                )
            else:
                return status, body
        except urllib.error.URLError as exc:
            # No HTTP response obtained: DNS, timeout, connection refused/reset,
            # TLS handshake failure. Retry with back-off; raise on exhaustion.
            last_reason = f"network error: {exc.reason!r}"
            if attempt >= _MAX_ATTEMPTS:
                raise RuntimeError(
                    f"GET {url} failed after {_MAX_ATTEMPTS} attempts — "
                    f"{last_reason}"
                ) from exc
            print(
                f"⚠️  compute-bundle-tag: {last_reason} fetching {url} "
                f"(attempt {attempt}/{_MAX_ATTEMPTS}); retrying…",
                file=sys.stderr,
            )
        time.sleep(backoff)
        backoff *= 2
    # Only reachable if we exhaust retries on transient HTTP codes.
    raise RuntimeError(
        f"GET {url} exhausted {_MAX_ATTEMPTS} retries — last: {last_reason}"
    )


def _paginate_tags(repo: str, token: str | None, per_page: int = 100):
    """Yield every ``name`` value from ``/repos/<repo>/tags`` across all pages."""
    page = 1
    while True:
        params = urllib.parse.urlencode({"per_page": per_page, "page": page})
        url = f"https://api.github.com/repos/{repo}/tags?{params}"
        status, body = _github_get(url, token)
        if status != 200:
            raise RuntimeError(
                f"GitHub API error fetching {url}: HTTP {status}: {body[:200]!r}"
            )
        items = json.loads(body or b"[]")
        if not isinstance(items, list):
            raise RuntimeError(f"unexpected /tags response shape from {url}")
        for item in items:
            name = item.get("name") if isinstance(item, dict) else None
            if isinstance(name, str):
                yield name
        if len(items) < per_page:
            return
        page += 1


# ─── Discovery ───────────────────────────────────────────────────────────────


def _load_features(features_dir: pathlib.Path) -> dict[str, str]:
    """Return ``{feature_id: version_string}`` from every ``features/<id>/metadata.yaml``."""
    out: dict[str, str] = {}
    for meta_path in sorted(features_dir.glob("*/metadata.yaml")):
        with meta_path.open(encoding="utf-8") as fp:
            data = yaml.safe_load(fp) or {}
        version = str(data.get("version", "")).strip()
        if not version:
            print(
                f"⚠️  compute-bundle-tag: {meta_path.parent.name} has no version — skipping.",
                file=sys.stderr,
            )
            continue
        out[meta_path.parent.name] = version
    return out


def _discover_tags(repo: str, token: str | None):
    """One-shot paginated fetch of every tag name. Returns a list (cheap: hundreds of items)."""
    return list(_paginate_tags(repo, token))


def _prior_bundle_tag(all_tags: list[str], baseline: str) -> str:
    """Return the highest ``v<X.Y.Z>`` tag, or ``baseline`` if none exist."""
    best: tuple[int, int, int] | None = None
    for t in all_tags:
        m = _BUNDLE_TAG_RE.match(t)
        if not m:
            continue
        triple = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if best is None or triple > best:
            best = triple
    if best is None:
        return baseline
    return _fmt_bundle(best)


def _latest_feature_versions(all_tags: list[str]) -> dict[str, tuple[int, int, int]]:
    """Return ``{feature_id: highest_semver}`` over all ``<id>/<X.Y.Z>`` tags."""
    by_feature: dict[str, tuple[int, int, int]] = {}
    for t in all_tags:
        m = _FEATURE_TAG_RE.match(t)
        if not m:
            continue
        fid = m.group(1)
        triple = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
        prev = by_feature.get(fid)
        if prev is None or triple > prev:
            by_feature[fid] = triple
    return by_feature


# ─── Core computation ────────────────────────────────────────────────────────


def _compute(
    repo: str,
    features_dir: pathlib.Path,
    baseline: str,
    token: str | None,
) -> dict:
    features_now = _load_features(features_dir)
    all_tags = _discover_tags(repo, token)
    prior_tag = _prior_bundle_tag(all_tags, baseline)
    prior_features = _latest_feature_versions(all_tags)

    per_feature: list[dict] = []
    bumps: list[str] = []

    for fid in sorted(features_now):
        curr_str = features_now[fid]
        try:
            curr = _parse_semver(curr_str)
        except ValueError as exc:
            raise SystemExit(f"⛔ compute-bundle-tag: feature '{fid}': {exc}") from exc
        prev = prior_features.get(fid)
        if prev is None:
            bump = "minor"
            per_feature.append(
                {
                    "id": fid,
                    "prev": None,
                    "curr": curr_str,
                    "bump": bump,
                    "reason": "new",
                }
            )
        else:
            try:
                bump = _classify_bump(prev, curr)
            except ValueError as exc:
                raise SystemExit(
                    f"⛔ compute-bundle-tag: feature '{fid}': {exc}"
                ) from exc
            prev_str = f"{prev[0]}.{prev[1]}.{prev[2]}"
            per_feature.append(
                {"id": fid, "prev": prev_str, "curr": curr_str, "bump": bump}
            )
        bumps.append(bump)

    for fid in sorted(prior_features):
        if fid not in features_now:
            prev = prior_features[fid]
            prev_str = f"{prev[0]}.{prev[1]}.{prev[2]}"
            per_feature.append(
                {
                    "id": fid,
                    "prev": prev_str,
                    "curr": None,
                    "bump": "major",
                    "reason": "removed",
                }
            )
            bumps.append("major")

    aggregate = _max_bump(bumps)
    prior_triple = _parse_semver(prior_tag[1:] if prior_tag.startswith("v") else prior_tag)
    next_triple = _apply_bump(prior_triple, aggregate)
    next_tag = _fmt_bundle(next_triple) if aggregate != "none" else prior_tag

    return {
        "repo": repo,
        "prior_tag": prior_tag,
        "next_tag": next_tag,
        "bump": aggregate,
        "skip": aggregate == "none",
        "per_feature": per_feature,
        "features_now": features_now,
    }


# ─── Output formatters ───────────────────────────────────────────────────────


def _format_json(record: dict) -> str:
    # Strip features_now (internal helper; not part of the public schema).
    public = {k: v for k, v in record.items() if k != "features_now"}
    return json.dumps(public, indent=2, sort_keys=False) + "\n"


def _format_notes(record: dict) -> str:
    repo = record["repo"]
    prior = record["prior_tag"]
    nxt = record["next_tag"]
    features_now: dict[str, str] = record["features_now"]
    per_feature = record["per_feature"]

    lines: list[str] = []

    lines.append("## Feature versions in this bundle")
    lines.append("")

    # Build a map for quick lookup by id (we need `bump` and `prev` for annotations).
    by_id = {item["id"]: item for item in per_feature}

    for fid in sorted(features_now):
        version = features_now[fid]
        item = by_id.get(fid, {})
        bump = item.get("bump", "none")
        prev = item.get("prev")
        annot = ""
        if bump == "none":
            annot = ""
        elif prev is None:
            annot = f"  (new → [`{fid}/{version}`](https://github.com/{repo}/releases/tag/{fid}/{version}))"
        else:
            annot = (
                f"  (bumped from `{prev}` → "
                f"[`{fid}/{version}`](https://github.com/{repo}/releases/tag/{fid}/{version}))"
            )
        lines.append(f"- `{fid}` @ `{version}`{annot}")

    lines.append("")
    lines.append(f"## Changes since prior bundle ({prior})")
    lines.append("")
    any_change = False
    for item in per_feature:
        bump = item["bump"]
        if bump == "none":
            continue
        any_change = True
        fid = item["id"]
        if item.get("reason") == "new":
            lines.append(f"- `{fid}`: new ({item['curr']})")
        elif item.get("reason") == "removed":
            lines.append(f"- `{fid}`: removed (was {item['prev']})")
        else:
            lines.append(f"- `{fid}`: {bump} ({item['prev']} → {item['curr']})")
    if not any_change:
        lines.append("_No per-feature changes; bundle tag unchanged from prior._")

    lines.append("")
    lines.append(f"Bundle tag: `{nxt}` · Prior: `{prior}` · Aggregate bump: `{record['bump']}`.")
    lines.append("")
    return "\n".join(lines)


def _format_manifest(record: dict, commit: str) -> str:
    features_now: dict[str, str] = record["features_now"]
    # Assemble as an ordered dict and serialize deterministically.
    manifest = {
        "bundle": record["next_tag"],
        "commit": commit,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "features": {fid: features_now[fid] for fid in sorted(features_now)},
    }
    return yaml.safe_dump(manifest, sort_keys=False, default_flow_style=False)


# ─── CLI ─────────────────────────────────────────────────────────────────────


def main() -> int:
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
        "--baseline",
        default="v0.0.0",
        help="Starting bundle tag when no prior v<X.Y.Z> exists (default: v0.0.0).",
    )
    parser.add_argument(
        "--commit",
        default=os.environ.get("GITHUB_SHA", ""),
        help="Commit SHA to embed in --manifest output (default: $GITHUB_SHA).",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GITHUB_TOKEN"),
        help="GitHub token (defaults to $GITHUB_TOKEN).",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--notes-body",
        action="store_true",
        help="Emit release-notes body (Markdown) instead of the JSON decision record.",
    )
    mode.add_argument(
        "--manifest",
        action="store_true",
        help="Emit the bundle manifest (YAML) instead of the JSON decision record.",
    )
    args = parser.parse_args()

    features_dir = pathlib.Path(args.features_dir).resolve()
    if not features_dir.is_dir():
        print(
            f"⛔ compute-bundle-tag: features dir not found: {features_dir}",
            file=sys.stderr,
        )
        return 1

    try:
        record = _compute(args.repo, features_dir, args.baseline, args.token)
    except RuntimeError as exc:
        print(f"⛔ compute-bundle-tag: {exc}", file=sys.stderr)
        return 1
    # _compute raises SystemExit(msg) for hard errors (e.g. downgrades); let
    # Python's default handler print the message and exit 1.

    if args.notes_body:
        sys.stdout.write(_format_notes(record))
    elif args.manifest:
        sys.stdout.write(_format_manifest(record, args.commit))
    else:
        sys.stdout.write(_format_json(record))
    return 0


if __name__ == "__main__":
    sys.exit(main())
