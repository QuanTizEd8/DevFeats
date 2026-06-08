#!/usr/bin/env python3
"""Move lib/*.sh function docstrings from before the definition into the body.

Before::

    # @brief funcname [<args>] — One-line description.
    #
    # Longer description.
    funcname() {
      ...
    }

After::

    funcname() {
      # @brief funcname [<args>] — One-line description.
      #
      # Longer description.
      ...
    }

Single-line definitions are expanded first::

    shell__bash() { "${_BASH_BIN:-bash}" "$@"; }

    shell__bash() {
      # @brief shell__bash — Run the active bash binary.
      "${_BASH_BIN:-bash}" "$@";
    }

When the function body begins with a non-doc comment, a blank line is inserted
between the doc block and that comment so doc parsers do not absorb it.

Recognised pre-function doc blocks:
  - ``# @brief ...`` (primary convention)
  - ``# <funcname> ... (internal)`` internal helpers
  - ``# <funcname> ...`` when the first word after ``#`` matches the function name

Usage:
  move-lib-func-docs.py [--check] [path ...]

Options:
  --check   Report files that would change; exit 1 if any would.
  --help    Show this help.

Default paths: all lib/*.sh under the repository root.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PATHS = sorted((REPO_ROOT / "lib").glob("*.sh"))

FUNC_DEF_RE = re.compile(
    r"^(\s*)([a-zA-Z_][a-zA-Z0-9_]*)\(\)\s*\{(.*)$",
)
@dataclass
class FunctionSite:
    """A function definition and optional preceding doc block."""

    doc_start: int | None
    doc_end: int | None
    func_line: int
    func_end: int
    indent: str
    name: str
    oneliner_body: str | None


def _is_comment_line(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith("#")


def _is_func_doc_block(doc_lines: list[str], func_name: str) -> bool:
    if not doc_lines:
        return False
    first = doc_lines[0].strip()
    if first.startswith("# @brief "):
        return True
    if "(internal)" in first:
        return True
    after_hash = first[1:].lstrip()
    first_word = after_hash.split(None, 1)[0] if after_hash else ""
    return first_word == func_name


def _body_starts_with_comment(lines: list[str], start: int, end: int) -> bool:
    for idx in range(start, end + 1):
        stripped = lines[idx].strip()
        if not stripped:
            continue
        return stripped.startswith("#")
    return False


def _find_func_end(lines: list[str], func_line: int, indent: str) -> int:
    """Return the line index of the function's closing brace.

    Uses indent-aligned ``}`` lines instead of naive brace counting so that
    braces inside strings (e.g. ``grep -c '^{'``) do not confuse the scanner.
    """
    close_re = re.compile(rf"^{re.escape(indent)}\}}\s*$")
    for idx in range(func_line + 1, len(lines)):
        if close_re.match(lines[idx]):
            return idx
    raise ValueError(f"unclosed function starting at line {func_line + 1}")


def _opening_body_has_doc(
    lines: list[str],
    func_line: int,
    func_name: str,
    indent: str,
) -> bool:
    """Return True when the function body already begins with a doc block."""
    match = FUNC_DEF_RE.match(lines[func_line])
    if not match:
        return False

    rest = match.group(3).rstrip()
    if rest and rest.endswith("}"):
        # One-liner: no leading in-body doc is possible.
        return False

    close_re = re.compile(rf"^{re.escape(indent)}\}}\s*$")
    for idx in range(func_line + 1, len(lines)):
        if close_re.match(lines[idx]):
            return False
        stripped = lines[idx].strip()
        if not stripped:
            continue
        if stripped.startswith("# @brief "):
            return True
        if "(internal)" in stripped and stripped.startswith("#"):
            return True
        after_hash = stripped[1:].lstrip()
        first_word = after_hash.split(None, 1)[0] if after_hash else ""
        if first_word == func_name:
            return True
        return False
    return False


def _collect_preceding_doc(
    lines: list[str],
    func_line: int,
    func_name: str,
) -> tuple[int, int] | None:
    pos = func_line - 1
    while pos >= 0 and not lines[pos].strip():
        pos -= 1
    if pos < 0 or not _is_comment_line(lines[pos]):
        return None

    end = pos
    while pos >= 0 and _is_comment_line(lines[pos]):
        pos -= 1
    start = pos + 1

    doc_lines = lines[start : end + 1]
    if not _is_func_doc_block(doc_lines, func_name):
        return None
    return start, end


def _indent_doc_lines(doc_lines: list[str], body_indent: str) -> list[str]:
    indented: list[str] = []
    for line in doc_lines:
        stripped = line.lstrip()
        if stripped:
            indented.append(f"{body_indent}{stripped}")
        else:
            indented.append("")
    return indented


def _parse_function_site(lines: list[str], func_line: int) -> FunctionSite | None:
    match = FUNC_DEF_RE.match(lines[func_line])
    if not match:
        return None

    indent, name, after_brace = match.groups()
    rest = after_brace.rstrip()

    if _opening_body_has_doc(lines, func_line, name, indent):
        return None

    doc_span = _collect_preceding_doc(lines, func_line, name)
    if doc_span is None:
        return None

    if rest and rest.endswith("}"):
        func_end = func_line
    else:
        func_end = _find_func_end(lines, func_line, indent)

    doc_start, doc_end = doc_span
    oneliner_body: str | None = None
    if rest and rest.endswith("}"):
        body = rest[:-1].strip()
        if body:
            oneliner_body = body

    return FunctionSite(
        doc_start=doc_start,
        doc_end=doc_end,
        func_line=func_line,
        func_end=func_end,
        indent=indent,
        name=name,
        oneliner_body=oneliner_body,
    )


def _find_function_sites(lines: list[str]) -> list[FunctionSite]:
    sites: list[FunctionSite] = []
    for idx, line in enumerate(lines):
        if not FUNC_DEF_RE.match(line):
            continue
        site = _parse_function_site(lines, idx)
        if site is not None:
            sites.append(site)
    return sites


def _render_function(lines: list[str], site: FunctionSite) -> list[str]:
    assert site.doc_start is not None and site.doc_end is not None
    doc_lines = lines[site.doc_start : site.doc_end + 1]
    body_indent = f"{site.indent}  "
    indented_doc = _indent_doc_lines(doc_lines, body_indent)

    if site.oneliner_body is not None:
        body_lines = [f"{body_indent}{site.oneliner_body}"]
        needs_sep = site.oneliner_body.lstrip().startswith("#")
    else:
        body_lines = lines[site.func_line + 1 : site.func_end]
        needs_sep = _body_starts_with_comment(lines, site.func_line + 1, site.func_end)

    if needs_sep and indented_doc:
        indented_doc = [*indented_doc, ""]

    return [
        f"{site.indent}{site.name}() {{",
        *indented_doc,
        *body_lines,
        f"{site.indent}}}",
    ]


def transform_lines(lines: list[str]) -> list[str]:
    sites = _find_function_sites(lines)
    if not sites:
        return lines

    out = list(lines)
    for site in sorted(sites, key=lambda s: s.doc_start or 0, reverse=True):
        assert site.doc_start is not None and site.doc_end is not None
        replacement = _render_function(out, site)
        out[site.doc_start : site.func_end + 1] = replacement
    return out


def transform_text(text: str) -> str:
    had_trailing_newline = text.endswith("\n")
    lines = text.splitlines()
    new_lines = transform_lines(lines)
    result = "\n".join(new_lines)
    if had_trailing_newline:
        result += "\n"
    return result


def _display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def process_path(path: Path, *, check: bool) -> bool:
    """Transform one file. Return True when the file would change."""
    original = path.read_text(encoding="utf-8")
    updated = transform_text(original)
    if updated == original:
        return False
    label = _display_path(path)
    if check:
        print(f"would update: {label}")
    else:
        path.write_text(updated, encoding="utf-8")
        print(f"updated: {label}")
    return True


def _self_test() -> None:
    """Run built-in regression checks."""
    cases: list[tuple[str, str]] = [
      (
          "\n".join(
              [
                  "# @brief shell__bash — Run bash.",
                  "# Extra detail.",
                  'shell__bash() { "${_BASH_BIN:-bash}" "$@"; }',
                  "",
              ],
          )
          + "\n",
          "\n".join(
              [
                  "shell__bash() {",
                  "  # @brief shell__bash — Run bash.",
                  "  # Extra detail.",
                  '  "${_BASH_BIN:-bash}" "$@";',
                  "}",
                  "",
              ],
          )
          + "\n",
      ),
      (
          "\n".join(
              [
                  "# @brief shell__detect_zshdir — Detect zsh dir.",
                  "#",
                  "# Stdout: path.",
                  "shell__detect_zshdir() {",
                  "  # Ask zsh which path it uses.",
                  "  echo /etc/zsh",
                  "}",
                  "",
              ],
          )
          + "\n",
          "\n".join(
              [
                  "shell__detect_zshdir() {",
                  "  # @brief shell__detect_zshdir — Detect zsh dir.",
                  "  #",
                  "  # Stdout: path.",
                  "",
                  "  # Ask zsh which path it uses.",
                  "  echo /etc/zsh",
                  "}",
                  "",
              ],
          )
          + "\n",
      ),
      (
          "\n".join(
              [
                  "# Section header stays.",
                  "",
                  "# _helper (internal) — Do work.",
                  "#",
                  "# Returns: 0.",
                  "_helper() {",
                  "  return 0",
                  "}",
                  "",
              ],
          )
          + "\n",
          "\n".join(
              [
                  "# Section header stays.",
                  "",
                  "_helper() {",
                  "  # _helper (internal) — Do work.",
                  "  #",
                  "  # Returns: 0.",
                  "  return 0",
                  "}",
                  "",
              ],
          )
          + "\n",
      ),
      (
          "\n".join(
              [
                  "# @brief already — Done.",
                  "already() {",
                  "  # @brief already — Done.",
                  "  return 0",
                  "}",
                  "",
              ],
          )
          + "\n",
          "\n".join(
              [
                  "# @brief already — Done.",
                  "already() {",
                  "  # @brief already — Done.",
                  "  return 0",
                  "}",
                  "",
              ],
          )
          + "\n",
      ),
    ]

    for idx, (source, want) in enumerate(cases, start=1):
        got = transform_text(source)
        if got != want:
            raise AssertionError(
                f"self-test case {idx} failed\n--- want ---\n{want}--- got ---\n{got}",
            )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="report files that would change without writing",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run built-in regression checks and exit",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="lib/*.sh files (default: all under lib/)",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        _self_test()
        print("self-test: ok")
        return 0

    paths = args.paths or DEFAULT_PATHS
    missing = [p for p in paths if not p.is_file()]
    if missing:
        for path in missing:
            print(f"error: not a file: {path}", file=sys.stderr)
        return 2

    changed = False
    for path in paths:
        changed = process_path(path.resolve(), check=args.check) or changed

    return 1 if args.check and changed else 0


if __name__ == "__main__":
    raise SystemExit(main())
