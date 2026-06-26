"""Generate .sh test scripts from checks.yaml definitions."""

from __future__ import annotations

import argparse
import difflib
import os
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Any

import yaml

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


# ---------------------------------------------------------------------------
# Public API (called from run.py before test dispatch)
# ---------------------------------------------------------------------------


def generate_tests(
    _feature: str,
    checks_path: Path,
    out_dir: Path,
) -> None:
    """Generate .sh test files from checks.yaml into out_dir.

    Parameters
    ----------
    _feature:
        Feature name (reserved for future feature-specific logic).
    checks_path:
        Path to the checks.yaml file.
    out_dir:
        Directory where generated .sh files are written.
    """
    with checks_path.open(encoding="utf-8") as fh:
        data: dict[str, Any] = yaml.safe_load(fh) or {}

    out_dir.mkdir(parents=True, exist_ok=True)
    for test_id, group in data.items():
        content = _render_group(test_id, group)
        out_path = out_dir / f"{test_id}.sh"
        out_path.write_text(content, encoding="utf-8")
        out_path.chmod(out_path.stat().st_mode | 0o111)


# ---------------------------------------------------------------------------
# CLI entry point  (proman-test-sync-tests)
# ---------------------------------------------------------------------------


def _repo_root_from_env_or_git() -> Path:
    env = os.environ.get("REPO_ROOT")
    if env:
        return Path(env)
    return Path(
        subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
        ).strip(),
    )


def main() -> None:
    """Entry point for the proman-test-sync-tests CLI."""
    parser = argparse.ArgumentParser(
        description="Generate .sh test files from checks.yaml definitions.",
    )
    parser.add_argument(
        "feature",
        nargs="?",
        help="Feature name (e.g. install-yq); omit to sync all features.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help=(
            "Verify generated files are up-to-date without writing"
            " (exit non-zero if stale)."
        ),
    )
    parser.add_argument(
        "--repo-root",
        default=None,
        type=Path,
        help="Repository root (default: auto-detected via REPO_ROOT env or git).",
    )
    args = parser.parse_args()

    repo_root: Path = args.repo_root or _repo_root_from_env_or_git()
    features_test_dir = repo_root / "test" / "features"

    if args.feature:
        candidates = [features_test_dir / args.feature]
    else:
        candidates = sorted(
            p
            for p in features_test_dir.iterdir()
            if p.is_dir() and (p / "checks.yaml").exists()
        )

    stale: list[str] = []

    for feat_dir in candidates:
        checks_path = feat_dir / "checks.yaml"
        if not checks_path.exists():
            if args.feature:
                print(
                    f"⛔ No checks.yaml found for feature: {args.feature}",
                    file=sys.stderr,
                )
                sys.exit(1)
            continue

        tests_dir = feat_dir / "tests"
        feature_name = feat_dir.name

        with checks_path.open(encoding="utf-8") as fh:
            data: dict[str, Any] = yaml.safe_load(fh) or {}

        for test_id, group in data.items():
            content = _render_group(test_id, group)
            out_path = tests_dir / f"{test_id}.sh"

            if args.check:
                existing = (
                    out_path.read_text(encoding="utf-8") if out_path.exists() else ""
                )
                if existing != content:
                    diff = difflib.unified_diff(
                        existing.splitlines(keepends=True),
                        content.splitlines(keepends=True),
                        fromfile=str(out_path),
                        tofile=f"{test_id}.sh (generated)",
                    )
                    sys.stdout.writelines(diff)
                    stale.append(str(out_path))
            else:
                tests_dir.mkdir(parents=True, exist_ok=True)
                out_path.write_text(content, encoding="utf-8")
                out_path.chmod(out_path.stat().st_mode | 0o111)
                print(f"  ✔  {feature_name}/{test_id}.sh")

    if args.check and stale:
        print(
            f"\n⛔ {len(stale)} generated test file(s) are stale."
            " Run `just sync-tests` to update.",
            file=sys.stderr,
        )
        sys.exit(1)
