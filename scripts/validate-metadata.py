#!/usr/bin/env python3
"""Validate all features/*/metadata.yaml against features/metadata.schema.json.

Remote $ref URLs in the schema that point to local files are rewritten to
file:// URIs so validation works entirely offline.
"""

import copy
import json
import pathlib
import sys

import jsonschema
import yaml

REPO_ROOT = pathlib.Path(__file__).parent.parent
SCHEMA_FILE = REPO_ROOT / "features" / "metadata.schema.json"
MANIFEST_SCHEMA_FILE = REPO_ROOT / "features" / "install-os-pkg" / "manifest.schema.json"

# The remote URL used in metadata.schema.json for the manifest sub-schema.
_REMOTE_MANIFEST_URL = (
    "https://raw.githubusercontent.com/QuanTizEd8/SysSet/main"
    "/features/install-os-pkg/manifest.schema.json"
)


def _rewrite_remote_refs(obj: object) -> None:
    """Replace the remote manifest $ref with the local file:// URI (in-place)."""
    if isinstance(obj, dict):
        if obj.get("$ref") == _REMOTE_MANIFEST_URL:
            obj["$ref"] = MANIFEST_SCHEMA_FILE.as_uri()
        for v in obj.values():
            _rewrite_remote_refs(v)
    elif isinstance(obj, list):
        for item in obj:
            _rewrite_remote_refs(item)


def main() -> int:
    schema = copy.deepcopy(json.loads(SCHEMA_FILE.read_text()))
    _rewrite_remote_refs(schema)
    validator = jsonschema.Draft7Validator(schema)

    metadata_files = sorted(REPO_ROOT.glob("features/*/metadata.yaml"))
    failures = 0

    for meta_file in metadata_files:
        feature = meta_file.parent.name
        try:
            data = yaml.safe_load(meta_file.read_text())
        except yaml.YAMLError as exc:
            print(f"❌  {feature}: YAML parse error: {exc}", file=sys.stderr)
            failures += 1
            continue

        errs = sorted(
            validator.iter_errors(data),
            key=lambda e: list(e.absolute_path),
        )
        if errs:
            for err in errs:
                path = (
                    " → ".join(str(p) for p in err.absolute_path)
                    if err.absolute_path
                    else "(root)"
                )
                print(f"❌  {feature}: {path}: {err.message}", file=sys.stderr)
            failures += 1
        else:
            print(f"✔  {feature}")

    if failures:
        print(
            f"\n{failures}/{len(metadata_files)} feature(s) failed validation.",
            file=sys.stderr,
        )
        return 1

    print(f"\n✅  All {len(metadata_files)} metadata.yaml files are valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
