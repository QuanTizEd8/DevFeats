"""Render .sh test scripts from checks.yaml definitions."""

from __future__ import annotations

import textwrap
from typing import Any

# ---------------------------------------------------------------------------
# Internal rendering helpers
# ---------------------------------------------------------------------------


def _desc_block(description: str) -> str:
    """Format a description string as bash comment lines (no trailing blank line)."""
    if not description:
        return ""
    lines = description.rstrip("\n").splitlines()
    return "".join(f"# {line}\n" for line in lines)


def _indent_body(text: str) -> str:
    """Indent a multi-line shell block by two spaces."""
    return textwrap.indent(text.rstrip("\n"), "  ") + "\n"


def _dquote(s: str) -> str:
    """Wrap a string in double quotes, escaping any interior double quotes."""
    return '"' + s.replace('"', '\\"') + '"'


def _render_item(item: dict[str, Any], idx: int) -> str:
    """Render a single check_item to one or more bash lines (ending with newline)."""
    kind = item.get("kind", "check")
    title = item["title"]
    raw_cmd = item.get("cmd")
    debug = (item.get("debug") or "").strip()
    on_fail = (item.get("on_fail") or "").strip()

    parts: list[str] = []

    # Unconditional diagnostic output before the check.
    if debug:
        parts.append(debug + "\n")

    # Snapshot _TEST_FAIL before the check so we can detect a new failure.
    if on_fail:
        parts.append(f'_df{idx}="$_TEST_FAIL"\n')

    qtitle = _dquote(title)

    if kind == "multiple":
        min_val = item["min"]
        cmds: list[str] = raw_cmd
        lines = [f"checkMultiple {qtitle} {min_val} \\"]
        for i, c in enumerate(cmds):
            suffix = " \\" if i < len(cmds) - 1 else ""
            lines.append(f"  {_dquote(c)}{suffix}")
        parts.append("\n".join(lines) + "\n")
    elif kind == "install_failure":
        # Validated by the test runner on the single install attempt; not emitted
        # into generated .sh scripts.
        return ""
    else:
        if raw_cmd is None:
            msg = f"check item {title!r} (kind={kind!r}) requires 'cmd'"
            raise KeyError(msg)
        fn = "fail_check" if kind == "fail" else "check"
        if isinstance(raw_cmd, str) and "\n" in raw_cmd.rstrip("\n"):
            cmd_indented = _indent_body(raw_cmd)
            parts.append(f"{fn} {qtitle} \\\n{cmd_indented}")
        else:
            if isinstance(raw_cmd, bool):
                cmd = "true" if raw_cmd else "false"
            elif isinstance(raw_cmd, str):
                cmd = raw_cmd.strip()
            else:
                cmd = str(raw_cmd)
            parts.append(f"{fn} {qtitle} {cmd}\n")

    # Conditional on_fail block: runs only when this check introduced a failure.
    if on_fail:
        indented = _indent_body(on_fail)
        parts.append(f'[ "$_TEST_FAIL" -eq "$_df{idx}" ] || {{\n{indented}}}\n')

    return "".join(parts)


def _render_group(test_id: str, group: dict[str, Any]) -> str:  # noqa: ARG001
    """Render one test_group dict to complete .sh file content."""
    description = (group.get("description") or "").rstrip("\n")
    shell = (group.get("shell") or "bash").strip()
    pre = (group.get("pre") or "").rstrip("\n")
    post = (group.get("post") or "").rstrip("\n")
    on_failure = (group.get("on_failure") or "").rstrip("\n")
    checks: list[dict[str, Any]] = group["checks"]

    shebang = f"#!/usr/bin/env {shell}"

    sections: list[str] = []

    # ── Header ───────────────────────────────────────────────────────────────
    desc_block = _desc_block(description)
    sections.append(
        f"{shebang}\n"
        f"{desc_block}"
        f"# AUTO-GENERATED from checks.yaml — DO NOT EDIT\n"
        f"set -e\n"
        f"\n"
        f". dev-container-features-test-lib\n",
    )

    # ── _cleanup() from `post` ────────────────────────────────────────────────
    if post:
        body = _indent_body(post)
        sections.append(f"\n_cleanup() {{\n{body}}}\ntrap _cleanup EXIT\n")

    # ── _test_failure_diagnostics() from `on_failure` ─────────────────────────
    if on_failure:
        body = _indent_body(on_failure)
        sections.append(f"\n_test_failure_diagnostics() {{\n{body}}}\n")

    # ── `pre` content (verbatim) ──────────────────────────────────────────────
    if pre:
        sections.append(f"\n{pre}\n")

    # ── check items ───────────────────────────────────────────────────────────
    check_lines: list[str] = []
    for idx, item in enumerate(checks):
        check_lines.append(_render_item(item, idx))

    if check_lines:
        sections.append("\n" + "".join(check_lines))

    # ── footer ────────────────────────────────────────────────────────────────
    sections.append("\nreportResults\n")

    return "".join(sections)
