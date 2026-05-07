"""CLI entry point for proman-build-feats."""

from __future__ import annotations

import argparse
import shutil
import sys
import tarfile

from proman.git import git_repo_root


def _build(tag: str) -> int:
    repo = git_repo_root()
    dist_dir = repo / "dist"
    src_dir = repo / "src"
    features_dir = repo / "features"

    print(f"Building artifacts for tag: '{tag}'", file=sys.stderr)

    check = list(src_dir.glob("*/install.bash"))
    if not check:
        print("src/ is not populated. Run 'just sync-src' first.", file=sys.stderr)
        return 1

    if dist_dir.exists():
        shutil.rmtree(dist_dir)
    dist_dir.mkdir(parents=True)

    feature_dirs = []
    for install_bash in sorted(features_dir.glob("*/install.bash")):
        name = install_bash.parent.name
        src_feat = src_dir / name
        if (src_feat / "install.bash").exists():
            feature_dirs.append(src_feat)

    if not feature_dirs:
        print("No features with an install.bash found.", file=sys.stderr)
        return 1

    print(f"Found {len(feature_dirs)} features.", file=sys.stderr)

    tmp_dir = dist_dir / "tmp"
    for feat_dir in feature_dirs:
        name = feat_dir.name
        staging = tmp_dir / name
        tarball = dist_dir / f"devfeats-{name}.tar.gz"

        staging.mkdir(parents=True)

        shutil.copy2(feat_dir / "install.sh", staging / "install.sh")
        shutil.copy2(feat_dir / "install.bash", staging / "install.bash")
        shutil.copytree(feat_dir / "_lib", staging / "_lib")

        json_src = feat_dir / "devcontainer-feature.json"
        if json_src.exists():
            shutil.copy2(json_src, staging / "devcontainer-feature.json")

        deps_src = feat_dir / "dependencies"
        if deps_src.is_dir():
            shutil.copytree(deps_src, staging / "dependencies")

        files_src = feat_dir / "files"
        if files_src.is_dir():
            shutil.copytree(files_src, staging / "files")

        with tarfile.open(tarball, "w:gz") as tf:
            tf.add(staging, arcname=".")
        shutil.rmtree(staging)
        print(f"{name}: built devfeats-{name}.tar.gz", file=sys.stderr)

    shutil.rmtree(tmp_dir, ignore_errors=True)
    print(f"\nBuild complete. Artifacts in {dist_dir}:", file=sys.stderr)
    for f in sorted(dist_dir.iterdir()):
        print(f"  {f.name}  ({f.stat().st_size // 1024} KB)", file=sys.stderr)
    return 0


def main() -> None:
    """Build distribution tarballs from assembled src/ into dist/."""
    parser = argparse.ArgumentParser(
        description="Assemble standalone distribution artifacts into dist/.",
    )
    parser.add_argument(
        "tag",
        nargs="?",
        default="dev",
        help="Release tag for informational output (default: dev).",
    )
    args = parser.parse_args()
    sys.exit(_build(args.tag))
