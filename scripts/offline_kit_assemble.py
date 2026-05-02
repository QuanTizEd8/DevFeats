#!/usr/bin/env python3
"""Assemble offline kit staging: digest-primary features/, manifest.json, root installers.

Reads a partial manifest (from compute-bundle-tag --manifest) with at least:
  schemaVersion, version, generatedAt, features, refs, digests

For each entry in ``features``, expects ``dist/devfeats-<id>.tar.gz``, computes
``sha256`` of that tarball file, extracts it under the digest path, and fills
``refs`` / ``digests``.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tarfile
from datetime import datetime, timezone
from pathlib import Path


def _safe_extractall(tf: tarfile.TarFile, dest: Path) -> None:
    """Extract tarball; use PEP-706 data filter on Python 3.12+ to limit path escape risks."""
    if sys.version_info >= (3, 12):
        tf.extractall(dest, filter="data")
    else:
        tf.extractall(dest)


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for chunk in iter(lambda: fp.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _checksums_for_dir(root: Path, rel_names: tuple[str, ...]) -> dict[str, str]:
    out: dict[str, str] = {}
    for name in rel_names:
        p = root / name
        if p.is_file():
            out[name.replace("\\", "/")] = _sha256_file(p)
    return out


def _check_manifest_version_matches_tag(data: dict, bundle_tag: str) -> str | None:
    """Return an error message if the manifest's ``version`` and ``bundle_tag`` disagree.

    The kit filename is derived from the CLI bundle tag; the JSON base is typed by
    ``compute-bundle-tag --manifest``. Failing here avoids shipping a file whose name
    does not match the embedded ``manifest.json`` (e.g. a stale hand-edited base).
    """
    mv = str(data.get("version", "")).strip()
    bt = (bundle_tag or "").strip()
    if not bt:
        return "bundle tag must be non-empty (e.g. v1.2.0)"
    if not mv:
        return "base manifest has no top-level 'version' field"
    if mv != bt:
        return f"base manifest version {mv!r} does not match bundle tag {bt!r}"
    return None


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("bundle_tag", help="Bundle tag e.g. v1.2.0")
    p.add_argument("dist_dir", type=Path, help="Directory with devfeats-<feature>.tar.gz")
    p.add_argument("base_manifest", type=Path, help="Partial JSON manifest path")
    p.add_argument("staging_dir", type=Path, help="Output staging directory (created)")
    args = p.parse_args()

    dist_dir: Path = args.dist_dir
    staging: Path = args.staging_dir
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    data = json.loads(args.base_manifest.read_text(encoding="utf-8"))
    if err := _check_manifest_version_matches_tag(data, args.bundle_tag):
        print(f"⛔ offline_kit_assemble: {err}", file=sys.stderr)
        return 1
    features: dict[str, str] = data.get("features") or {}
    if not isinstance(features, dict) or not features:
        print("⛔ offline_kit_assemble: no features in base manifest", file=sys.stderr)
        return 1

    refs: dict[str, str] = {}
    digests: dict[str, dict] = {}
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    oci_ns = "ghcr.io/quantized8/devfeats"

    first_tar: Path | None = None
    for feat in sorted(features):
        ver = str(features[feat]).strip()
        tb = dist_dir / f"devfeats-{feat}.tar.gz"
        if not tb.is_file():
            print(f"⛔ offline_kit_assemble: missing tarball {tb}", file=sys.stderr)
            return 1
        if first_tar is None:
            first_tar = tb

        digest_hex = _sha256_file(tb)
        digest_key = f"sha256:{digest_hex}"
        # Path segment matches the lowercased feature in ref keys and local-registry digest layout (install.bash).
        _feat_path = str(feat).lower()
        rel_path = f"features/{oci_ns}/{_feat_path}/sha256/{digest_hex}/"
        dest = staging / rel_path
        dest.mkdir(parents=True, exist_ok=True)
        with tarfile.open(tb, "r:gz") as tf:
            _safe_extractall(tf, dest)

        # Must match install.bash: _norm="${_ref,,}" before .refs[$r] lookup.
        ref = f"{oci_ns}/{feat}:{ver}"
        ref_key = ref.lower()
        refs[ref_key] = digest_key

        chks = _checksums_for_dir(
            dest,
            ("install.sh", "install.bash", "devcontainer-feature.json"),
        )
        digests[digest_key] = {
            "relativePath": rel_path,
            "fetchedAt": now,
            "sourceRefs": [ref_key],
            "checksums": chks,
        }

    assert first_tar is not None
    tmp_root = staging / "_root_src"
    tmp_root.mkdir(parents=True)
    with tarfile.open(first_tar, "r:gz") as tf:
        _safe_extractall(tf, tmp_root)
    for name in ("install.sh", "install.bash"):
        shutil.copy2(tmp_root / name, staging / name)
    shutil.copytree(tmp_root / "_lib", staging / "_lib", dirs_exist_ok=True)
    shutil.rmtree(tmp_root)

    data["refs"] = refs
    data["digests"] = digests
    root_entries: dict[str, str] = {}
    for rp in ("install.bash", "install.sh"):
        fp = staging / rp
        if fp.is_file():
            root_entries[rp] = _sha256_file(fp)
    lib_dir = staging / "_lib"
    if lib_dir.is_dir():
        for child in sorted(lib_dir.rglob("*")):
            if child.is_file():
                rel = str(child.relative_to(staging)).replace("\\", "/")
                root_entries[rel] = _sha256_file(child)
    if root_entries:
        data["checksums"] = {"algorithm": "sha256", "entries": root_entries}

    (staging / "manifest.json").write_text(
        json.dumps(data, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
