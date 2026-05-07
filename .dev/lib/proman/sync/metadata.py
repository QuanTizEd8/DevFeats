"""Feature metadata: read, augment, validate, and sanitize metadata.yaml."""

from __future__ import annotations

import json
import re
import sys
from typing import TYPE_CHECKING, Literal

import jsonschema
import yaml

if TYPE_CHECKING:
    from pathlib import Path


def log(msg: str) -> None:
    """Write a diagnostic message to stderr."""
    print(msg, file=sys.stderr)


def load_and_augment(feature_id: str, features_dirpath: Path) -> dict | None:
    """Read and augment metadata for a single feature; return None on failure."""
    derived_options = load_derived_options(features_dirpath)
    metadata = read_metadata(feature_id, features_dirpath)
    if not isinstance(metadata, dict):
        return None
    if not augment_metadata(feature_id, metadata, derived_options):
        return None
    return metadata


# Metadata Reading
# ----------------


def read_metadata(feature_id: str, features_dirpath: Path) -> dict | Literal[0, 1]:
    """Read and parse the metadata.yaml for the given feature ID."""
    metadata_filepath = features_dirpath / feature_id / "metadata.yaml"
    if not metadata_filepath.is_file():
        log(
            f"⚠️ {feature_id}: metadata.yaml not found for feature '{feature_id}';"
            " skipping"
        )
        return 0

    try:
        data = yaml.safe_load(metadata_filepath.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        log(f"❌ {feature_id}: YAML parse error: {exc}")
        return 1

    if not isinstance(data, dict):
        log(
            f"❌ {feature_id}: metadata.yaml does not contain a mapping"
            f" (got {type(data).__name__})"
        )
        return 1

    return data


# Metadata Augmentation
# ---------------------


def augment_metadata(feature_id: str, metadata: dict, derived_options: dict) -> bool:
    """Generate the full options dict for a feature.

    Add common options from features/shared-options.yaml,
    conditionally applying options with _apply_when
    based on the feature's full metadata dict.
    """
    options: dict = metadata.get("options", {})
    for option_id, option_def in derived_options.items():
        if option_id in options:
            log(
                f"⛔ {feature_id}: option '{option_id}' is a derived option and"
                " cannot be manually defined in metadata.yaml"
            )
            return False
        should_apply = (
            _evaluate_condition(option_def["_apply_when"], metadata)
            if "_apply_when" in option_def
            else True
        )
        if should_apply:
            options[option_id] = {
                k: v for k, v in option_def.items() if not k.startswith("_")
            }
    metadata["options"] = options
    return True


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
    msg = f"Unsupported condition: {condition}"
    raise ValueError(msg)


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
        msg = f"Unsupported JSONPath expression: {jsonpath}"
        raise ValueError(msg)
    path_parts = jsonpath[2:].split(".")
    current = data
    for part in path_parts:
        if not isinstance(current, dict) or part not in current:
            return False, None
        current = current[part]
    return True, current


def load_derived_options(features_dirpath: Path) -> dict:
    """Load shared-options.yaml and return its contents as a dict."""
    with (features_dirpath / "shared-options.yaml").open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


# Schema Validation
# -----------------


def validate_metadata_schema(
    feature_id: str,
    metadata: dict,
    validator: jsonschema.Draft7Validator,
) -> bool:
    """Validate metadata against the JSON schema.

    Logs all validation errors and returns False on failure.
    """
    errs = sorted(
        validator.iter_errors(metadata),
        key=lambda e: list(e.absolute_path),
    )
    if errs:
        for err in errs:
            path = (
                " → ".join(str(p) for p in err.absolute_path)
                if err.absolute_path
                else "(root)"
            )
            log(f"❌ {feature_id}: {path}: {err.message}")
        return False

    return True


def build_metadata_validator(
    features_dirpath: Path,
    lib_dirpath: Path,
    ospkg_schema_id: str,
) -> jsonschema.Draft7Validator:
    """Build and return a JSON schema validator for feature metadata."""
    schema_path = features_dirpath / "metadata.schema.json"
    ospkg_manifest_path = lib_dirpath / "ospkg.manifest.schema.json"
    metadata_schema = json.loads(schema_path.read_text(encoding="utf-8"))
    _rewrite_remote_refs(metadata_schema, ospkg_schema_id, ospkg_manifest_path)
    return jsonschema.Draft7Validator(metadata_schema)


def _rewrite_remote_refs(
    obj: object,
    ospkg_schema_id: str,
    ospkg_manifest_path: Path,
) -> None:
    """Replace the remote manifest $ref with the local file:// URI (in-place)."""
    if isinstance(obj, dict):
        if obj.get("$ref", "").lower() == ospkg_schema_id.lower():
            obj["$ref"] = ospkg_manifest_path.as_uri()
        for v in obj.values():
            _rewrite_remote_refs(v, ospkg_schema_id, ospkg_manifest_path)
    elif isinstance(obj, list):
        for item in obj:
            _rewrite_remote_refs(item, ospkg_schema_id, ospkg_manifest_path)


# Markdown Sanitation
# -------------------


def sanitize_markdown(metadata: dict) -> None:
    """Recursively process a value, stripping markdown from description fields."""
    metadata["description"] = _normalize_description(metadata["description"])

    if "options" in metadata:
        for option in metadata["options"].values():
            option["description"] = _normalize_description(option["description"])


def _normalize_description(text: str) -> str:
    """Strip markdown and normalize whitespace for JSON output.

    Strips leading/trailing whitespace and collapses multiple consecutive
    blank lines to a single blank line, while preserving intentional
    paragraph structure.
    """
    text = _strip_markdown(text)
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


def _strip_markdown(text: str) -> str:
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
    return re.sub(r"<[a-zA-Z][^>]*\s[^>]*>", "", text)
