#!/usr/bin/env python3
"""Static check: function-scoped variables in lib/*.sh must be declared local.

ShellCheck has no rule for this (see koalaman/shellcheck#1395). This checker
flags assignments inside functions when the target variable is not local to the
current function or an enclosing function (bash dynamic scope for nested helpers).

Intentional module globals are excluded: ALL_CAPS names (shell convention) and
names prefixed with ``_<MODULE>__`` where the prefix is derived from the checked
filename (e.g. bootstrap.sh → _BOOTSTRAP__). Additional suppressions live in
.config/lib-local-vars.allowlist.

Usage:
  lib-local-vars.py [path ...]     # default: lib/*.sh under repo root
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
ALLOWLIST = REPO_ROOT / ".config" / "lib-local-vars.allowlist"
DEFAULT_PATHS = sorted((REPO_ROOT / "lib").glob("*.sh"))

FUNC_START = re.compile(r"^([a-zA-Z_][a-zA-Z0-9_]*)?\s*\(\)\s*\{")
_MODULE_GLOBAL_RE = re.compile(r"^(_[A-Z][A-Z0-9_]*__)[\w]")
LOCAL_DECL = re.compile(r"\blocal(?:\s+-[a-zA-Z]+)*\s+([^;|&]+)")
DECLARE_DECL = re.compile(r"\bdeclare\s+(-[a-zA-Z]+)?\s+([^;|&]+)")
ASSIGN = re.compile(r"\b([a-zA-Z_][a-zA-Z0-9_]*)(\+?=)")
CASE_PATTERN = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*=\*\)\s*$")


SKIP_LINE_PREFIXES = (
    "export ",
    "readonly ",
    "declare -g",
    "declare -r",
    "local ",
    "unset ",
    "return ",
    "echo ",
    "printf ",
    "logging__",
    "case ",
    "esac",
    "if ",
    "fi",
    "then",
    "else",
    "elif ",
    "for ",
    "while ",
    "do",
    "done",
    "shift",
    "set ",
    "break",
    "continue",
    "source ",
    ". ",
    "[[",
    "((",
    "#",
    "trap ",
    "eval ",
    "exec ",
    "command ",
    "mapfile ",
    "readarray ",
)

RESERVED = frozenset(
    {
        "if",
        "then",
        "else",
        "elif",
        "fi",
        "for",
        "while",
        "do",
        "done",
        "case",
        "esac",
        "in",
        "return",
        "export",
        "local",
        "declare",
        "unset",
        "shift",
        "set",
        "echo",
        "printf",
        "test",
        "true",
        "false",
        "REPLY",
        "PWD",
        "OLDPWD",
        "HOME",
        "PATH",
        "IFS",
        "EUID",
        "UID",
        "USER",
    }
)


def derive_module_prefix(path: Path) -> str:
    """Return the ``_MODULE__`` prefix for *path*.

    Scans the file for the first assignment to a variable whose name starts
    with ``_[A-Z][A-Z0-9_]*__``.  Module-level globals are always defined at
    the top of the file before any function definitions, so the first hit is
    authoritative (e.g. ``logging-api.sh`` correctly yields ``_LOGGING__``
    rather than ``_LOGGING_API__``).  Falls back to uppercasing the file stem
    when the file defines no such globals.
    """
    for line in path.read_text().splitlines():
        m = _MODULE_GLOBAL_RE.match(line.strip())
        if m:
            return m.group(1)
    return "_" + path.stem.upper().replace("-", "_") + "__"


def is_module_global(var: str, module_prefix: str) -> bool:
    """Return whether ``var`` is an intentional module-level global name.

    Globals are either ALL_CAPS or prefixed with ``_<MODULE>__`` (e.g.
    ``_BOOTSTRAP__YQ_BIN`` in ``bootstrap.sh``).
    """
    if re.match(r"^[A-Z][A-Z0-9_]*$", var):
        return True
    return var.startswith(module_prefix)


def parse_local_names(line: str) -> set[str]:
    """Extract variable names declared ``local`` or non-global ``declare`` on a line."""
    found: set[str] = set()
    for m in LOCAL_DECL.finditer(line):
        for part in re.split(r"[\s=]+", m.group(1)):
            name = part.strip("()[]{}")
            if name and not name.startswith("-") and name not in {"true", "false"}:
                found.add(name)
    m = DECLARE_DECL.search(line)
    if m and "g" not in (m.group(1) or ""):
        for part in re.split(r"[\s=]+", m.group(2) or ""):
            name = part.strip("()[]{}")
            if name:
                found.add(name)
    return found


def load_allowlist() -> set[tuple[str, str, str]]:
    """Load ``file:function:var`` suppressions from the allowlist config file."""
    allowed: set[tuple[str, str, str]] = set()
    if not ALLOWLIST.is_file():
        return allowed
    for raw in ALLOWLIST.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(":")]
        if len(parts) != 3:
            print(f"lib-local-vars: invalid allowlist entry: {raw!r}", file=sys.stderr)
            continue
        allowed.add((parts[0], parts[1], parts[2]))
    return allowed


def walk_quotes(line: str, *, in_single: bool) -> bool:
    """Advance single-quote state across one line.

    Bash double-quoted strings are ignored for carry across lines.
    """
    in_double = False
    for ch in line:
        if ch == "#" and not in_single and not in_double:
            break
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
    return in_single


def brace_delta_outside_quotes(line: str, *, in_single_start: bool) -> int:
    """Count ``{`` and ``}`` only outside bash quotes.

    Text inside single quotes (e.g. awk programs) is ignored.
    """
    delta = 0
    in_single = in_single_start
    in_double = False
    for ch in line:
        if ch == "#" and not in_single and not in_double:
            break
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif not in_single and not in_double:
            if ch == "{":
                delta += 1
            elif ch == "}":
                delta -= 1
    return delta


def quote_state_at(line: str, pos: int, *, in_single_start: bool) -> tuple[bool, bool]:
    """Return ``(in_single, in_double)`` at ``pos`` in ``line``.

    ``in_single_start`` reflects quote state carried from prior lines.
    """
    in_single = in_single_start
    in_double = False
    for ch in line[:pos]:
        if ch == "#" and not in_single and not in_double:
            break
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
    return in_single, in_double


def assignment_in_quotes(line: str, start: int, *, in_single_start: bool) -> bool:
    """Return whether an assignment at ``start`` sits inside bash quotes."""
    in_single, in_double = quote_state_at(line, start, in_single_start=in_single_start)
    return in_single or in_double


def is_flag_or_url_param(line: str, var_start: int) -> bool:
    """Skip --opt=val, ?q=val, &q=val, setopt=opt=val false positives."""
    if var_start == 0:
        return False
    prev = line[var_start - 1]
    return prev in "-?&="


def should_skip_line(stripped: str) -> bool:
    """Return whether a stripped shell line should not be checked for assignments."""
    if stripped.startswith(SKIP_LINE_PREFIXES):
        return True
    if "awk " in stripped or " awk" in stripped:
        return True
    if stripped.startswith("git ") or " git " in stripped:
        return True
    return bool(CASE_PATTERN.match(stripped))


def check_file(path: Path, allowlist: set[tuple[str, str, str]]) -> list[str]:
    """Scan one ``lib/*.sh`` file and return human-readable issue strings."""
    rel = path.name
    module_prefix = derive_module_prefix(path)
    lines = path.read_text().splitlines()
    issues: list[str] = []

    # Stack of local-name sets; one entry per open function (outer -> inner).
    local_stack: list[set[str]] = []
    func_stack: list[str] = []
    depth = 0
    in_heredoc = False
    heredoc_term: str | None = None
    in_single_quote = False

    def scoped_locals() -> set[str]:
        merged: set[str] = set()
        for layer in local_stack:
            merged |= layer
        return merged

    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()

        if in_single_quote:
            in_single_quote = walk_quotes(line, in_single=in_single_quote)
            continue

        if in_heredoc:
            if stripped == heredoc_term or stripped.startswith(heredoc_term or ""):
                in_heredoc = False
                heredoc_term = None
            continue

        if "<<" in line:
            qpos = line.index("<<")
            if not quote_state_at(line, qpos, in_single_start=in_single_quote)[0]:
                hm = re.search(r"<<\s*'?([A-Za-z_][A-Za-z0-9_]*)'?", line)
                if hm:
                    in_heredoc = True
                    heredoc_term = hm.group(1)
                    continue

        m = FUNC_START.match(line)
        if m and not stripped.startswith("#"):
            fname = m.group(1) or "<anon>"
            func_stack.append(fname)
            local_stack.append(set())
            depth += brace_delta_outside_quotes(line, in_single_start=in_single_quote)
            in_single_quote = walk_quotes(line, in_single=in_single_quote)
            # One-line functions: `name() { ...; }` open and close on the same line.
            if depth <= 0:
                func_stack.pop()
                local_stack.pop()
                depth = 0
            continue

        if func_stack:
            depth += brace_delta_outside_quotes(line, in_single_start=in_single_quote)
            if stripped == "}" and depth <= 0:
                func_stack.pop()
                local_stack.pop()
                depth = 0
                in_single_quote = walk_quotes(line, in_single=in_single_quote)
                continue

            if local_stack:
                local_stack[-1] |= parse_local_names(line)

            if stripped.startswith("#") or should_skip_line(stripped):
                in_single_quote = walk_quotes(line, in_single=in_single_quote)
                continue

            func = func_stack[-1]
            known = scoped_locals()

            for am in ASSIGN.finditer(line):
                var = am.group(1)
                start = am.start(1)
                if var in RESERVED or is_module_global(var, module_prefix) or var in known:
                    continue
                if (rel, func, var) in allowlist:
                    continue
                if assignment_in_quotes(line, start, in_single_start=in_single_quote):
                    continue
                if is_flag_or_url_param(line, start):
                    continue
                issues.append(
                    f"{path}:{lineno}: {func}(): assignment to '{var}' without local "
                    f"(declare 'local {var}' or add to "
                    f".config/lib-local-vars.allowlist)"
                )

            in_single_quote = walk_quotes(line, in_single=in_single_quote)

    return issues


def main(argv: list[str]) -> int:
    """Run the checker on ``argv[1:]`` or all default ``lib/*.sh`` paths."""
    paths = [Path(p) for p in argv[1:]] if len(argv) > 1 else DEFAULT_PATHS
    allowlist = load_allowlist()
    all_issues: list[str] = []
    for path in paths:
        if not path.is_file():
            print(f"lib-local-vars: not a file: {path}", file=sys.stderr)
            return 2
        all_issues.extend(check_file(path, allowlist))

    if all_issues:
        print("\n".join(all_issues), file=sys.stderr)
        print(
            f"\nlib-local-vars: {len(all_issues)} issue(s). "
            "Use 'local' for function-scoped variables; see "
            ".config/lib-local-vars.allowlist.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
