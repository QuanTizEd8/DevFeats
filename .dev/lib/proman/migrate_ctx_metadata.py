#!/usr/bin/env python3
"""Text-safe codemod for metadata when keys and pattern tokens."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

WHEN_KEY_REPLACEMENTS = [
    (r"(?<![a-z0-9_.])arch:", "plat.machine_release:"),
    (r"(?<![a-z0-9_.])kernel:", "plat.kernel:"),
    (r"(?<![a-z0-9_.])pm:", "plat.pm:"),
    (r"(?<![a-z0-9_.])deb_arch:", "plat.deb_arch:"),
    (r"(?<![a-z0-9_.])id:", "os.id:"),
    (r"(?<![a-z0-9_.])id_like:", "os.id_like:"),
    (r"(?<![a-z0-9_.])version_codename:", "os.version_codename:"),
    (r"(?<![a-z0-9_.])version_id_major:", "os.version_id_major:"),
    (r"(?<![a-z0-9_.])version_id_mm:", "os.version_id_mm:"),
    (r"(?<![a-z0-9_.])version_id:", "os.version_id:"),
]

SEMVER_REPLACEMENTS = [
    (r"semver_lte:\s*([\"']?[^,\}\n]+[\"']?)", r"feat.version: {lte: \1}"),
    (r"semver_lt:\s*([\"']?[^,\}\n]+[\"']?)", r"feat.version: {lt: \1}"),
    (r"semver_gte:\s*([\"']?[^,\}\n]+[\"']?)", r"feat.version: {gte: \1}"),
    (r"semver_gt:\s*([\"']?[^,\}\n]+[\"']?)", r"feat.version: {gt: \1}"),
    (r"semver:\s*([\"']?[^,\}\n]+[\"']?)", r"feat.version: \1"),
]

# Conditional pattern keys ({KEY==…}) — base qualified keys, no case flavors.
COND_PATTERN_REPLACEMENTS = [
    (r"\{VERSION_INPUT([>=<!?])", r"{feat.version_input\1"),
    (r"\{OS_ARCH([>=<!?])", r"{plat.machine\1"),
    (r"\{KERNEL([>=<!?])", r"{plat.kernel\1"),
    (r"\{ARCH([>=<!?])", r"{plat.machine_release\1"),
    (r"\{LIBC([>=<!?])", r"{plat.libc\1"),
    (r"\{OS([>=<!?])", r"{plat.kernel\1"),
    (r"\{PREFIX([>=<!?])", r"{feat.prefix\1"),
]

TOKEN_MAP = {
    "{VERSION_INPUT}": "{feat.version_input}",
    "{OS_ARCH}": "{plat.machine}",
    "{KERNEL}": "{plat.kernel}",
    "{ARCH}": "{plat.machine_release}",
    "{LIBC}": "{plat.libc}",
    "{OS}": "{plat.kernel:lower}",
    "{OS_ID}": "{os.id}",
    "{PLATFORM}": "{plat.platform}",
    "{RUST_TRIPLE}": "{plat.rust_triple}",
    "{VERSION}": "{feat.version}",
    "{TAG}": "{feat.tag}",
    "{METHOD}": "{feat.method}",
    "{PREFIX}": "{feat.prefix}",
    "{deb_arch}": "{plat.deb_arch:lower}",
    "{id}": "{os.id}",
    "{version_codename}": "{os.version_codename}",
    "{version_id_major}": "{os.version_id_major}",
    "{version_id_mm}": "{os.version_id_mm}",
    "{version_id}": "{os.version_id}",
    "{OS:gh}": "{plat.kernel_gh}",
    "{OS:macos}": "{plat.kernel_macos}",
    "{OS:osx}": "{plat.kernel_osx}",
    "{ARCH:gh}": "{plat.machine_gh}",
    "{ARCH:node}": "{plat.machine_node}",
    "{ARCH:bitness}": "{plat.machine_bitness}",
}

TOKEN_PREFIX_REPLACEMENTS = [
    (r"\{OS:gh", "{plat.kernel_gh"),
    (r"\{OS:osx", "{plat.kernel_osx"),
    (r"\{OS:macos", "{plat.kernel_macos"),
    (r"\{ARCH:gh", "{plat.machine_gh"),
    (r"\{ARCH:node", "{plat.machine_node"),
    (r"\{ARCH:bitness", "{plat.machine_bitness"),
]


def dedupe_qualified_keys(text: str) -> str:
    while True:
        new = text
        new = new.replace("plat.plat.", "plat.")
        new = new.replace("os.os.", "os.")
        new = new.replace("feat.feat.", "feat.")
        if new == text:
            return text
        text = new


def migrate_text(text: str) -> str:
    for pat, repl in WHEN_KEY_REPLACEMENTS:
        text = re.sub(pat, repl, text)
    for pat, repl in SEMVER_REPLACEMENTS:
        text = re.sub(pat, repl, text)
    for pat, repl in COND_PATTERN_REPLACEMENTS:
        text = re.sub(pat, repl, text)
    text = re.sub(r"\{VERSION([>=<!?])", r"{feat.version\1", text)
    text = re.sub(r"\{TAG([>=<!?])", r"{feat.tag\1", text)
    for pat, repl in TOKEN_PREFIX_REPLACEMENTS:
        text = re.sub(pat, repl, text)
    for old in sorted(TOKEN_MAP, key=len, reverse=True):
        text = text.replace(old, TOKEN_MAP[old])
    return dedupe_qualified_keys(text)


def migrate_file(path: Path) -> bool:
    raw = path.read_text()
    new = migrate_text(raw)
    if new != raw:
        path.write_text(new)
        return True
    return False


def main() -> int:
    changed = 0
    for pattern in (
        "features/*/metadata.yaml",
        "features/*/manifests/**/*.yaml",
        "features/*/manifests/**/*.yml",
        "test/features/**/scenarios.yaml",
        "test/features/**/checks.yaml",
        "test/lib/cases/**/*.yaml",
    ):
        for path in sorted(ROOT.glob(pattern)):
            if migrate_file(path):
                print(path)
                changed += 1
    print(f"migrated {changed} files", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
