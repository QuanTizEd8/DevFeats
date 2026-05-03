"""Generate Markdown API reference for one lib/*.sh module."""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from proman.docs.parse_lib import LibFunction, LibModule, ParagraphBlock, SectionBlock

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


def generate(module: LibModule) -> str:
    """Generate API reference Markdown for a lib/*.sh module.

    Parameters
    ----------
    module : LibModule
        Parsed module returned by ``parse_lib_module``.

    Returns
    -------
    str
        Full Markdown content for ``docs/source/library/<name>.md``.
    """
    parts: list[str] = [f"# `{module.name}`"]
    if module.summary:
        parts.append(module.summary)
    if module.description:
        parts.append(module.description)
    for func in module.functions:
        parts.append(_render_function(func))
    return "\n\n".join(parts) + "\n"


# ── Internal helpers ──────────────────────────────────────────────────────────


def _render_function(func: LibFunction) -> str:
    """Render a single LibFunction as a Markdown ## subsection."""
    from proman.docs.parse_lib import ParagraphBlock, SectionBlock

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
            # Split param name from description on 2+ consecutive spaces.
            parts = re.split(r"  +", item, maxsplit=1)
            if len(parts) == 2:
                name, desc = parts
                lines.append(f"`{name.strip()}`")
                lines.append(f": {desc.strip()}")
            else:
                lines.append(f"`{item.strip()}`")
            lines.append("")
    else:
        lines.extend(block.items)

    return "\n".join(lines).rstrip()
