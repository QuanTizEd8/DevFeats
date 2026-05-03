"""CLI: generate docs-data artifact for cross-environment consumption."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from proman import feat_doc_gen
from proman.git_utils import git_owner_repo, git_repo_root
from proman.sync import load_and_augment

_FEATURES_NOTES_FILENAME = "NOTES.md"


def main() -> int:
    repo = git_repo_root()
    features_dir = repo / "features"
    output_dir = repo / ".dev" / "output"
    output_dir.mkdir(parents=True, exist_ok=True)

    owner, repo_name = git_owner_repo()

    all_metadata: dict[str, dict] = {}
    for meta_path in sorted(features_dir.glob("*/metadata.yaml")):
        feat_id = meta_path.parent.name
        feat_metadata = load_and_augment(feat_id, features_dir)
        if feat_metadata is None:
            print(
                f"⚠️  gen-docs-data: skipping {feat_id} (metadata load/augment failed)",
                file=sys.stderr,
            )
            continue
        feat_metadata["id"] = feat_id
        all_metadata[feat_id] = feat_metadata

    docs_data = {
        "repo_owner": owner,
        "repo_name": repo_name,
        "features": all_metadata,
    }
    (output_dir / "docs-data.json").write_text(
        json.dumps(docs_data, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    feat_doc_dir = repo / "docs" / "source" / "features"
    feat_doc_dir.mkdir(parents=True, exist_ok=True)
    for feat_id, feat_metadata in all_metadata.items():
        notes_path = features_dir / feat_id / _FEATURES_NOTES_FILENAME
        notes = notes_path.read_text(encoding="utf-8") if notes_path.exists() else ""
        doc_content = feat_doc_gen.generate(metadata=feat_metadata, notes=notes)
        doc_path = feat_doc_dir / f"{feat_id}.md"
        if not doc_path.exists() or doc_path.read_text(encoding="utf-8") != doc_content:
            doc_path.write_text(doc_content, encoding="utf-8")

    print(
        f"docs-data: {len(all_metadata)} features → "
        f".dev/output/docs-data.json + docs/source/features/*.md"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
