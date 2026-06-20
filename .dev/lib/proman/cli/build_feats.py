"""CLI entry point for proman-build-feats."""

from __future__ import annotations

import argparse
import shutil
import sys
import tarfile
from pathlib import Path

from proman.config import load as load_config


def _build(tag: str) -> int:
    config = load_config()
    dist_dir = config.absolute_path("ci.artifacts.dist.path")
    src_dir = config.absolute_path("path.src")
    feature_script = str(config["filename.feature_script"])
    feature_lib_dir = Path(str(config["path.feature_library"]))
    name_slug = str(config["name_slug"])
    src_rel = str(config["path.src"])
    dist_rel = str(config["ci.artifacts.dist.path"])

    print(f"Building artifacts for tag: '{tag}'", file=sys.stderr)

    check = list(src_dir.glob(f"*/{feature_script}"))
    if not check:
        print(
            f"{src_rel}/ is not populated. Run 'just sync-src' first.",
            file=sys.stderr,
        )
        return 1

    if dist_dir.exists():
        shutil.rmtree(dist_dir)
    dist_dir.mkdir(parents=True)

    feature_dirs = sorted(
        script.parent
        for script in src_dir.glob(f"*/{feature_script}")
        if (script.parent / "install.sh").is_file()
    )

    if not feature_dirs:
        print(
            f"No assembled features with install.sh and {feature_script} found in {src_rel}/.",
            file=sys.stderr,
        )
        return 1

    print(f"Found {len(feature_dirs)} features.", file=sys.stderr)

    tmp_dir = dist_dir / "tmp"
    for feat_dir in feature_dirs:
        name = feat_dir.name
        staging = tmp_dir / name
        tarball = dist_dir / f"{name_slug}-{name}.tar.gz"

        staging.mkdir(parents=True)

        shutil.copy2(feat_dir / "install.sh", staging / "install.sh")
        shutil.copy2(feat_dir / feature_script, staging / feature_script)
        lib_src = feat_dir / feature_lib_dir
        if lib_src.is_dir():
            shutil.copytree(lib_src, staging / feature_lib_dir)

        json_src = feat_dir / "devcontainer-feature.json"
        if json_src.exists():
            shutil.copy2(json_src, staging / "devcontainer-feature.json")

        files_src = feat_dir / "files"
        if files_src.is_dir():
            shutil.copytree(files_src, staging / "files")

        with tarfile.open(tarball, "w:gz") as tf:
            tf.add(staging, arcname=".")
        shutil.rmtree(staging)
        print(f"{name}: built {name_slug}-{name}.tar.gz", file=sys.stderr)

    shutil.rmtree(tmp_dir, ignore_errors=True)
    print(f"\nBuild complete. Artifacts in {dist_rel}:", file=sys.stderr)
    for f in sorted(dist_dir.iterdir()):
        print(f"  {f.name}  ({f.stat().st_size // 1024} KB)", file=sys.stderr)
    return 0


def main() -> None:
    """Build distribution tarballs from assembled src into the dist artifact path."""
    parser = argparse.ArgumentParser(
        description="Assemble standalone distribution artifacts.",
    )
    parser.add_argument(
        "tag",
        nargs="?",
        default="dev",
        help="Release tag for informational output (default: dev).",
    )
    args = parser.parse_args()
    sys.exit(_build(args.tag))
