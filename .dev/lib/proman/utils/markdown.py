"""Utilities for processing markdown."""

from __future__ import annotations

import re


def sanitize(text: str) -> str:
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
