"""Source-level portability contracts for production shell code."""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _tracked_production_shell_sources() -> list[Path]:
    """Return tracked Bash/POSIX shell sources under production directories."""
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "ls-files", "-z", "--", "features", "lib"],
        check=True,
        capture_output=True,
    )
    return [
        REPO_ROOT / name.decode()
        for name in result.stdout.split(b"\0")
        if name and Path(name.decode()).suffix in {".bash", ".sh"}
    ]


def test_production_shell_sources_do_not_use_busybox_incompatible_file_rm_d() -> None:
    """Empty directories use the portable file__rmdir wrapper, never rm -d."""
    offenders = [
        source.relative_to(REPO_ROOT)
        for source in _tracked_production_shell_sources()
        if "file__rm -d" in source.read_text(encoding="utf-8")
    ]
    assert offenders == []
