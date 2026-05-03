"""Generate Markdown API reference for one lib/*.sh module."""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from proman.docs.parse_lib import LibFunction, LibModule, ParagraphBlock, SectionBlock


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

    Multi-item sections (Args) become definition lists.
    Inline sections (Stdout, Returns) become a heading + text.
    """
    lines: list[str] = [f"### {block.title}", ""]
    if len(block.items) > 1 or block.title in ("Args", "Parameters"):
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
