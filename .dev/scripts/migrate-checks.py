#!/usr/bin/env python3
"""Migrate feature test .sh files to checks.yaml format.

Usage
-----
  python .dev/scripts/migrate-checks.py test/features/<feature>/
  python .dev/scripts/migrate-checks.py test/features/<feature>/ --dry-run

The script reads every *.sh file in <feature>/tests/, converts each one to a
checks.yaml test group, and prints the merged checks.yaml to stdout (or writes
it when --output is given).

Lines or constructs the script cannot convert automatically are preserved
verbatim and annotated with a  # TODO: review  comment so they are easy to
find and fix by hand.

What is automated (~75 % of files)
-----------------------------------
- Strips shebang, ``set -e`` / ``set -euo pipefail``,
  ``source dev-container-features-test-lib``, ``reportResults``, blank
  boilerplate lines.
- Extracts the leading ``#``-block as ``description``.
- Detects ``_cleanup() { … }`` + ``trap _cleanup EXIT`` → ``post``.
- Detects ``_test_failure_diagnostics() { … }`` → ``on_failure``.
- Code before the first check/fail_check (excluding the above) → ``pre``.
- Single-line ``check "…" cmd`` → check item.
- ``fail_check "…" cmd`` → ``kind: fail`` item.
- Consecutive echo/cat/ls/stat/printf/grep lines immediately before a check →
  ``debug`` block on that check.
- Multi-line (backslash-continued) checks are reassembled; if they are simple
  enough they are emitted as a YAML literal block scalar (``|``), otherwise
  they get a ``# TODO: review`` annotation.

What requires manual review
----------------------------
- ``checkMultiple`` calls (emit as-is with TODO).
- For-loop bodies that call ``check`` (expand manually).
- Nested quoting that cannot be round-tripped safely.
- Anything the parser cannot classify.
"""

from __future__ import annotations

import argparse
import re
import sys
import textwrap
from pathlib import Path

# ---------------------------------------------------------------------------
# Regex helpers
# ---------------------------------------------------------------------------

_SHEBANG_RE = re.compile(r"^#!")
_SETE_RE = re.compile(r"^set\s+-[a-z]*e[a-z]*\b")
_SOURCE_RE = re.compile(r"^source\s+dev-container-features-test-lib")
_REPORT_RE = re.compile(r"^reportResults\s*$")
_BLANK_RE = re.compile(r"^\s*$")
_COMMENT_RE = re.compile(r"^#")
_TRAP_RE = re.compile(r"^trap\s+_cleanup\s+EXIT")

# Function-block openers.
_CLEANUP_OPEN_RE = re.compile(r"^_cleanup\s*\(\s*\)\s*\{?\s*$")
_DIAG_OPEN_RE = re.compile(r"^_test_failure_diagnostics\s*\(\s*\)\s*\{?\s*$")

# check / fail_check call starters.
_CHECK_START_RE = re.compile(r"^(check|fail_check|checkMultiple)\s+")

# Lines treated as diagnostic output (debug field).
_DIAG_LINE_RE = re.compile(
    r"^(echo|cat|ls|stat|printf|getent|id|grep)\b|"
    r"^\"\$[A-Z_]+\"\s+--version\b|"  # e.g. "$_BREW" --version
    r"^\"?\$\w+\"\s+",                 # variable invocations used for diagnostics
)


# ---------------------------------------------------------------------------
# YAML serialisation helpers (hand-rolled to control style precisely)
# ---------------------------------------------------------------------------


def _yaml_str(value: str, indent: int = 0) -> str:
    r"""Serialise a string as a YAML literal block scalar when multi-line."""
    prefix = " " * indent
    if "\n" not in value.rstrip("\n"):
        # Single-line: emit as a plain or double-quoted scalar.
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        if any(
            c in value
            for c in ('"', "'", ":", "{", "}", "[", "]", "#", "&", "*", "!", "|", ">", "?", "-")
        ):
            return f'"{escaped}"'
        return value
    # Multi-line: use literal block scalar (|).
    body = textwrap.indent(value.rstrip("\n") + "\n", prefix + "  ")
    return f"|\n{body}"


def _emit_group(test_id: str, group: dict) -> str:
    """Serialise a single test group to YAML text."""
    lines: list[str] = [f"{test_id}:"]

    if group.get("description"):
        lines.append(f"  description: {_yaml_str(group['description'], indent=2)}")

    for key in ("pre", "post", "on_failure"):
        if group.get(key):
            val = _yaml_str(group[key], indent=2)
            lines.append(f"  {key}: {val}")

    lines.append("  checks:")
    for item in group.get("checks", []):
        if item.get("_todo"):
            lines.append("    # TODO: review this check")
        lines.append("    - title: " + _yaml_str(item["title"]))
        if item.get("kind") and item["kind"] != "check":
            lines.append(f"      kind: {item['kind']}")
        if item.get("min") is not None:
            lines.append(f"      min: {item['min']}")
        cmd = item["cmd"]
        if isinstance(cmd, list):
            lines.append("      cmd:")
            for c in cmd:
                lines.append(f"        - {_yaml_str(c)}")
        else:
            lines.append(f"      cmd: {_yaml_str(cmd, indent=6)}")
        if item.get("debug"):
            val = _yaml_str(item["debug"], indent=6)
            lines.append(f"      debug: {val}")
        if item.get("on_fail"):
            val = _yaml_str(item["on_fail"], indent=6)
            lines.append(f"      on_fail: {val}")

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Backslash-continuation reassembler
# ---------------------------------------------------------------------------


