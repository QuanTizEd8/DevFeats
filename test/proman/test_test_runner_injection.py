"""Tests for formula-derived variable injection into test execution contexts.

Covers:
- gen_devcontainer._copy_test_script_with_vars: prepends _FEAT_SHARE_DIR and
  _EXPORT_PROFILE_D definitions immediately after the shebang (or at file start
  when there is no shebang).
"""

from __future__ import annotations

import stat
from pathlib import Path

import pytest

from proman.const import export_profile_d, feat_share_dir
from proman.test.gen_devcontainer import _copy_test_script as _copy_test_script_with_vars


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

OWNER = "testowner"
REPO = "testrepo"
FEATURE = "install-foo"

EXPECTED_SHARE = feat_share_dir(FEATURE, OWNER, REPO)
EXPECTED_PROFILE_D = export_profile_d(FEATURE, OWNER, REPO)


def _make_script(tmp_path: Path, name: str, content: str) -> Path:
    p = tmp_path / name
    p.write_text(content)
    p.chmod(0o755)
    return p


# ---------------------------------------------------------------------------
# _copy_test_script_with_vars
# ---------------------------------------------------------------------------


def test_vars_injected_after_shebang(tmp_path: Path) -> None:
    """Variable definitions are inserted on line 2, right after the shebang."""
    src = _make_script(tmp_path, "src.sh", "#!/bin/bash\nset -e\necho hello\n")
    dst = tmp_path / "dst.sh"

    _copy_test_script_with_vars(src, dst, FEATURE, OWNER, REPO)

    lines = dst.read_text().splitlines()
    assert lines[0] == "#!/bin/bash", "shebang must remain on line 1"
    assert f"_FEAT_SHARE_DIR={EXPECTED_SHARE}" in lines[1]
    assert f"_EXPORT_PROFILE_D={EXPECTED_PROFILE_D}" in lines[2]
    # Original body must be preserved
    assert "set -e" in lines
    assert "echo hello" in lines


def test_vars_injected_at_start_when_no_shebang(tmp_path: Path) -> None:
    """When there is no shebang the variable block is prepended at line 1."""
    src = _make_script(tmp_path, "src.sh", "set -e\necho hello\n")
    dst = tmp_path / "dst.sh"

    _copy_test_script_with_vars(src, dst, FEATURE, OWNER, REPO)

    lines = dst.read_text().splitlines()
    assert f"_FEAT_SHARE_DIR={EXPECTED_SHARE}" in lines[0]
    assert f"_EXPORT_PROFILE_D={EXPECTED_PROFILE_D}" in lines[1]
    assert "set -e" in lines
    assert "echo hello" in lines


def test_file_permissions_preserved(tmp_path: Path) -> None:
    """Destination file inherits the execute bit from the source."""
    src = _make_script(tmp_path, "src.sh", "#!/bin/bash\necho hi\n")
    dst = tmp_path / "dst.sh"

    _copy_test_script_with_vars(src, dst, FEATURE, OWNER, REPO)

    assert dst.stat().st_mode & stat.S_IXUSR, "destination must be executable"


def test_vars_contain_correct_feature_paths(tmp_path: Path) -> None:
    """Injected values match what const.py formulas produce for the given feature."""
    src = _make_script(tmp_path, "src.sh", "#!/bin/bash\necho ok\n")
    dst = tmp_path / "dst.sh"

    _copy_test_script_with_vars(src, dst, FEATURE, OWNER, REPO)

    content = dst.read_text()
    assert EXPECTED_SHARE in content
    assert EXPECTED_PROFILE_D in content


def test_different_features_produce_different_paths(tmp_path: Path) -> None:
    """Two different feature IDs produce different injected values."""
    src = _make_script(tmp_path, "src.sh", "#!/bin/bash\necho ok\n")
    dst_a = tmp_path / "a.sh"
    dst_b = tmp_path / "b.sh"

    _copy_test_script_with_vars(src, dst_a, "install-foo", OWNER, REPO)
    _copy_test_script_with_vars(src, dst_b, "install-bar", OWNER, REPO)

    content_a = dst_a.read_text()
    content_b = dst_b.read_text()

    assert "install-foo" in content_a
    assert "install-bar" not in content_a
    assert "install-bar" in content_b
    assert "install-foo" not in content_b
