#!/usr/bin/env python3
"""Generate devcontainer-feature.json from metadata.yaml for each feature.

Usage:
    python3 scripts/_sync-src/metadata.py          # write/update all JSON files
    python3 scripts/_sync-src/metadata.py --check  # verify JSON files are up to date (CI)

Each features/*/metadata.yaml is the single source of truth for feature metadata.
devcontainer-feature.json is a generated artifact (git-ignored) produced by:

  1. Loading the YAML.
  2. Stripping markdown syntax from all ``description`` fields (feature-level
     and per-option) so the JSON description is plain text as the devcontainer
     spec recommends.
  3. Dropping custom ``x_*`` extension fields that are meaningful only to our
     tooling (docs, CI) and are not part of the devcontainer feature schema.
  4. Serialising to indented JSON.

Requires: PyYAML (pip install pyyaml / conda install pyyaml).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print(
        "ERROR: PyYAML is required.  Install with: pip install pyyaml",
        file=sys.stderr,
    )
    sys.exit(1)

_SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPT_DIR.parent))
from git_utils import git_owner_repo, git_repo_root


_REPO = git_repo_root()
_FEATURES = _REPO / "features"
_SRC = _REPO / "src"
_DERIVED_OPTIONS_PATH = _FEATURES / "derived-options.yaml"

# Constants
REPO_OWNER, REPO_NAME = git_owner_repo()
LICENSE_URL = f"https://github.com/{REPO_OWNER}/{REPO_NAME}/blob/main/LICENSE"
DOC_URL_BASE = f"https://{REPO_OWNER}.github.io/{REPO_NAME}"
DOC_URL_TEMPLATE = DOC_URL_BASE + "/features/{feature_id}/"


def main() -> None:
    check_mode = "--check" in sys.argv
    any_stale = False

    features = find_features()
    if not features:
        print(
            f"ERROR: No features/*/metadata.yaml files found under {_FEATURES}",
            file=sys.stderr,
        )
        sys.exit(1)

    for meta_path in features:
        feature_id = meta_path.parent.name
        json_path = _SRC / feature_id / "devcontainer-feature.json"

        with meta_path.open(encoding="utf-8") as fh:
            data = yaml.safe_load(fh)

        expected = generate_json(data)

        if check_mode:
            if not json_path.exists():
                print(f"⛔ {feature_id}: devcontainer-feature.json is missing", file=sys.stderr)
                any_stale = True
            elif json_path.read_text(encoding="utf-8") != expected:
                print(f"⛔ {feature_id}: devcontainer-feature.json is stale", file=sys.stderr)
                any_stale = True
            else:
                print(f"✅ {feature_id}: in sync", file=sys.stderr)
        else:
            json_path.parent.mkdir(parents=True, exist_ok=True)
            current = json_path.read_text(encoding="utf-8") if json_path.exists() else None
            if current == expected:
                print(f"✅ {feature_id}: devcontainer-feature.json unchanged", file=sys.stderr)
            else:
                json_path.write_text(expected, encoding="utf-8")
                print(f"✅ {feature_id}: generated devcontainer-feature.json", file=sys.stderr)

    if check_mode:
        if any_stale:
            print(
                "\n⛔ Stale devcontainer-feature.json files detected."
                "  Run: bash scripts/sync-src.sh",
                file=sys.stderr,
            )
            sys.exit(1)
        else:
            print("✅ All devcontainer-feature.json files are up to date.", file=sys.stderr)


def generate_json(data: dict) -> str:
    """Generate devcontainer-feature.json content from parsed YAML data.

    Returns the JSON string (with trailing newline).
    """
    full_options = _augment_options(data)
    patched: dict = {**data, "options": full_options}
    processed = {k: _process_value(k, v) for k, v in patched.items()}
    augmented = _add_synthetic_keys(processed)
    clean = _drop_internal_keys(augmented)
    return json.dumps(clean, sort_keys=True, indent=3, ensure_ascii=False) + "\n"


def _augment_options(data: dict) -> dict:
    """Generate the full options dict for a feature.

    Add derived options from features/derived-options.yaml,
    conditionally applying options with _apply_when
    based on the feature's full metadata dict.
    """
    with _DERIVED_OPTIONS_PATH.open(encoding="utf-8") as _fh:
        derived_options: dict = yaml.safe_load(_fh)

    options: dict = dict(data.get("options", {}))
    for option_id, option_def in derived_options.items():
        if option_id in options:
            raise ValueError(
                f"Feature {data.get('id', '<unknown>')} declares option '{option_id}' that conflicts with a reserved derived option.  "
                f"Remove the declaration to use the standard derived option schema from features/derived-options.yaml."
            )
        should_apply = (
            _evaluate_condition(option_def["_apply_when"], data)
            if "_apply_when" in option_def else True
        )
        if should_apply:
            options[option_id] = {k: v for k, v in option_def.items() if not k.startswith("_")}
    return options


def _evaluate_condition(apply_when: dict, data: dict) -> bool:
    """Evaluate an _apply_when condition against the feature's full metadata dict."""
    jsonpath = apply_when["jsonpath"]
    exists, value = _resolve_jsonpath(jsonpath, data)
    condition = apply_when["condition"]
    if condition == "exists":
        return exists
    if condition == "not_exists":
        return not exists
    if condition == "equals":
        expected = apply_when["value"]
        return exists and value == expected
    if condition == "not_equals":
        expected = apply_when["value"]
        return not exists or value != expected
    raise ValueError(f"Unsupported condition: {condition}")