def _collect_statement(lines: list[str], start: int) -> tuple[str, int, bool]:
    """Collect a potentially backslash-continued statement into a single string.

    Returns (joined_text, next_index, is_multiline).  The returned text has the
    backslashes removed and lines joined with ``\\n``.  *is_multiline* is True
    when the original statement spanned more than one source line.
    """
    parts: list[str] = []
    i = start
    is_multiline = False
    while i < len(lines):
        line = lines[i].rstrip()
        i += 1
        if line.endswith("\\"):
            is_multiline = True
            parts.append(line[:-1].rstrip())
            # Continue to next line.
        else:
            parts.append(line)
            break
    return "\n".join(parts), i, is_multiline


# ---------------------------------------------------------------------------
# Function-block extractor
# ---------------------------------------------------------------------------


def _collect_function_body(lines: list[str], start: int) -> tuple[str, int]:
    """Collect lines inside a { … } function body starting at *start*.

    *start* points to the line **after** the opening ``{`` (or to the opening
    line if it ends with ``{``).  Returns (body_text, next_line_index).
    """
    depth = 1
    body_lines: list[str] = []
    i = start
    while i < len(lines):
        raw = lines[i]
        stripped = raw.strip()
        i += 1
        if stripped == "}":
            depth -= 1
            if depth == 0:
                break
            body_lines.append(raw.rstrip())
        elif stripped.endswith("{"):
            depth += 1
            body_lines.append(raw.rstrip())
        else:
            body_lines.append(raw.rstrip())
    # Dedent body relative to two-space function indent.
    body = textwrap.dedent("\n".join(body_lines)).strip()
    return body, i


# ---------------------------------------------------------------------------
# check-call parser
# ---------------------------------------------------------------------------

_TITLE_DQ_RE = re.compile(r'^(check|fail_check|checkMultiple)\s+"((?:[^"\\]|\\.)*)"(.*)', re.DOTALL)
_TITLE_SQ_RE = re.compile(r"^(check|fail_check|checkMultiple)\s+'([^']*)'\s*(.*)", re.DOTALL)


def _parse_check_call(stmt: str) -> dict | None:
    """Parse a reassembled check/fail_check call into a check_item dict.

    Returns None if the call cannot be parsed.
    """
    stmt = stmt.strip()

    m = _TITLE_DQ_RE.match(stmt) or _TITLE_SQ_RE.match(stmt)
    if not m:
        return None

    fn_name = m.group(1)
    title = m.group(2).replace('\\"', '"')
    rest = m.group(3).strip()

    if fn_name == "checkMultiple":
        # Leave as TODO — emit raw.
        return {"title": title, "cmd": stmt, "kind": "multiple", "_todo": True}

    item: dict = {"title": title, "cmd": rest}
    if fn_name == "fail_check":
        item["kind"] = "fail"
    return item


# ---------------------------------------------------------------------------
# Main parser for a single .sh file
# ---------------------------------------------------------------------------


