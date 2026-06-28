"""CLI entry point for proman-build-lib."""

from __future__ import annotations

import shutil
import sys
import tarfile

import yaml

from proman.config import load as load_config


def _build() -> int:
    config = load_config()
    dist_dir = config.absolute_path("ci.artifacts.dist.path")
    lib_dir = config.absolute_path("path.library")
    name_slug = str(config["name_slug"])
    dist_rel = str(config["ci.artifacts.dist.path"])

    metadata_path = lib_dir / "metadata.yaml"
    if not metadata_path.is_file():
        print(
            f"Library metadata not found: {metadata_path}",
            file=sys.stderr,
        )
        return 1

    with metadata_path.open(encoding="utf-8") as fp:
        metadata = yaml.safe_load(fp) or {}
    version = str(metadata.get("version", "")).strip()
    if not version:
        print("lib/metadata.yaml has no 'version' field.", file=sys.stderr)
        return 1

    print(f"Building library tarball (version {version}).", file=sys.stderr)

    dist_dir.mkdir(parents=True, exist_ok=True)
    tarball = dist_dir / f"{name_slug}-bashlib.tar.gz"
    wrap_name = f"{name_slug}-bashlib-{version}"
    tmp_staging = dist_dir / "tmp-lib" / wrap_name
    tmp_staging.mkdir(parents=True, exist_ok=True)

    # Copy all lib/ contents except metadata.yaml.
    for src in lib_dir.iterdir():
        if src.name == "metadata.yaml":
            continue
        dst = tmp_staging / src.name
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    # Write VERSION file so __installed_version can read it at install time.
    (tmp_staging / "VERSION").write_text(version, encoding="utf-8")

    with tarfile.open(tarball, "w:gz") as tf:
        tf.add(tmp_staging, arcname=wrap_name)

    shutil.rmtree(tmp_staging.parent, ignore_errors=True)
    size_kb = tarball.stat().st_size // 1024
    print(
        f"Built {tarball.name} ({size_kb} KB) in {dist_rel}/.",
        file=sys.stderr,
    )
    return 0


def main() -> None:
    """Build the devfeats bash library distribution tarball."""
    sys.exit(_build())