def _resolve_jsonpath(jsonpath: str, data: dict) -> tuple[bool, object]:
    """Resolve a simple JSONPath expression against the feature metadata dict.

    Supported JSONPath syntax:
    - Root object: $
    - Dot notation for object properties: $.property

    Returns
    -------
    exists
        Whether the path exists in the metadata dict.
    value
        The value at the path if it exists, or None if it does not exist.
    """
    if not jsonpath.startswith("$."):
        raise ValueError(f"Unsupported JSONPath expression: {jsonpath}")
    path_parts = jsonpath[2:].split(".")
    current = data
    for part in path_parts:
        if not isinstance(current, dict) or part not in current:
            return False, None
        current = current[part]
    return True, current


def find_features() -> list[Path]:
    """Return sorted list of features/*/metadata.yaml paths."""
    return sorted(_FEATURES.glob("*/metadata.yaml"))


def _add_synthetic_keys(data: dict) -> dict:
    """Add synthetic keys to the top-level devcontainer-feature.json file data."""
    data["documentationURL"] = DOC_URL_TEMPLATE.format(feature_id=data["id"])
    data["licenseURL"] = LICENSE_URL
    return data


def _drop_internal_keys(data: dict) -> dict:
    """Drop internal-only keys."""
    return {k: v for k, v in data.items() if not k.startswith("_")}


# ---------------------------------------------------------------------------
# Markdown stripping
# ---------------------------------------------------------------------------

def strip_markdown(text: str) -> str:
    """Strip markdown formatting from a description string.

    Handles:
    - Images:   ![alt](url)        → alt
    - Links:    [text](url)        → text
    - Bold:     **text** / __text__ → text
    - Italic:   *text*              → text   (``_text_`` is intentionally left
                                              alone — too ambiguous with
                                              shell variables and identifiers)
    - HTML tags: <tag ...> / </tag> → (removed)
      Only real HTML is stripped: closing tags (</...>) and opening tags that
      carry attributes (contain whitespace).  Single-word angle-bracket tokens
      like <version>, <shell>, <home_dir> used as documentation placeholders
      are intentionally left untouched.

    Backtick code spans are intentionally preserved: they remain readable
    in plain text and are common in technical option descriptions.
    """
    if not text:
        return text
    # Images before links (avoid double-processing)
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)
    # Links
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    # Bold
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"__([^_]+)__", r"\1", text)
    # Italic (asterisk only)
    text = re.sub(r"\*([^*\n]+)\*", r"\1", text)
    # HTML tags: closing tags </foo> and opening tags with attributes <foo ...>
    # Single-word tokens like <version> or <shell> are NOT matched.
    text = re.sub(r"</[a-zA-Z][^>]*>", "", text)
    text = re.sub(r"<[a-zA-Z][^>]*\s[^>]*>", "", text)
    return text


def _normalize_description(text: str) -> str:
    """Strip markdown and normalize whitespace for JSON output.

    Strips leading/trailing whitespace and collapses multiple consecutive
    blank lines to a single blank line, while preserving intentional
    paragraph structure.
    """
    text = strip_markdown(text)
    lines = [line.rstrip() for line in text.splitlines()]
    # Collapse runs of blank lines
    result: list[str] = []
    prev_blank = False
    for line in lines:
        blank = not line.strip()
        if blank:
            if not prev_blank:
                result.append("")
            prev_blank = True
        else:
            result.append(line)
            prev_blank = False
    # Strip leading/trailing blank lines
    while result and not result[0]:
        result.pop(0)
    while result and not result[-1]:
        result.pop()
    return "\n".join(result)


# ---------------------------------------------------------------------------
# JSON generation
# ---------------------------------------------------------------------------

def _process_value(key: str, value: object) -> object:
    """Recursively process a value, stripping markdown from description fields."""
    if key == "description" and isinstance(value, str):
        return _normalize_description(value)
    if key == "options" and isinstance(value, dict):
        return {
            opt_name: {
                k: (
                    _normalize_description(v)
                    if k == "description" and isinstance(v, str)
                    else "string"
                    if k == "type" and v == "array"
                    else [item["value"] if isinstance(item, dict) else item for item in v]
                    if k in ("enum", "proposals") and isinstance(v, list)
                    else v
                )
                for k, v in opt.items()
            }
            for opt_name, opt in value.items()
        }
    return value


if __name__ == "__main__":
    main()
