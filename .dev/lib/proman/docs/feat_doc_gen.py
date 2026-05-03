"""Generate feature documentation from metadata.yaml and NOTES.md files."""

import json
from typing import Any

import mdit

from proman.git import git_owner_repo


def generate(metadata: dict[str, Any], notes: str = "") -> str:
    """Generate feature documentation."""
    name = metadata["name"]
    description = metadata["description"].strip()
    long_description = metadata.get("_long_description", "").strip()
    options = _render_options_table(metadata)
    example = _generate_usage_tabset(metadata)
    parts = [
        f"# {name}",
        description,
        long_description,
        "## Example Usage",
        example,
        options,
        notes,
    ]
    sep = "\n\n"
    return sep.join(parts).strip() + "\n"


def _generate_usage_tabset(metadata: dict[str, Any]) -> str:
    feat_id = metadata.get("id", "")
    major = metadata.get("version", "1").split(".")[0]
    owner, repo_name = git_owner_repo()
    feature_ref = f"ghcr.io/{owner}/{repo_name}/{feat_id}:{major}"

    options = metadata.get("options", {})
    defaults = {k: v.get("default") for k, v in options.items()}

    dc_json_lines = json.dumps({"features": {feature_ref: defaults}}, indent=2).splitlines()
    dc_json = "\n".join(
        [
            "// devcontainer.json",
            *dc_json_lines[:-2],
            "    // other features...",
            dc_json_lines[-2],
            "  // other properties...",
            dc_json_lines[-1]
        ]
    )

    items = list(defaults.items())
    cli_lines = [f"{feat_id} \\"]
    for i, (k, v) in enumerate(items):
        flag = f"--{k.replace('_', '-')}"
        val = str(v).lower() if isinstance(v, bool) else (v if v != "" else '""')
        suffix = " \\" if i < len(items) - 1 else ""
        cli_lines.append(f"  {flag} {val}{suffix}")
    cli_code = "\n".join(cli_lines)

    ts = mdit.element.TabSet(mdit.block_container())
    ts.append(mdit.element.CodeBlock(dc_json, language="json"), title="Dev Container")
    ts.append(mdit.element.CodeBlock(cli_code, language="bash"), title="CLI")
    tabset_str = ts.source(target="sphinx")
    description = (
        "For demonstration purposes, all available options are explicitly included with their default values. "
        "In real usage, you only need to specify the options you want to override."
    )
    return f"{description}\n\n{tabset_str}"


def _render_options_table(data: dict) -> str:
    """Render the ## Options table from a feature metadata dict.

    Parameters
    ----------
    data : dict
        Feature metadata dict (from devcontainer-feature.json or
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
            ],
        )

        if "_applies_when" in opt:
            conditions: list[dict] = opt["_applies_when"]
            conditions_str = [_render_option_condition(cond) for cond in conditions]
            if len(conditions) == 1:
                rows.append(f"- Applies when: {conditions_str[0]}")
            else:
                rows.append("- Applies when:")
                rows.extend(f"  - {cond_str}" for cond_str in conditions_str)

        if "enum" in opt:
            rows.append("- Allowed values:")
            rows.extend(
                f"  - `\"{e['value']}\"`: {e['description'].strip()}"
                for e in opt["enum"]
            )
        elif "proposals" in opt:
            rows.append("- Examples:")
            rows.extend(
                f"  - `\"{p['value']}\"`: {p['description'].strip()}"
                for p in opt["proposals"]
            )

    return "\n".join(rows) + "\n"


def _render_option_condition(condition: dict) -> str:
    """Render an option applicability condition to a human-readable string."""
    parts = []
    for key, values in condition.items():
        if isinstance(values, str):
            parts.append(f'`{key} = "{values}"`')
        elif isinstance(values, bool):
            parts.append(f"`{key} = {str(values).lower()}`")
        elif isinstance(values, list):
            values_str = ", ".join(f'"{v}"' for v in values)
            parts.append(f"`{key} ∈ {{{values_str}}}`")
        else:
            msg = f"Unsupported condition value type: {type(values)} for key {key}"
            raise TypeError(msg)
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
