"""Tests for metadata-derived variable injection into test execution contexts.

Covers:
- gen_devcontainer._render_test_script: prepends all _env_vars definitions immediately
  after the shebang (or at file start when there is no shebang).
- All keys from resolved_env_vars() are injected verbatim as bash variable names.
"""

from __future__ import annotations

import stat
from typing import TYPE_CHECKING

from proman.feature_env import resolved_env_vars

if TYPE_CHECKING:
    from pathlib import Path

from proman.test.gen_devcontainer import (
    _render_test_script as _copy_test_script_with_vars,
)

FEATURE = "setup-shim"

EXPECTED_VARS = resolved_env_vars(FEATURE)


def _make_script(tmp_path: Path, name: str, content: str) -> Path:
    p = tmp_path / name
    p.write_text(content)
    p.chmod(0o755)
    return p


def test_vars_injected_after_shebang(tmp_path: Path) -> None:
    """Variable definitions are inserted on lines 2+, right after the shebang."""
    src = _make_script(tmp_path, "src.sh", "#!/bin/bash\nset -e\necho hello\n")
    dst = tmp_path / "dst.sh"

    _copy_test_script_with_vars(src.read_text(), dst, FEATURE)

    lines = dst.read_text().splitlines()
    assert lines[0] == "#!/bin/bash", "shebang must remain on line 1"
    assert lines[1].startswith("export "), "expected injected export on line 2"
    injected_key = lines[1].split(" ", 1)[1].split("=", 1)[0]
    assert injected_key in EXPECTED_VARS, f"unexpected injected key: {injected_key!r}"
    assert "set -e" in lines
    assert "echo hello" in lines


def test_vars_injected_at_start_when_no_shebang(tmp_path: Path) -> None:
    """When there is no shebang the variable block is prepended at line 1."""
    src = _make_script(tmp_path, "src.sh", "set -e\necho hello\n")
    dst = tmp_path / "dst.sh"

    _copy_test_script_with_vars(src.read_text(), dst, FEATURE)

    lines = dst.read_text().splitlines()
    assert lines[0].startswith("export "), "expected injected export on line 1"
    injected_key = lines[0].split(" ", 1)[1].split("=", 1)[0]
    assert injected_key in EXPECTED_VARS, f"unexpected injected key: {injected_key!r}"
    assert "set -e" in lines
    assert "echo hello" in lines


def test_file_permissions_preserved(tmp_path: Path) -> None:
    """Destination file has the execute bit set."""
    src = _make_script(tmp_path, "src.sh", "#!/bin/bash\necho hi\n")
    dst = tmp_path / "dst.sh"

    _copy_test_script_with_vars(src.read_text(), dst, FEATURE)

    assert dst.stat().st_mode & stat.S_IXUSR, "destination must be executable"


def test_all_env_vars_injected(tmp_path: Path) -> None:
    """All keys from resolved_env_vars() are exported in the injected block."""
    src = _make_script(tmp_path, "src.sh", "#!/bin/bash\necho ok\n")
    dst = tmp_path / "dst.sh"

    _copy_test_script_with_vars(src.read_text(), dst, FEATURE)

    content = dst.read_text()
    for key, value in EXPECTED_VARS.items():
        assert f"export {key}=" in content, f"missing export for {key}"
        assert value in content, f"missing value for {key}: {value!r}"


def test_different_features_produce_different_paths(tmp_path: Path) -> None:
    """Two different feature IDs produce different injected values."""
    src = _make_script(tmp_path, "src.sh", "#!/bin/bash\necho ok\n")
    dst_a = tmp_path / "a.sh"
    dst_b = tmp_path / "b.sh"

    _copy_test_script_with_vars(src.read_text(), dst_a, "setup-shim")
    _copy_test_script_with_vars(src.read_text(), dst_b, "setup-user")

    content_a = dst_a.read_text()
    content_b = dst_b.read_text()

    assert "setup-shim" in content_a
    assert "setup-user" not in content_a
    assert "setup-user" in content_b
    assert "setup-shim" not in content_b
