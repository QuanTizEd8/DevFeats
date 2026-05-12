"""Tests for proman.const — shared formula functions."""

from __future__ import annotations

from proman.const import export_profile_d, feat_share_dir


def test_feat_share_dir_formula() -> None:
    """feat_share_dir produces the expected /usr/local/share path."""
    assert feat_share_dir("install-foo", "myowner", "myrepo") == (
        "/usr/local/share/myowner/myrepo/install-foo"
    )


def test_export_profile_d_formula() -> None:
    """export_profile_d produces the expected profile.d filename."""
    assert export_profile_d("install-foo", "myowner", "myrepo") == (
        "myowner-myrepo-install-foo-export-path.sh"
    )
