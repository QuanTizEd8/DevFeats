"""CLI: generate docs build context JSON for Sphinx and cross-environment use."""

from __future__ import annotations

import argparse
import json
import sys

from proman.config import load as load_config
from proman.docs import feat_doc_gen, lib_doc_gen
from proman.docs.parse_lib import parse_lib_module
from proman.git import git_owner_repo, git_repo_root
from proman.metadata import MetadataLoader
from proman.sync import sync_file


def main() -> int:
    """Generate docs_build_context.json and per-feature/library Markdown files."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--include-private",
        action="store_true",
        default=False,
        help="Include private functions (names starting with _) in library docs.",
    )
    args = parser.parse_args()
    config = load_config()

    repo = git_repo_root()
    features_dir = config.absolute_path("path.features")
    lib_dir = config.absolute_path("path.library")
    data_transfer_dir = config.absolute_path("path.data_transfer")
    data_transfer_dir.mkdir(parents=True, exist_ok=True)
    notes_filename = str(config["filename.feature_notes"])

    owner, repo_name = git_owner_repo()

    # ── Feature metadata ──────────────────────────────────────────────────────

    all_metadata = MetadataLoader().load()

    # ── Library module metadata ───────────────────────────────────────────────

    lib_modules: dict[str, str] = {}
    for sh_path in sorted(lib_dir.glob("*.sh")):
        module = parse_lib_module(sh_path)
        if not module.summary:
            print(
                f"⚠️  gen-docs-data: {sh_path.name} has no module-level docs; skipping",
                file=sys.stderr,
            )
            continue
        lib_modules[module.name] = module.summary

    # ── Write docs_build_context.json ─────────────────────────────────────────

    docs_data = {
        "repo_owner": owner,
        "repo_name": repo_name,
        "features": all_metadata,
        "lib_modules": lib_modules,
    }
    docs_build_context_path = data_transfer_dir / str(config["filename.docs_build_context"])
    docs_build_context_content = json.dumps(docs_data, indent=2, ensure_ascii=False)
    sync_file(docs_build_context_path, docs_build_context_content)

    # ── Feature docs ──────────────────────────────────────────────────────────

    feat_doc_dir = config.absolute_path("path.docs_source_features")
    feat_doc_dir.mkdir(parents=True, exist_ok=True)
    for feat_id, feat_metadata in all_metadata.items():
        notes_path = features_dir / feat_id / notes_filename
        notes = notes_path.read_text(encoding="utf-8") if notes_path.exists() else ""
        doc_content = feat_doc_gen.generate(metadata=feat_metadata, notes=notes)
        doc_path = feat_doc_dir / f"{feat_id}.md"
        sync_file(doc_path, doc_content)

    # ── Library docs ──────────────────────────────────────────────────────────

    lib_doc_dir = config.absolute_path("path.docs_source_library")
    lib_doc_dir.mkdir(parents=True, exist_ok=True)
    for sh_path in sorted(lib_dir.glob("*.sh")):
        module = parse_lib_module(sh_path)
        doc_content = lib_doc_gen.generate(module, include_private=args.include_private)
        doc_path = lib_doc_dir / f"{module.name}.md"
        sync_file(doc_path, doc_content)

    print(
        f"docs build context:"
        f" {len(all_metadata)} features, {len(lib_modules)} lib modules"
        f" → {docs_build_context_path.relative_to(repo)}"
        f" + {feat_doc_dir.relative_to(repo)}/*.md"
        f" + {lib_doc_dir.relative_to(repo)}/*.md",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
