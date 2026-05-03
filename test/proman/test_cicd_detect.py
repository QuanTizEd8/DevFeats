"""Tests for proman.cicd.detect — glob matching and macOS feature discovery."""

from unittest import mock

import proman.cicd.detect as CD


def test_recursive_double_star_matches_nested_paths():
    changed = [
        "lib/foo/bar.baz",
        "test/unit/subsuite/example.bats",
        ".devcontainer/.dev/nested/config.json",
    ]
    assert CD.any_match(changed, ["lib/**"])
    assert CD.any_match(changed, ["test/unit/**"])
    assert CD.any_match(changed, [".devcontainer/.dev/**"])


def test_no_pattern_match_returns_false():
    changed = ["docs/source/index.md", "README.md"]
    assert not CD.any_match(changed, ["lib/**", "test/unit/**"])


def test_accepts_both_single_and_two_segment_feature_paths():
    find_output = "\n".join([
        "test/features/install-git/macos/package_default.sh",
        "test/features/vendor/install-homebrew/macos/default.sh",
        "test/features/install-gh/linux/default.sh",
    ])
    with mock.patch.object(CD, "sh", return_value=find_output):
        got = CD.discover_macos_capable()
    assert got == ["install-git", "vendor/install-homebrew"]


def test_empty_find_output_returns_empty_list():
    with mock.patch.object(CD, "sh", return_value=""):
        assert CD.discover_macos_capable() == []