def _parse_sh(path: Path) -> dict:
    """Parse a test .sh file and return a test_group dict."""
    raw = path.read_text(encoding="utf-8")
    lines = raw.splitlines()

    # --- strip leading boilerplate and collect description -----------------
    i = 0
    desc_lines: list[str] = []
    while i < len(lines):
        line = lines[i].strip()
        if _SHEBANG_RE.match(line):
            i += 1
            continue
        if _SETE_RE.match(line):
            i += 1
            continue
        if _SOURCE_RE.match(line):
            i += 1
            continue
        if _BLANK_RE.match(line):
            i += 1
            continue
        # Collect leading comment block as description.
        if _COMMENT_RE.match(line):
            # Stop description collection when we hit a non-comment after at
            # least one check or code line.
            desc_lines.append(line[1:].strip())
            i += 1
            continue
        break

    description = "\n".join(desc_lines).strip()

    # --- scan remaining lines for function blocks and code -----------------
    post_body: str = ""
    on_failure_body: str = ""
    pre_lines: list[str] = []
    check_items: list[dict] = []
    pending_debug: list[str] = []
    in_pre = True  # True until we see the first check call.

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Skip boilerplate that can appear after description.
        if _SETE_RE.match(stripped) or _SOURCE_RE.match(stripped) or _REPORT_RE.match(stripped):
            i += 1
            continue
        if _TRAP_RE.match(stripped):
            i += 1
            continue
        if _BLANK_RE.match(stripped):
            i += 1
            if in_pre:
                pre_lines.append("")
            continue

        # _cleanup() function block.
        if _CLEANUP_OPEN_RE.match(stripped):
            # Determine if opening brace is on the same line.
            if stripped.endswith("{"):
                body, i = _collect_function_body(lines, i + 1)
            else:
                # Next line should be ``{``
                i += 1
                if i < len(lines) and lines[i].strip() == "{":
                    i += 1
                body, i = _collect_function_body(lines, i)
            post_body = body
            continue

        # _test_failure_diagnostics() function block.
        if _DIAG_OPEN_RE.match(stripped):
            if stripped.endswith("{"):
                body, i = _collect_function_body(lines, i + 1)
            else:
                i += 1
                if i < len(lines) and lines[i].strip() == "{":
                    i += 1
                body, i = _collect_function_body(lines, i)
            on_failure_body = body
            continue

        # check / fail_check / checkMultiple calls.
        if _CHECK_START_RE.match(stripped):
            in_pre = False
            stmt, i, is_multiline = _collect_statement(lines, i)
            item = _parse_check_call(stmt)
            if item is None:
                # Cannot parse — emit as-is in a TODO comment.
                item = {
                    "title": f"# TODO: review — {stripped[:60]}",
                    "cmd": stmt,
                    "_todo": True,
                }
            elif is_multiline:
                # Multi-line backslash-continued checks need manual review;
                # the reassembled cmd may not be semantically equivalent.
                item["_todo"] = True
            if pending_debug:
                item["debug"] = "\n".join(pending_debug).strip()
                pending_debug = []
            check_items.append(item)
            continue

        # Lines that look like diagnostic output (echo, cat, ls …) and appear
        # *before* a check go into the next check's debug field.
        if not in_pre and _DIAG_LINE_RE.match(stripped):
            pending_debug.append(stripped)
            i += 1
            continue

        # Everything else: pre-check code or inter-check diagnostics.
        if in_pre:
            pre_lines.append(line.rstrip())
        else:
            # Code between checks that is not a diagnostic — emit as TODO.
            pending_debug.append(f"# TODO: review — {stripped}")
        i += 1

    # Flush any trailing diagnostic lines (no following check).
    if pending_debug:
        if check_items:
            last = check_items[-1]
            existing = last.get("debug", "")
            extra = "\n".join(pending_debug)
            last["debug"] = (existing + "\n" + extra).strip() if existing else extra
        else:
            pre_lines.extend(pending_debug)

    # Clean up pre_lines: strip leading/trailing blanks.
    while pre_lines and not pre_lines[0].strip():
        pre_lines.pop(0)
    while pre_lines and not pre_lines[-1].strip():
        pre_lines.pop()

    group: dict = {}
    if description:
        group["description"] = description
    if pre_lines:
        group["pre"] = "\n".join(pre_lines)
    if post_body:
        group["post"] = post_body
    if on_failure_body:
        group["on_failure"] = on_failure_body
    group["checks"] = check_items or [
        {"title": "# TODO: no checks found", "cmd": "true", "_todo": True}
    ]
    return group


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "feature_dir",
        type=Path,
        help="Path to a feature test directory (e.g. test/features/install-yq/).",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=None,
        help="Write checks.yaml here instead of printing to stdout.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be written without writing anything (implies stdout).",
    )
    parser.add_argument(
        "--only",
        metavar="TEST_ID",
        default=None,
        help="Convert only the named test script (without .sh extension).",
    )
    args = parser.parse_args()

    tests_dir = args.feature_dir / "tests"
    if not tests_dir.is_dir():
        print(f"⛔ tests/ directory not found: {tests_dir}", file=sys.stderr)
        sys.exit(1)

    if args.only:
        sh_files = [tests_dir / f"{args.only}.sh"]
    else:
        sh_files = sorted(tests_dir.glob("*.sh"))

    if not sh_files:
        print("⛔ No .sh files found.", file=sys.stderr)
        sys.exit(1)

    yaml_parts: list[str] = []
    todos: list[str] = []

    for sh_path in sh_files:
        test_id = sh_path.stem
        try:
            group = _parse_sh(sh_path)
        except Exception as exc:  # noqa: BLE001
            print(f"⚠  {sh_path.name}: parse error — {exc}", file=sys.stderr)
            group = {
                "description": f"# TODO: parse failed — {exc}",
                "checks": [{"title": "# TODO: parse failed", "cmd": "true", "_todo": True}],
            }

        # Serialise before stripping _todo so _emit_group can emit comments.
        yaml_parts.append(_emit_group(test_id, group))

        # Collect TODOs for the summary, then strip internal flag.
        for item in group.get("checks", []):
            if item.get("_todo"):
                todos.append(f"  {test_id}: {item['title']}")
            item.pop("_todo", None)

    output_text = "\n".join(yaml_parts)

    if args.output and not args.dry_run:
        args.output.write_text(output_text, encoding="utf-8")
        print(f"✔  Written to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(output_text)

    if todos:
        print(
            f"\n⚠  {len(todos)} item(s) need manual review (marked # TODO:):",
            file=sys.stderr,
        )
        for t in todos:
            print(t, file=sys.stderr)


if __name__ == "__main__":
    main()
