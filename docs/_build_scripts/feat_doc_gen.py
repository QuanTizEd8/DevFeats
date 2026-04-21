"""Generate feature documentation from metadata.yaml and NOTES.md files."""

from __future__ import annotations

from pathlib import Path


def generate(
    metadata: dict[str, dict],
    features_dir: Path,
    features_doc_dir: Path,
    notes_filename: str = "NOTES.md",
) -> None:
    """Generate feature documentation."""
    # ── Feature reference preamble injection ───────────────────────────────────────
    # At build time, prepend each feature's H1 title, description, and ## Options
    # table to the stripped reference pages.
    #
    # metadata.yaml is the single source of truth.  The raw markdown description
    # (including links) is used verbatim so MyST renders it correctly.  The
    # ## Options table is generated from the options dict in metadata.yaml.
    # devcontainer-feature.json is a generated artifact and not read here.
    features_doc_dir.mkdir(exist_ok=True)
    for feat_id, feat_metadata in metadata.items():
        preamble = _gen_feature_preamble(feat_metadata)
        notes_path = features_dir / feat_id / notes_filename
        if notes_path.exists():
            notes = notes_path.read_text()
            content = f"{preamble}\n\n{notes}"
        else:
            content = preamble
        doc_path = features_doc_dir / f"{feat_id}.md"
        doc_path.write_text(content)
    return


def _gen_feature_preamble(feat_metadata: dict) -> str:
    name = feat_metadata["name"]
    description = feat_metadata["description"].strip()
    long_description = feat_metadata.get("_long_description", "").strip()
    options = _render_options_table(feat_metadata)
    parts = [
        f"# {name}",
        description,
        long_description,
        options,
    ]
    return "\n\n".join(parts) + "\n"


def _render_options_table(data: dict) -> str:
    """Render the ## Options table from a feature metadata dict.

    Args:
        data  Feature metadata dict (from devcontainer-feature.json or
              metadata.yaml — same structure).

    Returns a Markdown ``## Options`` table string, or an empty string when
    the feature has no options.  Does **not** include the feature description
    so callers can inject the raw (markdown-rich) description themselves.
    """
    options = data.get("options", {})
    if not options:
        return ""
    rows = [
        "## Options",
        "",
        "| Option | Type | Default | Description |",
        "|--------|------|---------|-------------|",
    ]
    for opt_name, opt in options.items():
        type_str = _option_type_str(opt)
        default_str = "\\n".join(_option_default_str(opt).splitlines())
        desc_str = _option_desc_full(opt)
        rows.append(f"| `{opt_name}` | {type_str} | {default_str} | {desc_str} |")
    return "\n".join(rows) + "\n"


# ── Internal helpers ──────────────────────────────────────────────────────────


def _option_type_str(opt: dict) -> str:
    t = opt.get("type", "string")
    if t == "string":
        if "enum" in opt:
            return "string (enum)"
        if "proposals" in opt:
            return "string (proposals)"
    return t


def _option_default_str(opt: dict) -> str:
    default = opt.get("default")
    if default is None:
        return ""
    if isinstance(default, bool):
        return f"`{'true' if default else 'false'}`"
    if isinstance(default, str):
        return f'`"{default}"`'
    return f"`{default}`"


def _option_desc_full(opt: dict) -> str:
    """Full option description collapsed to a single line for a table cell.

    Joins all non-empty lines with a space, so multi-line JSON descriptions
    are not truncated.
    """
    desc = opt.get("description", "")
    return " ".join(line.strip() for line in desc.splitlines() if line.strip())
