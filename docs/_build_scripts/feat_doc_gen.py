"""Generate feature documentation from metadata.yaml and NOTES.md files."""

from typing import Any


def generate(metadata: dict[str, Any], notes: str = "") -> str:
    """Generate feature documentation."""
    # ── Feature reference preamble injection ───────────────────────────────────────
    # At build time, prepend each feature's H1 title, description, and ## Options
    # table to the stripped reference pages.
    #
    # metadata.yaml is the single source of truth.  The raw markdown description
    # (including links) is used verbatim so MyST renders it correctly.  The
    # ## Options table is generated from the options dict in metadata.yaml.
    # devcontainer-feature.json is a generated artifact and not read here.
    name = metadata["name"]
    description = metadata["description"].strip()
    long_description = metadata.get("_long_description", "").strip()
    options = _render_options_table(metadata)
    parts = [
        f"# {name}",
        description,
        long_description,
        options,
        notes,
    ]
    return f"{'\n\n'.join(parts).strip()}\n"


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
    ]
    for opt_name, opt in options.items():
        opt_type = opt["type"]

        default_str = "\\n".join(_option_default_str(opt).splitlines())
        rows.extend(
            [
                f"### `{opt_name}`",
                _option_desc_full(opt),
                f"- Type: `{opt_type}`",
                f"- Default: {default_str}",
            ]
        )

        if "_applies_when" in opt:
            conditions: list[dict] = opt["_applies_when"]
            conditions_str = [_render_option_condition(cond) for cond in conditions]
            if len(conditions) == 1:
                rows.append(f"- Applies when: {conditions_str[0]}")
            else:
                rows.append("- Applies when:")
                for cond_str in conditions_str:
                    rows.append(f"  - {cond_str}")

        if "enum" in opt:
            rows.append("- Allowed values:")
            for enum in opt["enum"]:
                rows.append(f'  - `"{enum["value"]}"`: {enum["description"].strip()}')

        elif "proposals" in opt:
            rows.append("- Examples:")
            for proposal in opt["proposals"]:
                rows.append(f'  - `"{proposal["value"]}"`: {proposal["description"].strip()}')

    return "\n".join(rows) + "\n"


def _render_option_condition(condition: dict) -> str:
    """Render an option applicability condition to a human-readable string."""
    parts = []
    for key, values in condition.items():
        if isinstance(values, str):
            parts.append(f'`{key} = "{values}"`')
        elif isinstance(values, bool):
            parts.append(f'`{key} = {str(values).lower()}`')
        elif isinstance(values, list):
            values_str = ", ".join(f'"{v}"' for v in values)
            parts.append(f'`{key} ∈ {{{values_str}}}`')
        else:
            raise ValueError(f"Unsupported condition value type: {type(values)} for key {key}")
    return " and ".join(parts)


# ── Internal helpers ──────────────────────────────────────────────────────────

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
