"""Generate Markdown API reference for one lib shell module."""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from proman.docs.parse_lib import (
        LibFunction,
        LibModule,
        SectionBlock,
    )

from proman.docs.parse_lib import ParagraphBlock

# Sections rendered as definition lists (multi-item, name + description pairs).
_DEFLIST_SECTIONS = frozenset({"Args", "Parameters", "Env"})

# Map from section title to the heading label used in rendered output.
_SECTION_HEADINGS = {
    "Args": "Parameters",
    "Parameters": "Parameters",
    "Env": "Environment",
    "Stdout": "Stdout",
    "Returns": "Returns",
}


def generate(module: LibModule, *, include_private: bool = False) -> str:
    """Generate API reference Markdown for a lib shell module.

    Parameters
    ----------
    module : LibModule
        Parsed module returned by ``parse_lib_module``.
    include_private : bool
        When False (default), functions whose name starts with ``_`` are
        omitted from the output.

    Returns
    -------
    str
        Full Markdown content for ``docs/source/library/<filename>.md``.
    """
    parts: list[str] = [f"# `{module.name}`"]
    if module.summary:
        parts.append(module.summary)
    if module.description:
        parts.append(module.description)
    funcs = (
        module.functions
        if include_private
        else [f for f in module.functions if not f.name.startswith("_")]
    )
    parts.extend(_render_function(func) for func in funcs)
    return "\n\n".join(parts) + "\n"


# ── Internal helpers ──────────────────────────────────────────────────────────


def _render_function(func: LibFunction) -> str:
    """Render a single LibFunction as a Markdown ## subsection."""
    parts: list[str] = [f"## `{func.name}`"]
    if func.description:
        parts.append(func.description)
    parts.append(f"```bash\n{func.signature}\n```")
    for block in func.body:
        if isinstance(block, ParagraphBlock):
            parts.append("\n".join(block.lines))
        else:
            parts.append(_render_section(block))
    return "\n\n".join(parts)


def _render_section(block: SectionBlock) -> str:
    """Render a SectionBlock as a ### subsection.

    - ``Args`` / ``Env`` → definition list under a mapped heading.
    - ``Stdout`` / ``Returns`` → heading + plain text.
    """
    heading = _SECTION_HEADINGS.get(block.title, block.title)
    lines: list[str] = [f"### {heading}", ""]

    if block.title in _DEFLIST_SECTIONS:
        for item in block.items:
            # Items may span multiple lines (joined by \n from _group_section_items).
            # Split the header line on 2+ consecutive spaces
            # to get name + first desc line;
            # remaining lines are continuation lines indented under the definition.
            item_lines = item.split("\n")
            header = item_lines[0]
            continuations = item_lines[1:]
            parts = re.split(r"  +", header, maxsplit=1)
            if len(parts) == 2:
                name, first_desc = parts
                lines.append(f"`{name.strip()}`")
                if continuations:
                    desc = (
                        first_desc.strip()
                        + "\n"
                        + "\n".join(f"  {c}" for c in continuations)
                    )
                    lines.append(f": {desc}")
                else:
                    lines.append(f": {first_desc.strip()}")
            else:
                lines.append(f"`{item_lines[0].strip()}`")
            lines.append("")
    else:
        lines.extend(block.items)

    return "\n".join(lines).rstrip()
